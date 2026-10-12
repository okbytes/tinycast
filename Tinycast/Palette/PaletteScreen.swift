import QuartzCore
import SwiftUI

/// Which arrow pair a move came from: ↑/↓ or ←/→.
enum PaletteAxis {
    case vertical
    case horizontal
}

/// Scale and timing supplied by content while the palette owns the window mechanics.
@MainActor struct MenuPanelMotion {
    let entryScale: CGFloat
    let maximumScale: CGFloat
    let exitScaleDelta: CGFloat
    let expansionDuration: TimeInterval
    let settleDuration: TimeInterval
    let exitDuration: TimeInterval
    let expansionTiming: CAMediaTimingFunction
    let settleTiming: CAMediaTimingFunction
    let exitTiming: CAMediaTimingFunction

    static let palette = MenuPanelMotion(
        entryScale: Theme.MenuMotion.entryScale,
        maximumScale: Theme.MenuMotion.maximumScale,
        exitScaleDelta: Theme.MenuMotion.exitScaleDelta,
        expansionDuration: Theme.MenuMotion.expansionDuration,
        settleDuration: Theme.MenuMotion.settleDuration,
        exitDuration: Theme.MenuMotion.exitDuration,
        expansionTiming: Theme.MenuMotion.expansionTiming,
        settleTiming: Theme.MenuMotion.settleTiming,
        exitTiming: Theme.MenuMotion.exitTiming)
}

typealias MenuPanelClipPath =
    @MainActor (
        _ bounds: CGRect, _ metrics: InterfaceMetrics, _ corner: MenuPanelCorner
    ) -> CGPath

/// A menu supplied by a palette screen, including its rendering and row activation.
@MainActor struct PaletteMenuContent {
    let rowCount: Int
    let preferredSelection: Int?
    let isSelectable: (Int) -> Bool
    let clipPath: MenuPanelClipPath
    let motion: MenuPanelMotion
    /// Built on demand: `moveMenu` resolves the open menu on every arrow key.
    let view: (MenuPanelCorner) -> AnyView
    /// Bounds-checked by the caller against `rowCount`, so a row index is always one this menu has.
    let activate: (Int) -> Void

    init(
        rowCount: Int, preferredSelection: Int? = nil,
        view: @escaping (MenuPanelCorner) -> AnyView,
        activate: @escaping (Int) -> Void,
        isSelectable: @escaping (Int) -> Bool = { _ in true },
        clipPath: @escaping MenuPanelClipPath,
        motion: MenuPanelMotion
    ) {
        self.rowCount = rowCount
        self.preferredSelection = preferredSelection
        self.view = view
        self.activate = activate
        self.isSelectable = isSelectable
        self.clipPath = clipPath
        self.motion = motion
    }

    init(
        popover: PopoverMenuContent, selection: Binding<Int>, width: CGFloat? = nil,
        visibleRows: CGFloat? = nil,
        search: PopoverMenu.Search, onActivate: @escaping (Int) -> Void,
        preferredSelection: Int? = nil
    ) {
        self.init(
            rowCount: popover.items.count, preferredSelection: preferredSelection,
            view: { corner in
                AnyView(
                    PopoverMenu(
                        header: popover.header, items: popover.items, selection: selection,
                        width: width, visibleRows: visibleRows, onActivate: onActivate,
                        attachment: corner.popoverAttachment, search: search))
            },
            activate: { popover.items[$0].action() },
            isSelectable: { popover.items[$0].isSelectable },
            clipPath: { bounds, metrics, corner in
                PopoverMenu.SurfaceShape(
                    attachment: corner.popoverAttachment, radius: metrics.radius.menuPanel,
                    attachedRadius: metrics.size.menuButton / 2
                ).path(in: bounds).cgPath
            },
            motion: .palette)
    }
}

private extension MenuPanelCorner {
    var popoverAttachment: PopoverMenu.Attachment {
        switch self {
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        case .belowHeaderTrailing: .none
        }
    }
}

/// One palette mode. `rows` is its single source of visible order, so selection indexes it.
@MainActor protocol PaletteScreen {
    associatedtype Row: Identifiable

    var rows: [Row] { get }
    var primaryActionTitle: String { get }
    /// Where an open, a new query or a new filter puts the highlight; past row 0 it is centred.
    var landingSelection: Int { get }

    /// False when the selection can't be acted on, which hides the footer pill and swallows ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool
    /// The ⌘K rows as the palette's own menu; nil when there are none.
    func actions(at selection: Int) -> PopoverMenuContent?
    /// Defaults to wrapping `actions(at:)`, so a screen implements one or the other.
    func menuContent(
        at selection: Int, searchQuery: ActionMenuSearchQuery, menuSelection: Binding<Int>,
        onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent?
    func activate(at selection: Int)
    /// ⌘↵. False when the selection has no secondary action, leaving the key unhandled.
    func secondary(at selection: Int) -> Bool
    /// ⌃⌘↵. False when the selection has no third action, leaving the chord to `secondary`.
    func tertiary(at selection: Int) -> Bool
    /// ⌥↵. False on every screen with nothing to paste, which is most of them.
    func pasteKeepingWindowOpen(at selection: Int) -> Bool
    /// False when the screen has no answer to the chord, leaving the key unhandled.
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool
    /// The selection an arrow key lands on, or nil to leave the key to the palette's own default.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int?
    @ViewBuilder func body(selection: Int, scroll: ScrollIntent) -> AnyView
}

extension PaletteScreen {
    func hasPrimaryAction(at selection: Int) -> Bool { true }
    var landingSelection: Int { 0 }
    func actions(at selection: Int) -> PopoverMenuContent? { nil }
    func menuContent(
        at selection: Int, searchQuery: ActionMenuSearchQuery, menuSelection: Binding<Int>,
        onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent? {
        guard let content = actions(at: selection) else { return nil }
        let filtered = content.matching(searchQuery)
        return PaletteMenuContent(
            popover: filtered.content, selection: menuSelection,
            search: PopoverMenu.Search(
                placeholder: "Search for actions…", placement: .bottom),
            onActivate: onActivate, preferredSelection: filtered.bestMatch)
    }
    func tertiary(at selection: Int) -> Bool { false }
    func pasteKeepingWindowOpen(at selection: Int) -> Bool { false }
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool { false }
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? { nil }
}

extension PopoverMenuContent {
    /// Preserve section boundaries even when the row that originally carried one is filtered out.
    func matching(
        _ query: ActionMenuSearchQuery
    ) -> (
        content: PopoverMenuContent, bestMatch: Int?
    ) {
        guard !query.isEmpty else { return (self, nil) }
        var pendingSection = false
        var pendingTitle: String?
        var matches: [PopoverMenuItem] = []
        var bestMatch: (index: Int, score: Int)?

        for original in items {
            if original.startsSection {
                pendingSection = true
                pendingTitle = nil
            }
            if let sectionTitle = original.sectionTitle { pendingTitle = sectionTitle }
            guard let score = query.score(original.title) else { continue }

            var item = original
            item.startsSection = pendingSection && !matches.isEmpty
            item.sectionTitle = pendingTitle
            pendingSection = false
            pendingTitle = nil
            matches.append(item)
            if item.isSelectable, score > (bestMatch?.score ?? .min) {
                bestMatch = (matches.count - 1, score)
            }
        }
        return (PopoverMenuContent(header: header, items: matches), bestMatch?.index)
    }
}
