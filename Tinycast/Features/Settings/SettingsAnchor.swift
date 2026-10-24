/// One `Section` inside a pane, named once so the catalog and the pane cannot disagree: the search
/// result carries the anchor, the pane's `.settingsAnchor(_:)` marks the section it scrolls to.
struct SettingsAnchor: Hashable, Sendable {
    let tab: SettingsTab
    /// The `Section`'s own header text, which is also what a result's breadcrumb reads.
    let title: String
}

// Named `<pane><Section>` throughout, so the constant for a section is always guessable from it.
extension SettingsAnchor {
    static let generalGlobalShortcuts = Self(tab: .general, title: "Global Shortcuts")
    static let generalSearch = Self(tab: .general, title: "Search")
    static let generalHyperKey = Self(tab: .general, title: "Hyper Key")
    static let generalCalculator = Self(tab: .general, title: "Calculator")
    static let generalGeneral = Self(tab: .general, title: "General")

    static let applicationsSearchScopes = Self(tab: .applications, title: "Search Scopes")
    static let applicationsApplications = Self(tab: .applications, title: "Applications")

    static let systemActionsSystemActions = Self(tab: .systemActions, title: "System Actions")

    static let commandsCommands = Self(tab: .commands, title: "Commands")
    static let commandsCommandFolder = Self(tab: .commands, title: "Command Folder")
    static let commandsFolderCommands = Self(tab: .commands, title: "Folder Commands")

    static let windowManagementWindowManagement = Self(
        tab: .windowManagement, title: "Window Management")
    static let windowManagementSizing = Self(tab: .windowManagement, title: "Sizing")
    static let windowManagementMoving = Self(tab: .windowManagement, title: "Moving")
    static let windowManagementOptions = Self(tab: .windowManagement, title: "Options")

    static let clipboardClipboard = Self(tab: .clipboard, title: "Clipboard")
    static let clipboardCommands = Self(tab: .clipboard, title: "Commands")
    static let clipboardHistory = Self(tab: .clipboard, title: "History")
    static let clipboardDisabledApplications = Self(
        tab: .clipboard, title: "Disabled Applications")

    static let calendarCalendar = Self(tab: .calendar, title: "Calendar")
    static let calendarMenuBar = Self(tab: .calendar, title: "Menu Bar")
    static let calendarCalendars = Self(tab: .calendar, title: "Calendars")

    static let permissionsAccessibility = Self(tab: .permissions, title: "Accessibility")
    static let permissionsCalendars = Self(tab: .permissions, title: "Calendars")

    static let backupExport = Self(tab: .backup, title: "Export")
    static let backupImport = Self(tab: .backup, title: "Import")
    static let backupSettingsFile = Self(tab: .backup, title: "Settings File")
}

/// Where a search result lands: a whole section, or one row inside it.
enum SettingsTarget: Hashable, Sendable {
    case section(SettingsAnchor)
    /// The row's visible title, which is also the catalog entry's — they are the same string.
    case row(SettingsAnchor, String)

    var anchor: SettingsAnchor {
        switch self {
        case .section(let anchor), .row(let anchor, _): return anchor
        }
    }

    var tab: SettingsTab { anchor.tab }
}

/// One jump asked for by a search result. The token is what makes picking the same result twice
/// scroll and pulse again, rather than comparing equal and doing nothing.
struct SettingsScrollRequest: Equatable, Sendable {
    let target: SettingsTarget
    let token: Int
}
