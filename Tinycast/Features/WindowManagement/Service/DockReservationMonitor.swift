import AppKit
import os

/// Records what macOS does to the Dock's reservation and to windows, for the hidden-Dock bug.
/// See docs/features/window-management.md#recording-dock-episodes.
@MainActor
final class DockReservationMonitor {
    private struct Window {
        let owner: String
        let bounds: CGRect
    }

    private static let pollInterval: TimeInterval = 2
    private nonisolated static let logger = Logger(
        subsystem: "com.tinycast.app", category: "dock-watch")

    /// Public on purpose: `log show` redacts anything else, and these lines are the whole point.
    private nonisolated static func log(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }

    private var tokens: [NotificationToken] = []
    private var poll: Task<Void, Never>?
    private var lastScreens = ""
    private var lastDock = ""
    private var windows: [Int: Window] = [:]
    /// Display id → when a Dock-side inset last appeared on it.
    private var episodes: [Int: Date] = [:]

    func start() {
        guard poll == nil else { return }
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let (screens, dock) = (Self.describeScreens(), Self.describeDock())
        lastScreens = screens
        lastDock = dock
        windows = Self.onScreenWindows()
        Self.log("start; screens \(screens); dock \(dock)")

        tokens.append(
            NotificationToken(
                app.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.screensChanged(reason: "notified") }
                }, center: app))
        let appEvents: [(Notification.Name, String)] = [
            (NSWorkspace.didActivateApplicationNotification, "activated"),
            (NSWorkspace.didLaunchApplicationNotification, "launched"),
            (NSWorkspace.didTerminateApplicationNotification, "quit"),
        ]
        for (name, verb) in appEvents {
            tokens.append(
                NotificationToken(
                    workspace.addObserver(forName: name, object: nil, queue: .main) { note in
                        let app =
                            note.userInfo?[NSWorkspace.applicationUserInfoKey]
                            as? NSRunningApplication
                        Self.log("\(verb) \(app?.localizedName ?? "?")")
                    }, center: workspace))
        }
        let plainEvents: [(Notification.Name, String)] = [
            (NSWorkspace.activeSpaceDidChangeNotification, "space changed"),
            (NSWorkspace.screensDidSleepNotification, "screens slept"),
            (NSWorkspace.screensDidWakeNotification, "screens woke"),
            (NSWorkspace.didWakeNotification, "system woke"),
            (NSWorkspace.sessionDidResignActiveNotification, "session resigned"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session active"),
        ]
        for (name, label) in plainEvents {
            tokens.append(
                NotificationToken(
                    workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                        Self.log(label)
                    }, center: workspace))
        }

        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollInterval), tolerance: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                tick()
            }
        }
    }

    deinit {
        poll?.cancel()
    }

    // MARK: - Observations

    private func screensChanged(reason: String) {
        let screens = Self.describeScreens()
        let dock = Self.describeDock()
        Self.log("screens \(reason): \(screens); dock \(dock); \(Self.describeMouse())")
        lastScreens = screens
        lastDock = dock
        noteEpisodes()
    }

    /// An inset on a Dock edge, appearing or clearing, is what the whole record is for.
    private func noteEpisodes() {
        for screen in NSScreen.screens {
            let id = Self.displayID(screen)
            let inset = Int(AXScreens.dockReservation(of: screen))
            if inset > 0, episodes[id] == nil {
                episodes[id] = Date()
                Self.log("episode began on \(screen.localizedName): \(inset) pt reserved")
            } else if inset == 0, let began = episodes.removeValue(forKey: id) {
                let seconds = Int(Date().timeIntervalSince(began))
                Self.log("episode ended on \(screen.localizedName) after \(seconds) s")
            }
        }
    }

    private func tick() {
        let screens = Self.describeScreens()
        if screens != lastScreens { screensChanged(reason: "changed silently") }

        let dock = Self.describeDock()
        if dock != lastDock {
            lastDock = dock
            Self.log("dock \(dock); \(Self.describeMouse())")
        }

        let current = Self.onScreenWindows()
        for (id, window) in current {
            guard let old = windows[id], old.bounds != window.bounds,
                Self.keepsTopLeftAndWidth(old.bounds, window.bounds)
            else { continue }
            let lift = Int(old.bounds.maxY - window.bounds.maxY)
            let edge = "bottom \(Int(old.bounds.maxY)) → \(Int(window.bounds.maxY))"
            if lift > 0 {
                Self.log("shrink \(window.owner) #\(id): \(edge), \(lift) pt; \(Self.describeMouse())")
            } else if NSEvent.pressedMouseButtons == 0 {
                Self.log("grow \(window.owner) #\(id): \(edge)")
            }
        }
        windows = current
    }

    // MARK: - Readings

    private static func describeScreens() -> String {
        NSScreen.screens.map { screen in
            let frame = screen.frame
            let visible = screen.visibleFrame
            let insets =
                "menu \(Int(frame.maxY - visible.maxY)) bottom \(Int(visible.minY - frame.minY))"
                + " left \(Int(visible.minX - frame.minX)) right \(Int(frame.maxX - visible.maxX))"
            return "\(screen.localizedName) \(rect(frame)) visible \(rect(visible)) (\(insets))"
        }.joined(separator: "; ")
    }

    /// The Dock's own windows that are on screen, so a reveal or a hide is in the record.
    private static func describeDock() -> String {
        let dock = windowList().compactMap { info -> String? in
            guard info[kCGWindowOwnerName as String] as? String == "Dock",
                let layer = info[kCGWindowLayer as String] as? Int, layer >= 0,
                let bounds = bounds(of: info)
            else { return nil }
            return "layer \(layer) \(rect(bounds))"
        }
        return dock.isEmpty ? "no windows" : dock.joined(separator: ", ")
    }

    private static func describeMouse() -> String {
        let mouse = NSEvent.mouseLocation
        return "mouse \(Int(mouse.x)),\(Int(mouse.y)) buttons \(NSEvent.pressedMouseButtons)"
    }

    private static func onScreenWindows() -> [Int: Window] {
        var windows: [Int: Window] = [:]
        for info in windowList() {
            guard let id = info[kCGWindowNumber as String] as? Int,
                info[kCGWindowLayer as String] as? Int == 0,
                let owner = info[kCGWindowOwnerName as String] as? String,
                let bounds = bounds(of: info), bounds.width > 50, bounds.height > 50
            else { continue }
            windows[id] = Window(owner: owner, bounds: bounds)
        }
        return windows
    }

    private static func windowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private static func bounds(of info: [String: Any]) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary)
    }

    private static func keepsTopLeftAndWidth(_ old: CGRect, _ new: CGRect) -> Bool {
        abs(old.minX - new.minX) <= 1 && abs(old.minY - new.minY) <= 1
            && abs(old.width - new.width) <= 1
    }

    private static func displayID(_ screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .intValue ?? screen.localizedName.hashValue
    }

    private static func rect(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
    }
}
