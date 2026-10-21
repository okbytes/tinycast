import AppKit

/// Owns summoning the palette and nothing else; where and how big stays with the controller.
@MainActor
final class PaletteCoordinator {
    private let palette: PaletteState
    private let appIndex: AppIndex
    private let windowController: PaletteWindowController
    /// Features whose launcher rows are read from outside Tinycast re-read them on each open.
    var onLauncherShown: (() -> Void)?

    init(
        palette: PaletteState,
        appIndex: AppIndex,
        windowController: PaletteWindowController
    ) {
        self.palette = palette
        self.appIndex = appIndex
        self.windowController = windowController
    }

    // MARK: - Palette control

    var isVisible: Bool { windowController.isVisible }

    /// The app an action acts on: the one displaced, else what a hotkey found frontmost.
    var targetApp: NSRunningApplication? {
        windowController.isVisible
            ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
    }

    /// The own window the palette covered, for anything acting on it after the palette hides.
    var previousOwnWindow: NSWindow? { windowController.previousOwnWindow }

    /// Up and pointed at `mode`, which is the state a mode command's second invocation closes.
    func isShowing(_ mode: PaletteMode) -> Bool {
        windowController.isVisible && palette.mode == mode
    }

    func togglePalette() {
        if isShowing(.launcher) {
            hidePalette()
        } else {
            showPalette(mode: .launcher, restoreAnyMode: true)
        }
    }

    func togglePalette(mode: PaletteMode) {
        if isShowing(mode) {
            hidePalette()
        } else {
            showPalette(mode: mode)
        }
    }

    /// Navigating keeps the screen under as the back step; the launcher is the root and never has one.
    func navigate(to mode: PaletteMode) {
        if windowController.isVisible, palette.mode != mode, mode != .launcher {
            palette.push(mode: mode)
        } else {
            palette.prepare(mode: mode)
        }
    }

    /// Shows the palette, honoring Pop to Root Search. See docs/features/palette.md#state-flow.
    func showPalette(mode: PaletteMode, restoreAnyMode: Bool = false) {
        let preserved = windowController.consumePreservedState()
        let restoring = preserved && (restoreAnyMode || palette.mode == mode)
        // Resetting a screen the pop to root already reset would only re-render the whole palette.
        let alreadyFresh = windowController.isPoppedToRoot && palette.mode == mode
        if !(restoring || alreadyFresh) {
            navigate(to: mode)
        }
        windowController.show()
        // Re-scan on open so an app uninstalled since the last scan drops out of the launcher,
        // unless a scan just ended: reopens come in bursts, and each scan is a filesystem walk.
        if palette.mode == .launcher {
            Task { await appIndex.refreshIfStale() }
            onLauncherShown?()
        }
    }

    func hidePalette(restoreFocus: Bool = true) {
        windowController.hide(restoreFocus: restoreFocus)
    }

    /// A row dragged out and landed is a finished errand, so the palette leaves as after a paste.
    func dragLanded() {
        hidePalette(restoreFocus: false)
    }

    /// Reset to the root search now rather than after the Pop to Root Search delay.
    func popToRootNow() {
        windowController.popToRootNow()
    }

    /// True for the slim compact bar: launcher root, empty, not overflowed.
    var paletteIsCollapsed: Bool {
        // `queryIsEmpty`, not the query: it flips at the edge, so the shell ignores keystrokes.
        !palette.forceExpanded
            && palette.mode == .launcher
            && palette.queryIsEmpty
    }

    /// The compact bar's overflow: expand into the full launcher without typing.
    func expandFromCompact() {
        palette.forceExpanded = true
    }

    /// Resize the panel to the current collapsed state, when it flips while open.
    func syncPaletteSize() {
        windowController.applyCollapsed(paletteIsCollapsed)
    }
}
