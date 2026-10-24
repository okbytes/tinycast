import AppKit

/// Owns launcher activation: the one funnel from a palette row to whatever the entry's kind runs.
@MainActor
final class LauncherCoordinator {
    private let ranking: LauncherRankingStore
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let systemActionCoordinator: SystemActionCoordinator
    private let windowCommandCoordinator: WindowCommandCoordinator
    /// The sibling coordinators a command hands off to.
    private unowned let core: AppCore

    init(
        ranking: LauncherRankingStore,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        systemActionCoordinator: SystemActionCoordinator,
        windowCommandCoordinator: WindowCommandCoordinator,
        core: AppCore
    ) {
        self.ranking = ranking
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.systemActionCoordinator = systemActionCoordinator
        self.windowCommandCoordinator = windowCommandCoordinator
        self.core = core
    }

    // MARK: - Activation

    func launch(_ app: AppEntry, searchQuery: String? = nil) {
        // A category word is no search for the row: learning it would rank the row under "s".
        if !CommandCatalog.isQueryDriven(app) {
            let term = searchQuery.flatMap {
                AppEntry.Kind.matching(by: LauncherOrder.CategoryQuery($0)).contains(app.kind) ? nil : $0
            }
            ranking.visit(itemKey: app.preferenceKey, query: term)
        }
        switch app.kind {
        case .application:
            paletteCoordinator.hidePalette(restoreFocus: false)
            AppLauncher.launch(app.url)
        case .command:
            guard let id = CommandCatalog.command(for: app) else { return }
            // Query-driven: only this row knows the URL the typed text resolved to.
            if id == .openInBrowser {
                paletteCoordinator.hidePalette(restoreFocus: false)
                AppLauncher.open(app.url)
                return
            }
            // Dispatched with the palette still up: mode-switching commands keep it open.
            runCommand(id)
        case .systemAction:
            guard let action = SystemActionCatalog.action(forEntryID: app.id) else { return }
            systemActionCoordinator.runSystemAction(id: action.id)
        case .windowCommand:
            guard let command = WindowCommandCatalog.command(forEntryID: app.id) else { return }
            windowCommandCoordinator.runWindowCommand(id: command.id)
        case .folderCommand:
            guard let id = FolderCommand.id(fromEntryID: app.id) else { return }
            core.folderCommandCoordinator.run(id: id)
        }
    }

    /// The one funnel a built-in command runs through, from a palette row or its global shortcut.
    func runCommand(_ id: CommandID) {
        switch id {
        case .calculatorHistory:
            paletteCoordinator.togglePalette(mode: .calculatorHistory)
        case .clipboardHistory:
            paletteCoordinator.togglePalette(mode: .clipboard)
        case .pasteSequentially:
            core.clipboardCoordinator.pasteNextInSequence()
        case .searchEmoji:
            paletteCoordinator.togglePalette(mode: .emoji)
        case .openCamera:
            dismissPalette()
            Task { await core.cameraCoordinator.show() }
        case .define:
            core.dictionaryCoordinator.show()
        case .openInBrowser:
            break  // Query-driven: it runs where the typed text is, never through this funnel.
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// A shortcut runs these with nothing open, where a plain hide would still reset palette state.
    private func dismissPalette() {
        guard paletteCoordinator.isVisible else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
    }

    // MARK: - Row actions

    func resetRanking(for app: AppEntry) {
        ranking.reset(itemKey: app.preferenceKey)
    }

    func showInFinder(_ app: AppEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    /// Focus is never handed back: the relaunch takes it, or the app that refused has it.
    func restart(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await AppLauncher.restart(bundleID: bundleID, url: app.url) }
    }

    /// Quits the app behind an entry; a no-op (palette stays put) when it isn't running.
    func quit(_ app: AppEntry, force: Bool = false) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        // Nothing here takes focus, so hand it back unless that app is on its way out.
        let quittingPreviousApp = windowController.previousApp?.bundleIdentifier == bundleID
        guard AppLauncher.quit(bundleID: bundleID, force: force) else { return }
        paletteCoordinator.hidePalette(restoreFocus: !quittingPreviousApp)
    }
}
