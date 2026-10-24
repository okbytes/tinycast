import SwiftUI

/// Delay before a closed palette pops to root; an unset key reads as `.immediately`.
enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately ? "Immediately" : "After \(rawValue) seconds"
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

/// How early the calendar item picks the next event up. Zero, which `integer(forKey:)` also
/// returns unset, keeps it for the rest of today.
enum MenuBarEvents: Int, CaseIterable, Identifiable, Sendable {
    case today = 0
    case two = 2
    case five = 5
    case ten = 10
    case thirty = 30

    var id: Int { rawValue }

    var title: String { self == .today ? "Today" : "\(rawValue) minutes before" }
}

/// The calendar's independent menu-bar presence. Zero matches an unset preference.
enum CalendarMenuBarDisplay: Int, CaseIterable, Identifiable, Sendable {
    case disabled = 0
    case meetingIcon = 1
    case meetingTitle = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .meetingIcon: "Meeting Icon"
        case .meetingTitle: "Meeting Title"
        }
    }
}

/// Whether a started event remains in the menu bar long enough to show its time left.
enum HideCurrentEvent: Int, CaseIterable, Identifiable, Sendable {
    case dontHide = -1
    case automatically = 0
    case afterFive = 5
    case afterTen = 10
    case afterThirty = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dontHide: "Keep visible — show time left"
        case .automatically: "Automatically"
        default: "After \(rawValue) minutes"
        }
    }

    var hidesAtStart: Bool { self == .automatically }
    var minutes: Int? { rawValue > 0 ? rawValue : nil }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    private typealias Key = AppSettingsKey

    /// What `AppIndex` scans, in scan order; editing it re-indexes, being observed.
    var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes.rawValue) }
    }

    var launcherShowsSuggestions: Bool {
        didSet {
            defaults.set(launcherShowsSuggestions, forKey: Key.launcherShowsSuggestions.rawValue)
        }
    }

    /// How loose a fuzzy root-search hit may be and still show.
    var rootSearchSensitivity: SearchSensitivity {
        didSet {
            defaults.set(rootSearchSensitivity.rawValue, forKey: Key.rootSearchSensitivity.rawValue)
        }
    }

    /// Ships on, unlike every other feature switch: a launcher is expected to keep history.
    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled.rawValue) }
    }

    var clipboardTextSearchEnabled: Bool {
        didSet { defaults.set(clipboardTextSearchEnabled, forKey: Key.clipboardTextSearchEnabled.rawValue) }
    }

    var clipboardRetention: ClipboardRetention {
        didSet {
            defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention.rawValue)
        }
    }

    /// Bundle IDs never recorded from; ordered, so the Settings list stays stable.
    var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps.rawValue) }
    }

    /// What ↵ does on a clipboard entry; Paste takes the chord the chosen action leaves free.
    var clipboardDefaultAction: ClipboardDefaultAction {
        didSet {
            defaults.set(
                clipboardDefaultAction.rawValue, forKey: Key.clipboardDefaultAction.rawValue)
        }
    }

    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    /// The launcher icon's visibility; dragging the icon out of the menu bar turns it off.
    var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Key.showInMenuBar.rawValue) }
    }

    /// The physical key remapped to the Hyper chord; `KeyRemapManager` reacts via its observer.
    var hyperKey: HyperKeyPhysicalKey {
        didSet { defaults.set(hyperKey.rawValue, forKey: Key.hyperKey.rawValue) }
    }

    /// Whether Hyper is ⌃⌥⇧⌘ (on) or ⌃⌥⌘ (off).
    var hyperKeyIncludesShift: Bool {
        didSet { defaults.set(hyperKeyIncludesShift, forKey: Key.hyperKeyIncludesShift.rawValue) }
    }

    var hyperKeyQuickPress: HyperKeyQuickPress {
        didSet {
            defaults.set(hyperKeyQuickPress.rawValue, forKey: Key.hyperKeyQuickPress.rawValue)
        }
    }

    /// The physical key remapped to the Meh chord, ⌃⌥⇧.
    var mehKey: HyperKeyPhysicalKey {
        didSet { defaults.set(mehKey.rawValue, forKey: Key.mehKey.rawValue) }
    }

    /// How long a closed palette keeps its state before popping back to the root launcher.
    var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout.rawValue) }
    }

    /// Whether Escape walks back through the screens the palette opened, or just closes it.
    var escapeKeyBehavior: EscapeKeyBehavior {
        didSet { defaults.set(escapeKeyBehavior.rawValue, forKey: Key.escapeKeyBehavior.rawValue) }
    }

    /// Which separators the calculator reads and writes; `.system` follows Language & Region.
    var calcNumberStyle: CalcNumberStyle {
        didSet { defaults.set(calcNumberStyle.rawValue, forKey: Key.calcNumberStyle.rawValue) }
    }

    var autoSwitchInputSourceID: String? {
        didSet {
            guard let autoSwitchInputSourceID else {
                defaults.removeObject(forKey: Key.autoSwitchInputSource.rawValue)
                return
            }
            defaults.set(autoSwitchInputSourceID, forKey: Key.autoSwitchInputSource.rawValue)
        }
    }

    /// Doubles as calendar-access consent, so only `CalendarCoordinator` may write it.
    var calendarEnabled: Bool {
        didSet { defaults.set(calendarEnabled, forKey: Key.calendarEnabled.rawValue) }
    }

    /// Narrows the fetch itself rather than what is shown, so every surface reads the same days.
    var calendarSpan: MeetingSpan {
        didSet { defaults.set(calendarSpan.rawValue, forKey: Key.calendarSpan.rawValue) }
    }

    var menuBarEvents: MenuBarEvents {
        didSet { defaults.set(menuBarEvents.rawValue, forKey: Key.menuBarEvents.rawValue) }
    }

    var calendarMenuBarDisplay: CalendarMenuBarDisplay {
        didSet {
            defaults.set(
                calendarMenuBarDisplay.rawValue, forKey: Key.calendarMenuBarDisplay.rawValue)
        }
    }

    var menuBarLinkedEventsOnly: Bool {
        didSet {
            defaults.set(
                menuBarLinkedEventsOnly, forKey: Key.menuBarLinkedEventsOnly.rawValue)
        }
    }

    var calendarMenuBarHidesWhenEmpty: Bool {
        didSet {
            defaults.set(
                calendarMenuBarHidesWhenEmpty, forKey: Key.calendarMenuBarHidesWhenEmpty.rawValue)
        }
    }

    var hideCurrentEvent: HideCurrentEvent {
        didSet { defaults.set(hideCurrentEvent.rawValue, forKey: Key.hideCurrentEvent.rawValue) }
    }

    /// Off means fully off: no launcher entries, and a still-registered shortcut moves nothing.
    var windowManagementEnabled: Bool {
        didSet {
            defaults.set(windowManagementEnabled, forKey: Key.windowManagementEnabled.rawValue)
        }
    }

    var windowManagementShowInLauncher: Bool {
        didSet {
            defaults.set(
                windowManagementShowInLauncher,
                forKey: Key.windowManagementShowInLauncher.rawValue)
        }
    }

    /// Points between tiled windows and the screen edge; `WindowPlacementEngine` caps it.
    var windowGap: Int {
        didSet { defaults.set(windowGap, forKey: Key.windowGap.rawValue) }
    }

    /// What re-triggering a half does: nothing, step its size, or walk it across the displays.
    var windowCycle: WindowCycle {
        didSet { defaults.set(windowCycle.rawValue, forKey: Key.windowCycle.rawValue) }
    }

    /// A `~`-abbreviated path, or empty for `~/.config/tinycast/commands`.
    var commandFolder: String {
        didSet { defaults.set(commandFolder, forKey: Key.commandFolder.rawValue) }
    }

    /// Whether settings.json mirrors these settings; `AppCore` starts and stops the mirror.
    var settingsFileEnabled: Bool {
        didSet { defaults.set(settingsFileEnabled, forKey: Key.settingsFileEnabled.rawValue) }
    }

    init() {
        // The only feature switch that defaults on, so absence has to outrank a stored `false`.
        clipboardEnabled =
            defaults.object(forKey: Key.clipboardEnabled.rawValue) == nil
            || defaults.bool(forKey: Key.clipboardEnabled.rawValue)
        // `integer(forKey:)` returns 0 when unset, which no case matches.
        clipboardTextSearchEnabled = defaults.bool(forKey: Key.clipboardTextSearchEnabled.rawValue)
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention.rawValue))
            ?? .threeMonths
        // Password managers ship excluded, until the user first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps.rawValue)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        clipboardDefaultAction =
            defaults.string(forKey: Key.clipboardDefaultAction.rawValue)
            .flatMap(ClipboardDefaultAction.init) ?? .paste
        launchAtLogin = LaunchAtLogin.isEnabled
        showInMenuBar =
            defaults.object(forKey: Key.showInMenuBar.rawValue) == nil
            || defaults.bool(forKey: Key.showInMenuBar.rawValue)
        hyperKey =
            defaults.string(forKey: Key.hyperKey.rawValue).flatMap(HyperKeyPhysicalKey.init)
            ?? .none
        // Defaults to true, so absence must be distinguished from a stored `false`.
        hyperKeyIncludesShift =
            defaults.object(forKey: Key.hyperKeyIncludesShift.rawValue) == nil
            || defaults.bool(forKey: Key.hyperKeyIncludesShift.rawValue)
        hyperKeyQuickPress =
            defaults.string(forKey: Key.hyperKeyQuickPress.rawValue)
            .flatMap(HyperKeyQuickPress.init)
            ?? .none
        mehKey =
            defaults.string(forKey: Key.mehKey.rawValue).flatMap(HyperKeyPhysicalKey.init) ?? .none
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout.rawValue))
            ?? .immediately
        escapeKeyBehavior =
            defaults.string(forKey: Key.escapeKeyBehavior.rawValue).flatMap(EscapeKeyBehavior.init)
            ?? .navigateBackOrClose
        calcNumberStyle =
            defaults.string(forKey: Key.calcNumberStyle.rawValue).flatMap(CalcNumberStyle.init)
            ?? .system
        // Unset seeds the defaults; a stored empty array is a deliberately cleared list.
        searchScopes =
            defaults.stringArray(forKey: Key.searchScopes.rawValue) ?? SearchScopes.defaults
        launcherShowsSuggestions =
            defaults.object(forKey: Key.launcherShowsSuggestions.rawValue) == nil
            || defaults.bool(forKey: Key.launcherShowsSuggestions.rawValue)
        rootSearchSensitivity =
            defaults.string(forKey: Key.rootSearchSensitivity.rawValue)
            .flatMap(SearchSensitivity.init) ?? .default
        autoSwitchInputSourceID = defaults.string(forKey: Key.autoSwitchInputSource.rawValue)
        // Opt-in: until it is asked for, EventKit is never loaded.
        calendarEnabled = defaults.bool(forKey: Key.calendarEnabled.rawValue)
        // No case is zero, so an unset key falls through to the default.
        calendarSpan =
            MeetingSpan(rawValue: defaults.integer(forKey: Key.calendarSpan.rawValue))
            ?? .todayAndTomorrow
        // Both default to their zero case, so an unset key needs no presence check.
        menuBarEvents =
            MenuBarEvents(rawValue: defaults.integer(forKey: Key.menuBarEvents.rawValue)) ?? .today
        calendarMenuBarDisplay =
            CalendarMenuBarDisplay(
                rawValue: defaults.integer(forKey: Key.calendarMenuBarDisplay.rawValue))
            ?? .disabled
        menuBarLinkedEventsOnly =
            defaults.object(forKey: Key.menuBarLinkedEventsOnly.rawValue) == nil
            || defaults.bool(forKey: Key.menuBarLinkedEventsOnly.rawValue)
        calendarMenuBarHidesWhenEmpty =
            defaults.bool(forKey: Key.calendarMenuBarHidesWhenEmpty.rawValue)
        hideCurrentEvent =
            defaults.object(forKey: Key.hideCurrentEvent.rawValue)
            .flatMap { $0 as? Int }
            .flatMap(HideCurrentEvent.init(rawValue:)) ?? .dontHide
        windowManagementEnabled = defaults.bool(forKey: Key.windowManagementEnabled.rawValue)
        windowManagementShowInLauncher =
            defaults.object(forKey: Key.windowManagementShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowManagementShowInLauncher.rawValue)
        // Unset reads as 0, which is the intended default anyway — no gap.
        windowGap = defaults.integer(forKey: Key.windowGap.rawValue)
        windowCycle =
            defaults.string(forKey: Key.windowCycle.rawValue).flatMap(WindowCycle.init) ?? .off
        commandFolder = defaults.string(forKey: Key.commandFolder.rawValue) ?? ""
        settingsFileEnabled = defaults.bool(forKey: Key.settingsFileEnabled.rawValue)
    }
}
