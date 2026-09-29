import Foundation

/// A chord aimed at the selected row. The palette recognises it; the screen decides what it does.
enum PaletteShortcut: Equatable {
    /// ⌘⌫ or ⌘⌦.
    case commandDelete
    /// ⌃X.
    case delete
    /// ⌃⇧X.
    case deleteAll
    /// ⇧⌘T.
    case copyText
    /// ⇧⌘↵, matched by the Return handler rather than `resolve`.
    case copyCalculation
    /// ⇧⌘F.
    case toggleFavorite
    /// ⇧⌘H.
    case hideFromSearch
    /// ⌃⇧Q.
    case quit
    /// ⌘R.
    case restart
    /// ⌘N, a new one of whatever the screen holds.
    case newItem
    /// ⌥⌘,, the screen's own settings; ⌘, alone stays the app's.
    case settings
    /// ⌘., which AppKit binds to `cancelOperation:`, so it arrives as a token instead of a key.
    case pin
    /// ⌘1…⌘0, matched by key code in the panel and handed over as a slot.
    case favoriteSlot(Int)

    /// `matches` compares the pressed key through the active layout, so the letters stay positional.
    static func resolve(
        command: Bool, shift: Bool, option: Bool, control: Bool, isDeleteKey: Bool,
        matches: (Character) -> Bool
    ) -> Self? {
        if isDeleteKey { return command ? .commandDelete : nil }
        if command, shift, matches("t") { return .copyText }
        if control, matches("x") { return shift ? .deleteAll : .delete }
        if command, shift, matches("f") { return .toggleFavorite }
        if command, shift, matches("h") { return .hideFromSearch }
        if control, shift, matches("q") { return .quit }
        if command, matches("r") { return .restart }
        if command, !shift, matches("n") { return .newItem }
        if command, option, matches(",") { return .settings }
        return nil
    }

    /// The compact bar shows no selection, so a chord aimed at a highlighted row waits for the list.
    var requiresExpanded: Bool {
        switch self {
        case .copyText, .toggleFavorite, .hideFromSearch, .quit, .restart:
            true
        case .commandDelete, .delete, .deleteAll, .pin, .favoriteSlot, .newItem,
            .settings, .copyCalculation:
            false
        }
    }

    var closesMenu: Bool {
        switch self {
        case .delete, .deleteAll, .copyText, .copyCalculation, .toggleFavorite, .hideFromSearch,
            .newItem, .settings:
            true
        case .commandDelete, .quit, .restart, .pin, .favoriteSlot:
            false
        }
    }
}
