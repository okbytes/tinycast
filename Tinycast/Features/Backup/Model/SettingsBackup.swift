import Foundation

/// A readable configuration snapshot; every field is optional, so an import merges.
struct SettingsBackup: Codable {

    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?
    var launcherAliases: [String: String]?
    var pinnedEmoji: [String]?

    /// Enums store by raw value, so an unknown one is ignored rather than failing.
    struct SettingsData: Codable {
        // Adding a field here means adding it to SettingsBackupCoverage too, or the harness fails.
        // Carried, unlike the consent flags: recording your own copies grants no permission class.
        var clipboardEnabled: Bool?
        var clipboardRetentionDays: Int?
        var clipboardDefaultAction: String?
        var clipboardDisabledApps: [String]?
        var launchAtLogin: Bool?
        var hyperKey: String?
        var hyperKeyIncludesShift: Bool?
        var hyperKeyQuickPress: String?
        var mehKey: String?
        var showInMenuBar: Bool?
        var popToRootSeconds: Int?
        var escapeKeyBehavior: String?
        var calcNumberStyle: String?
        var searchScopes: [String]?
        var launcherShowsSuggestions: Bool?
        var rootSearchSensitivity: String?
        var windowManagementEnabled: Bool?
        var windowManagementShowInLauncher: Bool?
        var windowHalfStart: String?
        var windowQuarterStart: String?
        var windowCenterWidth: Int?
        // A `~` path, so it lands on the other Mac's home; the folder itself is not carried.
        var commandFolder: String?
        // No `calendarEnabled`, so an import grants no access; the span only narrows what is read.
        var calendarSpan: Int?
        var menuBarEvents: Int?
        var calendarMenuBarDisplay: Int?
        var menuBarLinkedEventsOnly: Bool?
        var calendarMenuBarHidesWhenEmpty: Bool?
        var hideCurrentEvent: Int?
    }

    /// One entry per bindable action. docs/features/hotkeys.md#persistence
    struct HotkeyBackup: Codable {
        /// Named apart from `commands`: the launcher toggle is the one action with no command row.
        var togglePalette: HotKeyBinding?
        var commands: [String: HotKeyBinding]?
        var apps: [String: HotKeyBinding]?
        var systemActions: [String: HotKeyBinding]?
        var windowCommands: [String: HotKeyBinding]?
    }

    /// A tally of what an import touched, for user-facing confirmation.
    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var hiddenItems = 0
        var aliases = 0
        var pinnedEmoji = 0
    }
}

// MARK: - Gather / apply (main-actor: reads and writes the live stores)

@MainActor
extension SettingsBackup {
    static func gather(from core: AppCore) -> SettingsBackup {
        let s = core.settings
        var backup = SettingsBackup()
        backup.settings = SettingsData(
            clipboardEnabled: s.clipboardEnabled,
            clipboardRetentionDays: s.clipboardRetention.rawValue,
            clipboardDefaultAction: s.clipboardDefaultAction.rawValue,
            clipboardDisabledApps: s.clipboardDisabledApps,
            launchAtLogin: s.launchAtLogin,
            hyperKey: s.hyperKey.rawValue,
            hyperKeyIncludesShift: s.hyperKeyIncludesShift,
            hyperKeyQuickPress: s.hyperKeyQuickPress.rawValue,
            mehKey: s.mehKey.rawValue,
            showInMenuBar: s.showInMenuBar,
            popToRootSeconds: s.popToRootTimeout.rawValue,
            escapeKeyBehavior: s.escapeKeyBehavior.rawValue,
            calcNumberStyle: s.calcNumberStyle.rawValue,
            searchScopes: s.searchScopes,
            launcherShowsSuggestions: s.launcherShowsSuggestions,
            rootSearchSensitivity: s.rootSearchSensitivity.rawValue,
            windowManagementEnabled: s.windowManagementEnabled,
            windowManagementShowInLauncher: s.windowManagementShowInLauncher,
            windowHalfStart: s.windowHalfStart.rawValue,
            windowQuarterStart: s.windowQuarterStart.rawValue,
            windowCenterWidth: s.windowCenterWidth,
            commandFolder: s.commandFolder,
            calendarSpan: s.calendarSpan.rawValue,
            menuBarEvents: s.menuBarEvents.rawValue,
            calendarMenuBarDisplay: s.calendarMenuBarDisplay.rawValue,
            menuBarLinkedEventsOnly: s.menuBarLinkedEventsOnly,
            calendarMenuBarHidesWhenEmpty: s.calendarMenuBarHidesWhenEmpty,
            hideCurrentEvent: s.hideCurrentEvent.rawValue)

        let hk = core.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.binding(for: .togglePalette)
        hotkeys.commands = Dictionary(
            uniqueKeysWithValues: CommandID.allCases.compactMap { id in
                id.hotKeyAction.flatMap(hk.binding(for:)).map { (id.rawValue, $0) }
            })
        hotkeys.apps = Dictionary(
            uniqueKeysWithValues: hk.boundBundleIDs.compactMap { id in
                hk.binding(for: .app(bundleID: id)).map { (id, $0) }
            })
        hotkeys.systemActions = Dictionary(
            uniqueKeysWithValues: SystemAction.ID.allCases.compactMap { id in
                hk.binding(for: .systemAction(id: id)).map { (id.rawValue, $0) }
            })
        hotkeys.windowCommands = Dictionary(
            uniqueKeysWithValues: WindowCommand.ID.allCases.compactMap { id in
                hk.binding(for: .windowCommand(id: id)).map { (id.rawValue, $0) }
            })
        backup.hotkeys = hotkeys

        backup.hiddenLauncherItems = Array(core.visibility.hiddenItemKeys)
        backup.hiddenLauncherKinds = Array(core.visibility.disabledKinds)
        backup.launcherAliases = core.aliases.aliases
        backup.pinnedEmoji = core.pinnedEmoji.glyphs
        return backup
    }

