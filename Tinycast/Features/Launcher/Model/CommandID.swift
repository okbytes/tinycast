import Foundation

/// Built-in launcher actions.
enum CommandID: String, CaseIterable, Sendable {
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case pasteSequentially = "command:paste-sequentially"
    case searchEmoji = "command:search-emoji"
    case openCamera = "command:open-camera"
    case openInBrowser = "command:open-in-browser"
    case define = "command:define"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case settings = "command:settings"
    case quit = "command:quit"

    var name: String {
        switch self {
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .pasteSequentially: return "Paste Sequentially"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .openCamera: return "Open Camera"
        case .openInBrowser: return "Open in Browser"
        case .define: return "Define Word"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .settings: return "Tinycast Settings"
        case .quit: return "Quit Tinycast"
        }
    }

    var sfSymbol: String {
        switch self {
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pasteSequentially: return "list.bullet.clipboard"
        case .searchEmoji: return "face.smiling"
        case .openCamera: return "camera"
        case .openInBrowser: return "globe"
        case .define: return "book.closed"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .settings: return "gearshape"
        case .quit: return "power"
        }
    }

    /// Suggested, highest first, until the user's own habits fill the section.
    var suggestionPriority: Int? {
        switch self {
        case .clipboardHistory: 80
        case .searchEmoji: 50
        default: nil
        }
    }

    /// Query-driven: the typed text is their input, so they are built where offered, never listed.
    var isQueryDriven: Bool {
        self == .openInBrowser
    }

    /// A chord carries no query, and none should be able to terminate the app outright.
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
