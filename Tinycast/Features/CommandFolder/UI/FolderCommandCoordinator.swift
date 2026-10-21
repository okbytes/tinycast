import AppKit

/// Owns the command folder: discovery into the launcher slice, and the one run funnel.
@MainActor
@Observable
final class FolderCommandCoordinator {
    /// The folder's commands as rows, rebuilt only when the folder itself changes.
    private(set) var entries: [AppEntry] = []

    private let settings: AppSettings
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    /// Nil until a read succeeds, so the first one after launch always sweeps.
    @ObservationIgnored private var commands: [FolderCommand]?
    @ObservationIgnored private var monitor: CommandFolderMonitor?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// When the last successful read ended; a summon inside `AppIndex.rescanInterval` keeps it.
    @ObservationIgnored private var lastReadEnded: ContinuousClock.Instant?

    init(
        settings: AppSettings, appIndex: AppIndex, hotKeys: HotKeyManager,
        visibility: VisibilityStore, ranking: LauncherRankingStore, aliases: AliasStore,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// The chosen folder, else the default beside the settings file.
    var folder: URL {
        let path = settings.commandFolder
        guard !path.isEmpty else { return AppPaths.commandFolder() }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// There is no switch: an empty or missing folder is simply an empty section.
    func start() {
        applyFolder()
    }

    /// Re-armed on the new folder; the old read is dropped so same-named files are re-read.
    func applyFolder() {
        let monitor = CommandFolderMonitor(folder: folder)
        monitor.onChange = { [weak self] in self?.refresh() }
        monitor.start()
        self.monitor = monitor
        commands = nil
        refresh()
    }

    /// A chosen folder is kept `~`-relative, so a backup lands it in the other Mac's home.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        settings.commandFolder = (chosen.path as NSString).abbreviatingWithTildeInPath
    }

    func name(of id: String) -> String? {
        commands?.first { $0.id == id }?.name
    }

    // MARK: - Discovery

    /// A folder read is a directory walk, so it runs off main; an overlapping request is dropped.
    func refresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            let folder = self.folder
            let found = await Task.detached { CommandFolderScanner.scan(folder) }.value
            refreshTask = nil
            // An unreadable folder keeps the last good read, and with it every alias and binding.
            guard let found else { return }
            lastReadEnded = .now
            guard found != commands else { return }
            commands = found
            entries = found.map { AppEntry($0, folder: folder) }
            appIndex.setFolderCommands(entries)
            removeReferences(toCommandsMissingFrom: found)
        }
    }

    /// A summon's refresh, on the same staleness rule as the app scan.
    func refreshIfStale() {
        if let lastReadEnded, ContinuousClock.now - lastReadEnded < AppIndex.rescanInterval {
            return
        }
        refresh()
    }

    /// Frees what a removed file held. An empty folder is a real reading, so it frees everything.
    private func removeReferences(toCommandsMissingFrom live: [FolderCommand]) {
        let keys = Array(aliases.aliases.keys) + visibility.hiddenItemKeys + ranking.visits.keys
        let bound = Set(hotKeys.boundFolderCommandIDs)
        let stale = FolderCommand.staleIDs(referencedBy: keys, bound: bound, live: live)
        guard !stale.isEmpty else { return }
        for id in stale.intersection(bound) {
            let action = HotKeyAction.folderCommand(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        let entryIDs = Set(stale.map(FolderCommand.entryID(for:)))
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    // MARK: - Running

    /// The one funnel for a launcher row and a global shortcut alike.
    func run(id: String) {
        guard let command = commands?.first(where: { $0.id == id }) else { return }
        switch command.kind {
        case .link(let url):
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
            AppLauncher.open(url)
        case .script:
            // Focus goes back first: a script usually acts on whatever the user was in.
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette() }
            let script = folder.appending(path: command.id)
            let isExecutable = FileManager.default.isExecutableFile(atPath: script.path)
            let home = FileManager.default.homeDirectoryForCurrentUser
            Task {
                do throws(FolderCommandRunner.Failure) {
                    try await FolderCommandRunner.run(
                        script: script, isExecutable: isExecutable, in: home)
                } catch {
                    await core.showNotice(
                        title: "Couldn’t Run \(command.name)", message: error.localizedDescription,
                        symbol: FolderCommand.scriptSymbol, tone: .danger)
                }
            }
        }
    }

    /// Made on the way, so the first visit lands in a folder rather than an error.
    func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        AppLauncher.showInFinder(folder)
    }
}