    @discardableResult
    func apply(to core: AppCore) -> ApplySummary {
        var summary = ApplySummary()
        if let s = settings { summary.settingsFields = applySettings(s, to: core) }
        if let hotkeys { summary.hotkeys = applyHotkeys(hotkeys, to: core) }
        if hiddenLauncherItems != nil || hiddenLauncherKinds != nil {
            let items = hiddenLauncherItems ?? Array(core.visibility.hiddenItemKeys)
            let kinds = hiddenLauncherKinds ?? Array(core.visibility.disabledKinds)
            core.visibility.replace(hiddenItems: items, disabledKinds: kinds)
            summary.hiddenItems = items.count
        }
        if let launcherAliases {
            core.aliases.replace(launcherAliases)
            // Counted after the store, which drops blanks the file may carry.
            summary.aliases = core.aliases.aliases.count
        }
        if let pinnedEmoji {
            core.pinnedEmoji.replace(pinnedEmoji)
            summary.pinnedEmoji = core.pinnedEmoji.glyphs.count
        }
        return summary
    }

    private func applySettings(_ s: SettingsData, to core: AppCore) -> Int {
        let settings = core.settings
        var count = 0
        if let flag = s.clipboardEnabled {
            settings.clipboardEnabled = flag
            count += 1
        }
        if let days = s.clipboardRetentionDays, let retention = ClipboardRetention(rawValue: days) {
            settings.clipboardRetention = retention
            count += 1
        }
        if let apps = s.clipboardDisabledApps {
            settings.clipboardDisabledApps = apps
            count += 1
        }
        if let raw = s.clipboardDefaultAction, let action = ClipboardDefaultAction(rawValue: raw) {
            settings.clipboardDefaultAction = action
            count += 1
        }
        if let launch = s.launchAtLogin {
            settings.launchAtLogin = launch
            count += 1
        }
        if let raw = s.hyperKey, let key = HyperKeyPhysicalKey(rawValue: raw) {
            settings.hyperKey = key
            count += 1
        }
        if let flag = s.hyperKeyIncludesShift {
            settings.hyperKeyIncludesShift = flag
            count += 1
        }
        if let raw = s.hyperKeyQuickPress, let quick = HyperKeyQuickPress(rawValue: raw) {
            settings.hyperKeyQuickPress = quick
            count += 1
        }
        if let raw = s.mehKey, let key = HyperKeyPhysicalKey(rawValue: raw) {
            settings.mehKey = key
            count += 1
        }
        if let show = s.showInMenuBar {
            settings.showInMenuBar = show
            count += 1
        }
        if let secs = s.popToRootSeconds, let timeout = PopToRootTimeout(rawValue: secs) {
            settings.popToRootTimeout = timeout
            count += 1
        }
        if let raw = s.escapeKeyBehavior, let behavior = EscapeKeyBehavior(rawValue: raw) {
            settings.escapeKeyBehavior = behavior
            count += 1
        }
        if let raw = s.calcNumberStyle, let style = CalcNumberStyle(rawValue: raw) {
            settings.calcNumberStyle = style
            count += 1
        }
        if let scopes = s.searchScopes {
            settings.searchScopes = SearchScopes.normalize(scopes)
            count += 1
        }
        if let flag = s.launcherShowsSuggestions {
            settings.launcherShowsSuggestions = flag
            count += 1
        }
        if let raw = s.rootSearchSensitivity, let sensitivity = SearchSensitivity(rawValue: raw) {
            settings.rootSearchSensitivity = sensitivity
            count += 1
        }
        // Writing through AppSettings is enough; AppCore's sinks re-project the rest.
        if let flag = s.windowManagementEnabled {
            settings.windowManagementEnabled = flag
            count += 1
        }
        if let flag = s.windowManagementShowInLauncher {
            settings.windowManagementShowInLauncher = flag
            count += 1
        }
        if let raw = s.windowHalfStart, let side = WindowCommand.HalfSide(rawValue: raw) {
            settings.windowHalfStart = side
            count += 1
        }
        if let raw = s.windowQuarterStart, let corner = WindowCommand.QuarterCorner(rawValue: raw) {
            settings.windowQuarterStart = corner
            count += 1
        }
        if let width = s.windowCenterWidth, WindowPlacementEngine.centerWidthRange.contains(width) {
            settings.windowCenterWidth = width
            count += 1
        }
        if let path = s.commandFolder {
            settings.commandFolder = path
            count += 1
        }
        if let raw = s.calendarSpan, let span = MeetingSpan(rawValue: raw) {
            settings.calendarSpan = span
            count += 1
        }
        if let raw = s.menuBarEvents, let lead = MenuBarEvents(rawValue: raw) {
            settings.menuBarEvents = lead
            count += 1
        }
        if let raw = s.calendarMenuBarDisplay,
            let display = CalendarMenuBarDisplay(rawValue: raw)
        {
            settings.calendarMenuBarDisplay = display
            count += 1
        }
        if let flag = s.menuBarLinkedEventsOnly {
            settings.menuBarLinkedEventsOnly = flag
            count += 1
        }
        if let flag = s.calendarMenuBarHidesWhenEmpty {
            settings.calendarMenuBarHidesWhenEmpty = flag
            count += 1
        }
        if let raw = s.hideCurrentEvent, let hide = HideCurrentEvent(rawValue: raw) {
            settings.hideCurrentEvent = hide
            count += 1
        }
        return count
    }

