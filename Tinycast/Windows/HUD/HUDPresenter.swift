import AppKit
import SwiftUI

/// How a HUD comes and goes: one at a time, replace, fade, dwell, fade away.
@MainActor
final class HUDPresenter {
    /// How far the panel sits above the bottom of the visible frame.
    private let edgeInset: CGFloat
    private let dwell: TimeInterval
    private let screen: () -> NSScreen?
    private var panel: HUDPanel?
    private var dismissal: Task<Void, Never>?

    init(edgeInset: CGFloat, dwell: TimeInterval, screen: @escaping () -> NSScreen?) {
        self.edgeInset = edgeInset
        self.dwell = dwell
        self.screen = screen
    }

    /// Progress has no dwell, so it waits to be replaced.
    func show(_ view: some View, dwells: Bool = true) {
        let panel = panel ?? make()
        let host = NSHostingView(rootView: view)
        // Never size from `host.frame` after attaching: AppKit resets it to the content rect.
        let content = host.fittingSize
        host.setFrameSize(content)
        panel.setContentSize(content)
        panel.contentView = host
        place(panel)
        // A panel on screen may be mid-fade, so bring it back rather than start another.
        if panel.isVisible {
            panel.cancelFade()
        } else {
            panel.fadeIn(duration: Theme.Duration.enter) { panel.orderFrontRegardless() }
        }
        if dwells { scheduleDismissal() } else { dismissal?.cancel() }
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        dismissal = Task { [weak self, dwell] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self?.panel?.fadeOut(duration: Theme.Duration.exit)
        }
    }

    private func make() -> HUDPanel {
        let panel = HUDPanel()
        self.panel = panel
        return panel
    }

    private func place(_ panel: NSPanel) {
        guard let visible = screen()?.visibleFrame else { return }
        panel.setFrameOrigin(
            NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + edgeInset))
    }
}
