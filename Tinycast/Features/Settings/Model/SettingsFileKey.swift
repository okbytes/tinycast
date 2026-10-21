import Foundation

/// Every key settings.json holds, in the order the file lists them; the raw value is its path.
enum SettingsFileKey: String, CaseIterable, Sendable {
    // Spelled out, so renaming a case can never rename a key in someone's file.
    case launcherShortcut = "general.launcherShortcut"
    case showInMenuBar = "general.showInMenuBar"
    case popToRootTimeout = "general.popToRootSeconds"
    case escapeKeyBehavior = "general.escapeKeyBehavior"
    case autoSwitchInputSource = "general.autoSwitchInputSource"
    case hyperKey = "hyperKey.key"
    case hyperKeyIncludesShift = "hyperKey.includesShift"
    case hyperKeyQuickPress = "hyperKey.quickPress"
    case mehKey = "hyperKey.mehKey"
    case calcNumberStyle = "calculator.numberStyle"
    case launcherShowsSuggestions = "search.showsSuggestions"
    case rootSearchSensitivity = "search.sensitivity"
    case applicationsEnabled = "applications.enabled"
    case searchScopes = "applications.searchScopes"
    case applications = "applications.apps"
    case systemActionsEnabled = "systemActions.enabled"
    case systemActions = "systemActions.actions"
    case builtInCommandsEnabled = "commands.builtInEnabled"
    case builtInCommands = "commands.builtIn"
    case commandFolder = "commands.folder"
    case appleShortcutsEnabled = "appleShortcuts.enabled"
    case windowManagementEnabled = "windowManagement.enabled"
    case windowManagementShowInLauncher = "windowManagement.showInLauncher"
    case windowGap = "windowManagement.gap"
    case windowCycle = "windowManagement.cycle"
    case windowShortcuts = "windowManagement.shortcuts"
    case windowAliases = "windowManagement.aliases"
    case clipboardEnabled = "clipboard.enabled"
    case clipboardRetention = "clipboard.retentionDays"
    case clipboardDefaultAction = "clipboard.defaultAction"
    case clipboardDisabledApps = "clipboard.disabledApps"
    case clipboardCommands = "clipboard.commands"
    case emojiSkinTone = "emoji.skinTone"
    case emojiGridColumns = "emoji.gridColumns"
    case emojiCommands = "emoji.commands"
    case calendarSpan = "calendar.span"
    case calendarMenuBarDisplay = "calendar.menuBar"
    case menuBarEvents = "calendar.menuBarUpcomingEvents"
    case menuBarLinkedEventsOnly = "calendar.menuBarLinkedEventsOnly"
    case calendarMenuBarHidesWhenEmpty = "calendar.menuBarHidesWhenEmpty"
    case hideCurrentEvent = "calendar.hideCurrentEventAfterMinutes"

    /// The top-level object the key sits in.
    var section: String { String(rawValue.prefix { $0 != "." }) }

    /// The key's name inside its section.
    var name: String { String(rawValue.drop { $0 != "." }.dropFirst()) }

    /// Every section, in file order.
    static let sections: [String] = allCases.reduce(into: []) { sections, key in
        if sections.last != key.section { sections.append(key.section) }
    }
}
