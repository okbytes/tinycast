import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case application
        case command
        case systemAction
        case windowCommand
        case appleShortcut

        var descriptor: KindDescriptor {
            switch self {
            case .application:
                return KindDescriptor(
                    label: "Application", sectionTitle: "Applications",
                    openVerb: "Open Application", canHideFromSearch: true,
                    canRevealInFinder: true, canDragOut: true, isSymbolIcon: false, rankPriority: 4)
            case .command:
                return KindDescriptor(
                    label: "Command", sectionTitle: "Commands",
                    openVerb: "Run Command", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .systemAction:
                return KindDescriptor(
                    label: "System Action", sectionTitle: "System Actions",
                    openVerb: "Run System Action", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowCommand:
                return KindDescriptor(
                    label: "Window Command", sectionTitle: "Window Management",
                    openVerb: "Move Window", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .appleShortcut:
                // File-backed so every row draws the Shortcuts app's own icon.
                return KindDescriptor(
                    label: "Apple Shortcut", sectionTitle: "Apple Shortcuts",
                    openVerb: "Run Shortcut", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: false, rankPriority: 3)
            }
        }
    }

    /// Fixed per kind: a new `Kind` case fails to build until it names every field.
    struct KindDescriptor: Sendable {
        let label: String
        let sectionTitle: String
        let openVerb: String
        /// Only where Settings lists a per-item checkbox to put it back: a hide is never one-way.
        let canHideFromSearch: Bool
        let canRevealInFinder: Bool
        /// Only an application: a shortcut dropped on another app opens nothing there.
        let canDragOut: Bool
        let isSymbolIcon: Bool
        /// Breaks a full tie, apps first: Calculator over Calculator History.
        let rankPriority: Int
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    /// Set when a feature pane, not this entry's category pane, lists its controls and gates it.
    var settingsOwner: SettingsTab?
    /// Secondary label beside the name, for an entry whose name alone can't say what it acts on.
    var subtitle: String?
    /// Ranked like the name: a translation, a rename, `CFBundleAlternateNames`.
    var alternateTitles: [String] = []
    /// Found by, never ranked by: a declared name.
    var keywords: [String] = []
    /// Moves when the bundle's icon changes on disk, retiring the cached bitmap. Applications only.
    var iconStamp: Int = 0
    /// When it landed on disk, so a fresh install can be suggested before its first open.
    var installedAt: Date?
    /// The searchable form of every field above, built at publish by `buildSearchProfile`.
    var search = SearchProfile.unnamed

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    /// What this entry is called, in the shape `EntryNaming` reads.
    var naming: EntryNaming.Sources {
        var sources = EntryNaming.Sources(name: name)
        sources.alternateTitles = alternateTitles
        sources.subtitle = subtitle
        sources.keywords = keywords
        return sources
    }

    /// Built once per index change, never per keystroke; only `AppIndex.named` calls it.
    mutating func buildSearchProfile() { search = EntryNaming.profile(for: naming) }

    /// Only a name the entry lacks adds anything; a bundle usually spells itself the same twice.
    mutating func addAlternateTitle(_ candidate: String) {
        let existing = [name] + alternateTitles
        guard !candidate.isEmpty,
            !existing.contains(where: {
                FuzzyMatch.normalized($0) == FuzzyMatch.normalized(candidate)
            })
        else { return }
        alternateTitles.append(candidate)
    }

    var kindLabel: String { kind.descriptor.label }

    /// The hotkey action for this entry, or nil when the entry has no addressable action.
    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .command:
            return CommandCatalog.command(for: self)?.hotKeyAction
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemAction:
            return SystemActionCatalog.action(forEntryID: id).map { .systemAction(id: $0.id) }
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id).map { .windowCommand(id: $0.id) }
        case .appleShortcut:
            return AppleShortcut.id(fromEntryID: id).map { .appleShortcut(id: $0) }
        }
    }

    /// Synthetic entries have no file to reveal; a destination is its record's own action.
    var canRevealInFinder: Bool { kind.descriptor.canRevealInFinder }

    var canHideFromSearch: Bool { kind.descriptor.canHideFromSearch }

    var canDragOut: Bool { kind.descriptor.canDragOut }

    /// What this row draws, and the only thing any icon path needs to ask.
    var iconSource: EntryIcon { defaultIcon }

    /// Derived from the kind alone: synthetic entries get a symbol tile, everything else its file.
    private var defaultIcon: EntryIcon {
        guard kind.descriptor.isSymbolIcon else { return .file(stamp: iconStamp) }
        return .symbol(kindSymbol)
    }

    private var kindSymbol: String {
        switch kind {
        case .command: return CommandCatalog.command(for: self)?.sfSymbol ?? "questionmark"
        case .systemAction: return SystemActionCatalog.action(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .application, .appleShortcut: return "questionmark"
        }
    }

    /// Main-actor because it subscribes the calling view; every caller is a `body`.
    @MainActor var icon: NSImage {
        IconCache.observeStyle()
        return IconCache.icon(for: iconSource, fileURL: url)
    }

    /// Icon identity for a row's async load: re-skinning changes the glyph while `id` stays put.
    var iconKey: String { "\(id)|\(iconSource)" }
}

