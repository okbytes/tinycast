import AppKit
import os
@preconcurrency import ApplicationServices

/// Undoes macOS or an app fitting a window above a hidden Dock. docs/features/window-management.md
@MainActor
final class DockShrinkGuard {
    /// The observer's refcon points here unretained, so `watches` owns it until `drop`.
    @MainActor
    private final class Watch {
        weak var owner: DockShrinkGuard?
        let pid: pid_t
        let window: AXUIElement
        let held: CGRect
        let anchor: WindowPlacementEngine.Anchor
        var observer: AXObserver?
        var restores: [Date] = []
        var settle: Task<Void, Never>?

        init(
            owner: DockShrinkGuard, pid: pid_t, window: AXUIElement, held: CGRect,
            anchor: WindowPlacementEngine.Anchor
        ) {
            self.owner = owner
            self.pid = pid
            self.window = window
            self.held = held
            self.anchor = anchor
        }
    }

    /// A window, held or not, that was shortened to the reservation's line while it stood.
    private struct Shortened {
        let pid: pid_t
        let before: CGRect
        let after: CGRect
    }

    /// Lets a Dock transition finish, so the restore lands after the app's last re-fit.
    private static let settleDelay = Duration.milliseconds(500)
    private static let episodePollInterval = Duration.seconds(2)
    /// An app that re-applies the shrink this often wins; fighting it would only jitter.
    private static let restoreLimit = 2
    private static let insistenceWindow: TimeInterval = 10
    private static let capacity = 16

    private let logger = Logger(subsystem: "com.tinycast.app", category: "window-management")
    /// Oldest first, so the one evicted past `capacity` is always `watches[0]`.
    private var watches: [Watch] = []
    private var screensToken: NotificationToken?
    private var reservationStands = AXScreens.dockReservationStands
    /// Every on-screen window's frame as the reservation appeared, by window number.
    private var episodeWindows: [Int: (pid: pid_t, frame: CGRect)] = [:]
    private var shortened: [Int: Shortened] = [:]
    private var episodePoll: Task<Void, Never>?
    private var episodeEnd: Task<Void, Never>?

