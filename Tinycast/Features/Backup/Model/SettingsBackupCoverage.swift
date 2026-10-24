import Foundation

/// What `SettingsBackup.SettingsData` carries, written out so a new setting has to be considered.
enum SettingsBackupCoverage {
    /// Each `SettingsData` field paired with the `AppSettings` key it mirrors.
    static let mirrored: [String: AppSettingsKey] = [
        "clipboardEnabled": .clipboardEnabled,
        "clipboardRetentionDays": .clipboardRetention,
        "clipboardDefaultAction": .clipboardDefaultAction,
        "clipboardDisabledApps": .clipboardDisabledApps,
        "hyperKey": .hyperKey,
        "hyperKeyIncludesShift": .hyperKeyIncludesShift,
        "hyperKeyQuickPress": .hyperKeyQuickPress,
        "mehKey": .mehKey,
        "showInMenuBar": .showInMenuBar,
        "popToRootSeconds": .popToRootTimeout,
        "escapeKeyBehavior": .escapeKeyBehavior,
        "calcNumberStyle": .calcNumberStyle,
        "searchScopes": .searchScopes,
        "launcherShowsSuggestions": .launcherShowsSuggestions,
        "rootSearchSensitivity": .rootSearchSensitivity,
        "windowManagementEnabled": .windowManagementEnabled,
        "windowManagementShowInLauncher": .windowManagementShowInLauncher,
        "windowHalfStart": .windowHalfStart,
        "windowQuarterStart": .windowQuarterStart,
        "windowCenterWidth": .windowCenterWidth,
        "commandFolder": .commandFolder,
        "calendarSpan": .calendarSpan,
        "menuBarEvents": .menuBarEvents,
        "calendarMenuBarDisplay": .calendarMenuBarDisplay,
        "menuBarLinkedEventsOnly": .menuBarLinkedEventsOnly,
        "calendarMenuBarHidesWhenEmpty": .calendarMenuBarHidesWhenEmpty,
        "hideCurrentEvent": .hideCurrentEvent
    ]

    /// The `SettingsData` fields no `AppSettings` key stands behind, and what they read instead.
    static let externallySourced: [String: String] = [
        "launchAtLogin": "Read from LaunchAtLogin, which owns the login item, not UserDefaults."
    ]

    /// Keys kept out of a backup on purpose, each with the reason it has to stay out.
    static let deliberatelyExcluded: [String: String] = [
        AppSettingsKey.clipboardTextSearchEnabled.rawValue:
            "Background OCR is an opt-in processing choice on this Mac; a backup must not enable it.",
        AppSettingsKey.autoSwitchInputSource.rawValue:
            "Names a keyboard input source installed on this Mac; another Mac may not have it.",
        AppSettingsKey.calendarEnabled.rawValue:
            "Doubles as consent to read your calendar; an import must not grant calendar access.",
        AppSettingsKey.settingsFileEnabled.rawValue:
            "Lets a file on this Mac change its settings; an import must not hand that to another."
    ]
}