extension AppEntry {
    init(_ command: WindowCommand) {
        self.init(
            id: command.entryID, name: command.name,
            url: URL(string: "tinycast://window-command/" + command.id.rawValue)!,
            bundleID: nil, kind: .windowCommand)
    }

    /// No bundle id: that would key every shortcut's alias and ranking to the Shortcuts app.
    init(_ shortcut: AppleShortcut, applicationURL: URL) {
        self.init(
            id: shortcut.entryID, name: shortcut.name, url: applicationURL, bundleID: nil,
            kind: .appleShortcut)
    }
}

extension AppEntry.Kind {
    private static let byCategoryName: [String: AppEntry.Kind] = allCases.reduce(into: [:]) {
        $0[FuzzyMatch.normalized($1.descriptor.sectionTitle)] = $1
        $0[FuzzyMatch.normalized($1.descriptor.label)] = $1
    }

    private static let categoryNames = allCases.map { kind in
        (kind, [kind.descriptor.sectionTitle, kind.descriptor.label].map(FuzzyMatch.Candidate.init))
    }

    static func named(by query: LauncherOrder.CategoryQuery) -> AppEntry.Kind? {
        byCategoryName[query.name]
    }

    static func matching(by query: LauncherOrder.CategoryQuery) -> Set<AppEntry.Kind> {
        if let kind = named(by: query) { return [kind] }
        return Set(
            categoryNames.compactMap { kind, names in
                names.contains(where: query.matches) ? kind : nil
            })
    }
}

@MainActor
@Observable
final class AppIndex {
    private(set) var apps: [AppEntry] = []

    /// The launcher's rows in order, with the size of each leading section at their head.
    struct Results: Equatable {
        var entries: [AppEntry] = []
        var favoriteCount = 0
        var suggestionCount = 0
        var matchCount = 0
    }

    private struct MatchKey: Equatable {
        let query: String
        let limit: Int
        let entriesRevision: Int
        let rankingRevision: Int
        let aliasRevision: Int
        let sensitivity: SearchSensitivity
    }

    private struct ResultsKey: Equatable {
        let match: MatchKey
        let visibilityRevision: Int
        let favoritesRevision: Int
        let hotKeysRevision: Int
        let showsSuggestions: Bool
        /// Suggestions and usage order age with the clock, which no revision tracks.
        let minute: Int
    }

    /// Repeated renders for the same query reuse the ranking instead of re-matching every frame.
    @ObservationIgnored private var matchMemo = Memo<MatchKey, Results>()
    @ObservationIgnored private var resultsMemo = Memo<ResultsKey, Results>()
    /// Bumped whenever `apps` changes, so both memos above name the entry set they were built from.
    private var entriesRevision = 0

