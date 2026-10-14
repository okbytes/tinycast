import AppKit

/// The one funnel from a palette row or a global hotkey to the mover.
@MainActor
final class WindowCommandCoordinator {
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    private let windowMover: WindowMover

    init(settings: AppSettings, paletteCoordinator: PaletteCoordinator, windowMover: WindowMover) {
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.windowMover = windowMover
    }

    /// The one funnel for palette and hotkey alike. See docs/features/window-management.md#wiring.
    func runWindowCommand(id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        windowMover.perform(
            id, target: handOffTarget(), gap: CGFloat(settings.windowGap),
            cycle: settings.windowCycle)
    }

    /// The window to place, read before the palette hides and hands focus back to it.
    private func handOffTarget() -> WindowTarget? {
        guard paletteCoordinator.isVisible else { return WindowTarget.current() }
        let target = WindowTarget.behindPalette(
            ownWindow: paletteCoordinator.previousOwnWindow, app: paletteCoordinator.targetApp)
        paletteCoordinator.hidePalette(restoreFocus: true)
        return target
    }
}
