import Foundation

/// Where each settings.json key lives; exhaustive, so a new key fails to build until it is bound.
@MainActor
enum SettingsFileSchema {
    static func bindings(
        settings: AppSettings, shortcuts: HotKeySettingsFile, launcher: LauncherSettingsFile,
        windowManagement: WindowManagementSettingsFile
    ) -> [SettingsFileBinding] {
        SettingsFileKey.allCases.map { key in
            binding(
                for: key, settings: settings, shortcuts: shortcuts, launcher: launcher,
                windowManagement: windowManagement)
        }
    }

    private static func binding(
        for key: SettingsFileKey, settings: AppSettings, shortcuts: HotKeySettingsFile,
        launcher: LauncherSettingsFile, windowManagement: WindowManagementSettingsFile
    ) -> SettingsFileBinding {
        func bind<Root: AnyObject, Value: SettingsFileValue>(
            _ root: Root, _ path: ReferenceWritableKeyPath<Root, Value>,
            accept: @escaping (Value) -> Value? = { $0 }
        ) -> SettingsFileBinding {
            SettingsFileBinding(key, root, path, accept: accept)
        }

        switch key {
        case .launcherShortcut:
            return shortcuts.binding(for: key, action: .togglePalette, name: "App Launcher")
        case .showInMenuBar: return bind(settings, \.showInMenuBar)
        case .popToRootTimeout: return bind(settings, \.popToRootTimeout)
        case .escapeKeyBehavior: return bind(settings, \.escapeKeyBehavior)
        case .autoSwitchInputSource: return bind(settings, \.autoSwitchInputSourceID)
        case .hyperKey: return bind(settings, \.hyperKey)
        case .hyperKeyIncludesShift: return bind(settings, \.hyperKeyIncludesShift)
        case .hyperKeyQuickPress: return bind(settings, \.hyperKeyQuickPress)
        case .mehKey: return bind(settings, \.mehKey)
        case .calcNumberStyle: return bind(settings, \.calcNumberStyle)
        case .launcherShowsSuggestions: return bind(settings, \.launcherShowsSuggestions)
        case .rootSearchSensitivity: return bind(settings, \.rootSearchSensitivity)
        case .applicationsEnabled: return launcher.kindBinding(for: key, kind: .application)
        case .searchScopes: return bind(settings, \.searchScopes) { SearchScopes.normalize($0) }
        case .applications: return launcher.appsBinding(for: key)
        case .systemActionsEnabled: return launcher.kindBinding(for: key, kind: .systemAction)
        case .systemActions: return launcher.systemActionsBinding(for: key)
        case .builtInCommandsEnabled: return launcher.kindBinding(for: key, kind: .command)
        case .builtInCommands: return launcher.commandsBinding(for: key, owner: nil)
        case .commandFolder: return bind(settings, \.commandFolder)
        case .windowManagementEnabled: return bind(settings, \.windowManagementEnabled)
        case .windowManagementShowInLauncher:
            return bind(settings, \.windowManagementShowInLauncher)
        case .windowHalfStart: return bind(settings, \.windowHalfStart)
        case .windowQuarterStart: return bind(settings, \.windowQuarterStart)
        case .windowCenterWidth:
            return bind(settings, \.windowCenterWidth) {
                WindowPlacementEngine.centerWidthRange.contains($0) ? $0 : nil
            }
        case .windowShortcuts: return windowManagement.commandShortcutsBinding(for: key)
        case .windowAliases: return windowManagement.commandAliasesBinding(for: key)
        case .clipboardEnabled: return bind(settings, \.clipboardEnabled)
        case .clipboardRetention: return bind(settings, \.clipboardRetention)
        case .clipboardDefaultAction: return bind(settings, \.clipboardDefaultAction)
        case .clipboardDisabledApps: return bind(settings, \.clipboardDisabledApps)
        case .clipboardCommands: return launcher.commandsBinding(for: key, owner: .clipboard)
        case .calendarSpan: return bind(settings, \.calendarSpan)
        case .calendarMenuBarDisplay: return bind(settings, \.calendarMenuBarDisplay)
        case .menuBarEvents: return bind(settings, \.menuBarEvents)
        case .menuBarLinkedEventsOnly: return bind(settings, \.menuBarLinkedEventsOnly)
        case .calendarMenuBarHidesWhenEmpty: return bind(settings, \.calendarMenuBarHidesWhenEmpty)
        case .hideCurrentEvent: return bind(settings, \.hideCurrentEvent)
        }
    }
}

extension PopToRootTimeout: SettingsFileRawValue {}
extension EscapeKeyBehavior: SettingsFileRawValue {}
extension HyperKeyPhysicalKey: SettingsFileRawValue {}
extension HyperKeyQuickPress: SettingsFileRawValue {}
extension CalcNumberStyle: SettingsFileRawValue {}
extension SearchSensitivity: SettingsFileRawValue {}
extension WindowCommand.HalfSide: SettingsFileRawValue {}
extension WindowCommand.QuarterCorner: SettingsFileRawValue {}
extension ClipboardDefaultAction: SettingsFileRawValue {}

extension ClipboardRetention: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .year: 365
        case .forever: "forever"
        }
    }
}

extension MeetingSpan: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .today: "today"
        case .todayAndTomorrow: "todayAndTomorrow"
        case .nextSevenDays: "nextSevenDays"
        }
    }
}

extension CalendarMenuBarDisplay: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .disabled: "disabled"
        case .meetingIcon: "meetingIcon"
        case .meetingTitle: "meetingTitle"
        }
    }
}

extension MenuBarEvents: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .today: "today"
        case .two: 2
        case .five: 5
        case .ten: 10
        case .thirty: 30
        }
    }
}

extension HideCurrentEvent: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .dontHide: "never"
        case .automatically: 0
        case .afterFive: 5
        case .afterTen: 10
        case .afterThirty: 30
        }
    }
}