    private static let systemActionEntries: [AppEntry] = SystemActionCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://system-action/" + command.id.rawValue)!,
                bundleID: nil, kind: .systemAction)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private static let allWindowCommandEntries: [AppEntry] = WindowCommandCatalog.all
        .map(AppEntry.init)
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var discoveredEntries: [AppEntry] = []
    private var windowCommandEntries: [AppEntry] = []
    private var appleShortcutEntries: [AppEntry] = []
    /// The catalog's commands a disabled feature hides; the Commands slice is recomputed from it.
    private var hiddenCommands: Set<CommandID> = []
    private var nameCache = BundleNameCache()
    private var isRefreshing = false
    /// Set when a refresh lands mid-scan, so a scope edit is never silently dropped.
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private var settings: AppSettings?
    /// Fired after every scan, even an unchanged one: LaunchServices can trail a deletion by seconds.
    @ObservationIgnored var onScan: (() -> Void)?

    init(ranking: LauncherRankingStore, aliases: AliasStore) {
        self.ranking = ranking
        self.aliases = aliases
    }

    /// The always-relevant built-ins, plus whatever a disabled feature has not hidden.
    private var commandEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .command }
    }

    private var visibleCatalogEntries: [AppEntry] {
        CommandCatalog.all.filter {
            guard let command = CommandCatalog.command(for: $0) else { return true }
            return !hiddenCommands.contains(command)
        }
    }

    /// Whether the feature behind a command is on, which is what its shortcut has to obey too.
    func isCommandEnabled(_ command: CommandID) -> Bool {
        !hiddenCommands.contains(command)
    }

    /// A feature's commands leave the Commands slice when it is off; `visible` restores them.
    func setCommandsVisible(_ commands: Set<CommandID>, _ visible: Bool) {
        let updated = visible ? hiddenCommands.subtracting(commands) : hiddenCommands.union(commands)
        guard updated != hiddenCommands else { return }
        hiddenCommands = updated
        publishEntries()
    }

    /// Discovered from the Shortcuts app, so it arrives already built and sorted.
    func setAppleShortcuts(_ entries: [AppEntry]) {
        guard entries != appleShortcutEntries else { return }
        appleShortcutEntries = entries
        publishEntries()
    }

    /// Shows or hides the window-command slice; the catalog itself is static.
    func setWindowCommandsVisible(_ visible: Bool) {
        let entries = visible ? Self.allWindowCommandEntries : []
        guard entries != windowCommandEntries else { return }
        windowCommandEntries = entries
        publishEntries()
    }

    /// Wires the scopes, re-indexing on edit rather than waiting for the next open.
    func start(settings: AppSettings) {
        self.settings = settings
        observeSearchScopes()
    }

    /// Fires synchronously on main before the write lands, so the task re-arms, then rescans.
    private func observeSearchScopes() {
        withObservationTracking {
            _ = settings?.searchScopes
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSearchScopes()
                await self.refresh()
            }
        }
    }

    /// Re-scan on every open; reopens collapse, and an unchanged set does no UI work.
    func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let scopes = settings?.searchScopes ?? SearchScopes.defaults
            let languages = BundleLocalization.indexedLanguages(Locale.preferredLanguages)
            let reusing = BundleNameCache(reusing: nameCache, languages: languages)
            let (found, cache) = await Task.detached(priority: .utility) {
                AppIndex.scan(scopes: scopes, cache: reusing)
            }.value
            nameCache = cache
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
        onScan?()
    }

    /// Out of the index *and* unknown to LaunchServices, so dropping a search scope isn't a delete.
    func isUninstalled(bundleID: String) -> Bool {
        !discoveredEntries.contains { $0.kind == .application && $0.bundleID == bundleID }
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil
    }

    nonisolated private static func scan(
        scopes: [String], cache: BundleNameCache
    ) -> ([AppEntry], BundleNameCache) {
        Signposts.interval("AppIndex.scan") {
            var cache = cache
            var indexByBundleID: [String: Int] = [:]
            var result: [AppEntry] = []
            for url in SearchScopes.appBundles(in: scopes) {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                let fileName = EntryNaming.strippingAppExtension(url.lastPathComponent)
                // Dedup by bundle id; the first scope wins, but a renamed copy lends its name.
                if let bundleID, let first = indexByBundleID[bundleID] {
                    result[first].addAlternateTitle(fileName)
                    continue
                }

                // Finder's rule: LaunchServices ignores a display name the file name contradicts.
                let names = cache.names(
                    for: url, base: fileName, developmentRegion: bundle?.developmentLocalization)
                // Raw: Calendar's strings file swaps its `iCal` array for a name.
                let alternates = bundle?.infoDictionary?["CFBundleAlternateNames"] as? [String] ?? []
                // Still searchable, never the label: `code` must keep finding Visual Studio Code.
                let declared = [bundle?.installedAppName].compactMap { $0 }
                var entry = AppEntry(
                    id: url.path, name: names.first ?? fileName, url: url, bundleID: bundleID,
                    kind: .application, alternateTitles: Array(names.dropFirst()) + alternates,
                    keywords: declared, iconStamp: FileIconStamp.value(for: url),
                    installedAt: try? url.resourceValues(forKeys: [.addedToDirectoryDateKey])
                        .addedToDirectoryDate)
                entry.addAlternateTitle(fileName)
                if let bundleID { indexByBundleID[bundleID] = result.count }
                result.append(entry)
            }
            // Slice order is section order, so the flat selection maps 1:1 onto rows.
            let apps = result.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            // Named here, not at publish: romanizing a CJK index is ~50 ms of main-actor time.
            return (AppIndex.named(apps), cache)
        }
    }

    /// The searchable form of every name an entry carries. `scan` names the app slice itself.
    nonisolated private static func named(_ entries: [AppEntry]) -> [AppEntry] {
        entries.map { entry in
            var entry = entry
            entry.buildSearchProfile()
            return entry
        }
    }

    private func publishEntries() {
        // Each slice arrives in its own display order; the slice order is the section order.
        let updated =
            discoveredEntries
            + Self.named(
                appleShortcutEntries
                    + Self.systemActionEntries
                    + windowCommandEntries
                    + commandEntries)
        guard updated != apps else { return }
        apps = updated
        entriesRevision &+= 1
    }

    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        searchResults(query, limit: limit).entries
    }

    /// Ranked matches lead so Return still opens the best one; a started category only appends.
    private func searchResults(_ query: String, limit: Int = 200) -> Results {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Results(entries: apps) }
        return matchMemo.value(for: matchKey(q, limit: limit)) {
            let category = LauncherOrder.CategoryQuery(q)
            if let kind = AppEntry.Kind.named(by: category) {
                return Results(entries: categoryListing(kind, query: category.name))
            }
            let ranked = rank(q, limit: limit)
            let listed = categoryRemainder(AppEntry.Kind.matching(by: category), excluding: ranked)
            return Results(entries: ranked + listed, matchCount: ranked.count)
        }
    }

    /// Slice order is section order, so filtering keeps sections and selection aligned.
    private func categoryListing(_ kind: AppEntry.Kind, query: String) -> [AppEntry] {
        let listed = apps.filter {
            $0.kind == kind || FuzzyMatch.normalized($0.name) == query
        }
        return byUsage(listed, usage: ranking.snapshot())
    }

    private func categoryRemainder(
        _ kinds: Set<AppEntry.Kind>, excluding ranked: [AppEntry]
    ) -> [AppEntry] {
        guard !kinds.isEmpty else { return [] }
        let matched = Set(ranked.map(\.id))
        let listed = apps.filter { kinds.contains($0.kind) && !matched.contains($0.id) }
        return byUsage(listed, usage: ranking.snapshot())
    }

    /// The launcher's rows: ranked matches, or favorites, suggestions and each kind by usage.
    func orderedResults(
        query: String, visibility: VisibilityStore, favorites: FavoritesStore, hotKeys: HotKeyManager
    ) -> Results {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsSuggestions = settings?.launcherShowsSuggestions ?? true
        let usage = ranking.snapshot()
        let key = ResultsKey(
            match: matchKey(q, limit: 200), visibilityRevision: visibility.revision,
            favoritesRevision: favorites.revision, hotKeysRevision: hotKeys.revision,
            showsSuggestions: showsSuggestions, minute: Int(usage.now.timeIntervalSince1970 / 60))
        return resultsMemo.value(for: key) {
            // Filtering stays downstream of `matches` so that memo is never keyed on hidden state.
            let matched = searchResults(q)
            let visible = matched.entries.filter(visibility.isVisible)
            guard q.isEmpty else {
                let matchCount = matched.entries.prefix(matched.matchCount).count(where: visibility.isVisible)
                return Results(entries: visible, matchCount: matchCount)
            }
            let split = favorites.ordered(visible)
            let suggested =
                showsSuggestions ? suggestions(from: split.rest, usage: usage, hotKeys: hotKeys) : []
            let shown = Set(suggested.map(\.id))
            let rest = byUsage(split.rest.filter { !shown.contains($0.id) }, usage: usage)
            return Results(
                entries: split.favorites + suggested + rest,
                favoriteCount: split.favorites.count, suggestionCount: suggested.count)
        }
    }

    private var sensitivity: SearchSensitivity { settings?.rootSearchSensitivity ?? .default }

    private func matchKey(_ query: String, limit: Int) -> MatchKey {
        MatchKey(
            query: query, limit: limit, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            aliasRevision: aliases.revision, sensitivity: sensitivity)
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        Signposts.interval("AppIndex.rank") {
            let usage = ranking.snapshot()
            return LauncherOrder.ranked(
                apps, query: LauncherOrder.Query(q), sensitivity: sensitivity, limit: limit,
                profile: \.search, signals: { self.signals(for: $0, usage: usage) })
        }
    }

    private func byUsage(_ entries: [AppEntry], usage: LauncherRankingStore.Snapshot) -> [AppEntry] {
        var ordered: [AppEntry] = []
        ordered.reserveCapacity(entries.count)
        var start = entries.startIndex
        while start < entries.endIndex {
            let kind = entries[start].kind
            let end = entries[start...].firstIndex { $0.kind != kind } ?? entries.endIndex
            ordered += LauncherOrder.byUsage(
                Array(entries[start..<end]), signals: { self.signals(for: $0, usage: usage) })
            start = end
        }
        return ordered
    }

    /// Tinycast opening Tinycast goes nowhere.
    private func suggestions(
        from entries: [AppEntry], usage: LauncherRankingStore.Snapshot, hotKeys: HotKeyManager
    ) -> [AppEntry] {
        let eligible = entries.filter {
            !($0.bundleID?.hasPrefix(Self.ownBundlePrefix) ?? false)
        }
        return LauncherSuggestions.select(from: eligible, now: usage.now) { entry in
            return LauncherSuggestions.Traits(
                signals: signals(for: entry, usage: usage), installedAt: entry.installedAt,
                hasHotKey: entry.hotKeyAction.flatMap(hotKeys.binding(for:)) != nil,
                priority: CommandCatalog.command(for: entry)?.suggestionPriority)
        }
    }

    private static let ownBundlePrefix = "com.tinycast."

    private func signals(
        for entry: AppEntry, usage: LauncherRankingStore.Snapshot
    ) -> LauncherOrder.Signals {
        LauncherOrder.Signals(
            alias: aliases.alias(for: entry.preferenceKey).map { SearchText($0, transliterated: false) },
            usage: usage.usage(for: entry.preferenceKey),
            priority: entry.kind.descriptor.rankPriority, title: entry.name)
    }
}
