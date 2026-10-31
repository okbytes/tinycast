import Foundation

/// Where to look and which match styles are legal there, as a table rather than per-root code.
struct UninstallSearchRoot: Hashable, Sendable {
    enum Base: Hashable, Sendable {
        case userLibrary
        case systemLibrary
    }

    enum MatchStyle: String, Hashable, Sendable, CaseIterable {
        case bundleID
        case groupContainer
        case displayName
        /// A crash report: the app name, then `_` or `-`.
        case report
    }

    let base: Base
    /// Relative to `base`, never empty.
    let relativePath: String
    let styles: Set<MatchStyle>
    /// 1, or 2 where the product sits inside a company folder, as `Google/Chrome` does.
    let depth: Int
    /// A launch-job plist whose program path points inside the app bundle.
    let matchProgramPaths: Bool

    init(
        base: Base, relativePath: String, styles: Set<MatchStyle>, depth: Int = 1,
        matchProgramPaths: Bool = false
    ) {
        self.base = base
        self.relativePath = relativePath
        self.styles = styles
        self.depth = depth
        self.matchProgramPaths = matchProgramPaths
    }

    func path(home: String) -> String {
        switch base {
        case .userLibrary: return home + "/Library/" + relativePath
        case .systemLibrary: return "/Library/" + relativePath
        }
    }

    /// The home directory is absent. See docs/features/uninstall.md.
    static let all: [UninstallSearchRoot] = [
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Application Support",
            styles: [.bundleID, .displayName], depth: 2),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Caches", styles: [.bundleID, .displayName],
            depth: 2),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Logs", styles: [.bundleID, .displayName], depth: 2),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Containers", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Group Containers", styles: [.groupContainer]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Application Scripts",
            styles: [.bundleID, .groupContainer]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Preferences", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Preferences/ByHost", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Saved Application State", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "HTTPStorages", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "WebKit", styles: [.bundleID]),
        UninstallSearchRoot(base: .userLibrary, relativePath: "Cookies", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Autosave Information", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "LaunchAgents",
            styles: [.bundleID, .displayName], matchProgramPaths: true),
        // Plug-in wells: a child is a wrapper named after its product, suffix stripped.
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Internet Plug-Ins", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "QuickLook", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Services", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "PreferencePanes", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Screen Savers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Spotlight", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Automator", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Input Methods", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/HAL", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/Components",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/VST",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/VST3",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Audio/Plug-Ins/CLAP",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "ScriptingAdditions",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Components", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Contextual Menu Items",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "ColorPickers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "QuickTime", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Widgets", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "InputManagers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "CoreMediaIO/Plug-Ins/DAL",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Developer", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "SyncedPreferences", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Application Support/CrashReporter",
            styles: [.report]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Logs/DiagnosticReports", styles: [.report]),
        UninstallSearchRoot(
            base: .userLibrary, relativePath: "Logs/CrashReporter", styles: [.report]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Application Support",
            styles: [.bundleID, .displayName], depth: 2),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Caches", styles: [.bundleID, .displayName],
            depth: 2),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Logs", styles: [.bundleID, .displayName],
            depth: 2),
        UninstallSearchRoot(base: .systemLibrary, relativePath: "Preferences", styles: [.bundleID]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "LaunchAgents",
            styles: [.bundleID, .displayName], matchProgramPaths: true),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "LaunchDaemons",
            styles: [.bundleID, .displayName], matchProgramPaths: true),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "PrivilegedHelperTools",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Internet Plug-Ins",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "QuickLook", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Services", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Spotlight", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Automator", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Input Methods", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "InputManagers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "PreferencePanes", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Screen Savers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/HAL",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/Components",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/VST",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/VST3",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Audio/Plug-Ins/CLAP",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "ScriptingAdditions",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Components", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Contextual Menu Items",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "ColorPickers", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "QuickTime", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Widgets", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "CoreMediaIO/Plug-Ins/DAL",
            styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Developer", styles: [.bundleID, .displayName]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Application Support/CrashReporter",
            styles: [.report]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Logs/DiagnosticReports", styles: [.report]),
        UninstallSearchRoot(
            base: .systemLibrary, relativePath: "Logs/CrashReporter", styles: [.report])
    ]

    /// Where a CLI launcher lands, scanned by link target and never by name.
    static let binDirectories: [String] = [
        "/usr/local/bin", "/opt/homebrew/bin", "~/.local/bin", "~/bin"
    ]
}