    private func applyHotkeys(_ hotkeys: HotkeyBackup, to core: AppCore) -> Int {
        let hk = core.hotKeys
        var count = 0
        // Skip an already-claimed binding: the second registration would silently fail.
        func apply(_ binding: HotKeyBinding, _ action: HotKeyAction) {
            guard hk.conflictOwner(of: binding, excluding: action) == nil else { return }
            hk.setBinding(binding, for: action)
            count += 1
        }
        if let b = hotkeys.togglePalette { apply(b, .togglePalette) }
        for (rawID, b) in hotkeys.commands ?? [:] {
            guard let action = CommandID(rawValue: rawID)?.hotKeyAction else { continue }
            apply(b, action)
        }
        for (id, b) in hotkeys.apps ?? [:] { apply(b, .app(bundleID: id)) }
        for (rawID, b) in hotkeys.systemActions ?? [:] {
            guard let id = SystemAction.ID(rawValue: rawID) else { continue }
            apply(b, .systemAction(id: id))
        }
        for (rawID, b) in hotkeys.windowCommands ?? [:] {
            guard let id = WindowCommand.ID(rawValue: rawID) else { continue }
            apply(b, .windowCommand(id: id))
        }
        return count
    }
}

// MARK: - Serialization

extension SettingsBackup {
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    init(json: Data) throws {
        self = try JSONDecoder().decode(SettingsBackup.self, from: json)
    }
}