    init() {
        let center = NotificationCenter.default
        screensToken = NotificationToken(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.screensChanged() }
            }, center: center)
    }

    deinit {
        episodePoll?.cancel()
        episodeEnd?.cancel()
    }

    /// Holds `frame` until the window is changed some other way, closed, or placed again.
    func hold(
        _ frame: CGRect, anchor: WindowPlacementEngine.Anchor, of window: AXUIElement, pid: pid_t
    ) {
        release(window)
        let watch = Watch(owner: self, pid: pid, window: window, held: frame, anchor: anchor)
        watch.observer = AXWindowAccess.observe(
            window, pid: pid, callback: Self.windowChanged,
            refcon: Unmanaged.passUnretained(watch).toOpaque())
        guard watch.observer != nil else { return }
        watches.append(watch)
        if watches.count > Self.capacity { drop(watches[0]) }
    }

    func release(_ window: AXUIElement) {
        watches.filter { CFEqual($0.window, window) }.forEach(drop)
    }

    func release(pid: pid_t) {
        watches.filter { $0.pid == pid }.forEach(drop)
        shortened = shortened.filter { $0.value.pid != pid }
    }

    private func drop(_ watch: Watch) {
        watch.settle?.cancel()
        if let observer = watch.observer {
            AXWindowAccess.stopObserving(watch.window, with: observer)
        }
        watches.removeAll { $0 === watch }
    }

    // MARK: - Held windows

    /// Delivered on the main run loop, but a C callback still reaches the actor only by a hop.
    private nonisolated static let windowChanged: AXObserverCallback = { _, _, name, refcon in
        guard let refcon else { return }
        let watch = Unmanaged<Watch>.fromOpaque(refcon).takeUnretainedValue()
        let notification = name as String
        Task { @MainActor in watch.owner?.windowChanged(watch, notification: notification) }
    }

    private func windowChanged(_ watch: Watch, notification: String) {
        guard watches.contains(where: { $0 === watch }) else { return }
        // A held mouse button is the user dragging the window, which makes it theirs again.
        guard notification != kAXUIElementDestroyedNotification, NSEvent.pressedMouseButtons == 0,
            let current = AXWindowAccess.frame(of: watch.window)
        else { return drop(watch) }

        switch WindowPlacementEngine.heldFrameChange(
            from: watch.held, to: current, tolerance: AXWindowAccess.clampTolerance)
        {
        case .unchanged:
            return
        case .other:
            drop(watch)
        case .dockShrink:
            // A write now would only be clamped to the same line; the episode's end restores it.
            guard !reservationStands else { return }
            scheduleRestore(watch)
        }
    }

    private func scheduleRestore(_ watch: Watch) {
        watch.settle?.cancel()
        watch.settle = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.restore(watch)
        }
    }

    private func restore(_ watch: Watch) {
        guard watches.contains(where: { $0 === watch }), !reservationStands,
            let current = AXWindowAccess.frame(of: watch.window),
            WindowPlacementEngine.heldFrameChange(
                from: watch.held, to: current, tolerance: AXWindowAccess.clampTolerance)
                == .dockShrink
        else { return }

        let now = Date()
        watch.restores.removeAll { now.timeIntervalSince($0) > Self.insistenceWindow }
        guard watch.restores.count < Self.restoreLimit else {
            logger.notice(
                "Stopped holding pid \(watch.pid, privacy: .public)'s window over the Dock: the app insists"
            )
            return drop(watch)
        }
        watch.restores.append(now)
        let lift = Int(watch.held.maxY - current.maxY)
        logger.notice(
            "Restored pid \(watch.pid, privacy: .public)'s window, lifted \(lift, privacy: .public) pt for the Dock"
        )
        write(watch.held, anchor: watch.anchor, to: watch.window, pid: watch.pid, current: current)
    }

    private func write(
        _ frame: CGRect, anchor: WindowPlacementEngine.Anchor, to window: AXUIElement, pid: pid_t,
        current: CGRect
    ) {
        let application = AXWindowAccess.application(for: pid)
        let restoreEnhancedUI = AXWindowAccess.suppressEnhancedUserInterface(on: application)
        defer { restoreEnhancedUI() }
        _ = AXWindowAccess.write(
            frame, anchor: anchor, to: window, current: current, canResize: true, canvas: nil)
    }

    // MARK: - Episodes

    private func screensChanged() {
        let stands = AXScreens.dockReservationStands
        guard stands != reservationStands else { return }
        reservationStands = stands
        if stands { beginEpisode() } else { endEpisode() }
    }

    private func beginEpisode() {
        episodeEnd?.cancel()
        episodeWindows = Self.onScreenWindows()
        shortened = [:]
        logger.notice(
            "The Dock reserved its space; watching \(self.episodeWindows.count, privacy: .public) windows"
        )
        episodePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.episodePollInterval)
                guard let self, !Task.isCancelled else { return }
                noteShortened()
            }
        }
    }

    /// Apps re-fit lazily, often only on activation, so the whole episode is watched, not its start.
    private func noteShortened() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        for (id, window) in Self.onScreenWindows() {
            guard shortened[id] == nil, let before = episodeWindows[id], before.pid == window.pid,
                WindowPlacementEngine.heldFrameChange(
                    from: before.frame, to: window.frame, tolerance: AXWindowAccess.clampTolerance)
                    == .dockShrink
            else { continue }
            shortened[id] = Shortened(pid: window.pid, before: before.frame, after: window.frame)
            let lift = Int(before.frame.maxY - window.frame.maxY)
            logger.notice(
                "Saw pid \(window.pid, privacy: .public)'s window shortened \(lift, privacy: .public) pt to the Dock's line"
            )
        }
    }

    private func endEpisode() {
        episodePoll?.cancel()
        episodePoll = nil
        noteShortened()
        episodeWindows = [:]
        let counts = "\(shortened.count) shortened, \(watches.count) held"
        logger.notice("The Dock let go; \(counts, privacy: .public) windows to check")
        episodeEnd = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard let self, !Task.isCancelled else { return }
            restoreAfterEpisode()
        }
    }

    private func restoreAfterEpisode() {
        for watch in watches { restore(watch) }
        let pending = shortened
        shortened = [:]
        // A held window was just rewritten, so it no longer sits at `after` and is skipped here.
        for window in pending.values {
            guard let element = Self.axWindow(pid: window.pid, framed: window.after) else {
                logger.notice(
                    "No window of pid \(window.pid, privacy: .public) sits where the shortened one was; left alone"
                )
                continue
            }
            let lift = Int(window.before.maxY - window.after.maxY)
            logger.notice(
                "Put back pid \(window.pid, privacy: .public)'s window once the Dock let go, \(lift, privacy: .public) pt"
            )
            write(
                window.before, anchor: .topLeading, to: element, pid: window.pid,
                current: window.after)
        }
    }

    // MARK: - Window readings

    /// Layer-0 windows of other apps, in the same top-left space AX reports.
    private static func onScreenWindows() -> [Int: (pid: pid_t, frame: CGRect)] {
        let own = ProcessInfo.processInfo.processIdentifier
        guard
            let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]]
        else { return [:] }
        var windows: [Int: (pid: pid_t, frame: CGRect)] = [:]
        for info in list {
            guard let id = info[kCGWindowNumber as String] as? Int,
                info[kCGWindowLayer as String] as? Int == 0,
                let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != own,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                frame.width > 50, frame.height > 50
            else { continue }
            windows[id] = (pid, frame)
        }
        return windows
    }

    /// The app's window sitting where the shortened one was seen; frames are the only shared key.
    private static func axWindow(pid: pid_t, framed frame: CGRect) -> AXUIElement? {
        let application = AXWindowAccess.application(for: pid)
        return AXWindowAccess.windows(in: application).first { window in
            guard AXWindowAccess.isEligible(window), let current = AXWindowAccess.frame(of: window)
            else { return false }
            let tolerance = AXWindowAccess.clampTolerance
            return abs(current.minX - frame.minX) <= tolerance
                && abs(current.minY - frame.minY) <= tolerance
                && abs(current.width - frame.width) <= tolerance
                && abs(current.height - frame.height) <= tolerance
        }
    }
}
