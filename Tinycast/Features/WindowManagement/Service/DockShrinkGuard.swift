import AppKit
import os
@preconcurrency import ApplicationServices

/// Undoes macOS or an app fitting a tile above a hidden Dock. docs/features/window-management.md
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

    /// Lets a Dock transition finish, so the restore lands after the app's last re-fit.
    private static let settleDelay = Duration.milliseconds(500)
    /// An app that re-applies the shrink this often wins; fighting it would only jitter.
    private static let restoreLimit = 2
    private static let insistenceWindow: TimeInterval = 10
    private static let capacity = 16

    private let logger = Logger(subsystem: "com.tinycast.app", category: "window-management")
    /// Oldest first, so the one evicted past `capacity` is always `watches[0]`.
    private var watches: [Watch] = []

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
    }

    private func drop(_ watch: Watch) {
        watch.settle?.cancel()
        if let observer = watch.observer {
            AXWindowAccess.stopObserving(watch.window, with: observer)
        }
        watches.removeAll { $0 === watch }
    }

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
            watch.settle?.cancel()
            watch.settle = Task { [weak self] in
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled else { return }
                self?.restore(watch)
            }
        }
    }

    private func restore(_ watch: Watch) {
        guard watches.contains(where: { $0 === watch }),
            let current = AXWindowAccess.frame(of: watch.window),
            WindowPlacementEngine.heldFrameChange(
                from: watch.held, to: current, tolerance: AXWindowAccess.clampTolerance)
                == .dockShrink
        else { return }

        let now = Date()
        watch.restores.removeAll { now.timeIntervalSince($0) > Self.insistenceWindow }
        guard watch.restores.count < Self.restoreLimit else {
            logger.notice("Stopped holding pid \(watch.pid, privacy: .public)'s window over the Dock: the app insists")
            return drop(watch)
        }
        watch.restores.append(now)
        let lift = Double(watch.held.maxY - current.maxY)
        logger.notice("Restored pid \(watch.pid, privacy: .public)'s window, lifted \(lift, privacy: .public) pt for the Dock")

        let application = AXWindowAccess.application(for: watch.pid)
        let restoreEnhancedUI = AXWindowAccess.suppressEnhancedUserInterface(on: application)
        defer { restoreEnhancedUI() }
        _ = AXWindowAccess.write(
            watch.held, anchor: watch.anchor, to: watch.window, current: current, canResize: true,
            canvas: nil)
    }
}
