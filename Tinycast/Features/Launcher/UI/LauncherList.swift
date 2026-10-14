import SwiftUI

struct LauncherList: View {

    @Environment(\.metrics) private var metrics
    let results: [AppEntry]
    let selectedRowID: String?
    let suggestionCount: Int
    let matchCount: Int
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    /// The card at flat index 0, when one leads. At most one ever does.
    var card: LeadCard?
    var cardSelected = false
    var onActivateCard: () -> Void = {}
    var onCardActions: () -> Void = {}
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    let onDropped: () -> Void
    @Environment(RunningAppsMonitor.self) private var runningApps

    /// The colour card answers only a query the calculator could not, so the two never compete.
    enum LeadCard: Equatable {
        case calc(CalcResult)
        case color(ColorValue)

        var sectionTitle: String {
            switch self {
            case .calc: return "Calculator"
            case .color: return "Color"
            }
        }

        var rowID: String {
            switch self {
            case .calc: return "calc-card"
            case .color: return "color-card"
            }
        }
    }

    private enum Row: Identifiable {
        case header(String)
        case card(LeadCard)
        case app(AppEntry)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .card(let card): return card.rowID
            case .app(let app): return app.id
            }
        }
    }

    /// Whether the selection sits on flat index 0: the card, else the first result.
    private var firstRowSelected: Bool {
        card != nil ? cardSelected : selectedRowID != nil && selectedRowID == results.first?.id
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let card { rows = [.header(card.sectionTitle), .card(card)] }
        let suggestions = results.prefix(suggestionCount)
        let matches = results.dropFirst(suggestionCount).prefix(matchCount)
        let rest = results.dropFirst(suggestionCount + matchCount)
        var grouped: [AppEntry.Kind: [AppEntry]] = [:]
        for app in rest { grouped[app.kind, default: []].append(app) }
        if !suggestions.isEmpty {
            rows.append(.header("Suggestions"))
            rows.append(contentsOf: suggestions.map(Row.app))
        }
        if !matches.isEmpty {
            rows.append(.header("Results"))
            rows.append(contentsOf: matches.map(Row.app))
        }
        // Publication order, so rows match the flat index.
        let kinds: [AppEntry.Kind] = [
            .application, .appleShortcut,
            .systemAction, .windowCommand,
            .command
        ]
        for kind in kinds {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            rows.append(.header(kind.descriptor.sectionTitle))
            rows.append(contentsOf: group.map(Row.app))
        }
        // A missing kind would make every later row activate its neighbour: assert instead.
        assert(
            grouped.keys.allSatisfy(kinds.contains),
            "kind missing from the launcher's section order: "
                + grouped.keys.filter { !kinds.contains($0) }.map(\.rawValue).joined(separator: ", "))
        return rows
    }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && card == nil {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                                case .card(let card):
                                    LeadCardView(card: card, selected: cardSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateCard)
                                        .onRightClick(perform: onCardActions)
                                        .padding(.bottom, metrics.spacing.xs)
                                        .selectionFrame(cardSelected)
                                case .app(let app):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedRowID,
                                        running: runningApps.isRunning(app)
                                    )
                                    .contentShape(Rectangle())
                                    .onRowTap(drag: drag(for: app)) { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                    .selectionFrame(app.id == selectedRowID)
                                }
                            }
                        }
                        .padding(.horizontal, metrics.spacing.md)
                        .padding(.top, metrics.spacing.xs)
                        .padding(.bottom, metrics.spacing.md)
                        .hideNativeScrollers()
                        .scrollOriginAnchor()
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    // Snap to the origin on the first row so its header shows too.
                    .scrollFollowsSelection(
                        scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
                }
            }
        }
    }

    /// Cache-only icon: the row holds its own smaller bitmap, and a decode would stall the drag.
    private func drag(for app: AppEntry) -> RowDrag? {
        guard app.canDragOut else { return nil }
        return RowDrag(
            item: { .file(app.url, image: IconCache.cached(app.iconSource, fileURL: app.url)) },
            dropped: onDropped)
    }
}

/// Draws whichever card leads; each feature still owns how its own card looks.
private struct LeadCardView: View {
    let card: LauncherList.LeadCard
    let selected: Bool

    var body: some View {
        switch card {
        case .calc(let result):
            CalculatorCard(result: result, selected: selected)
        case .color(let color):
            ColorCard(color: color, selected: selected)
        }
    }
}

private struct AppRow: View {

    @Environment(\.metrics) private var metrics
    let app: AppEntry
    let selected: Bool
    let running: Bool
    /// Observed so a hotkey set/cleared in Settings re-renders the row's keycaps immediately.
    @Environment(HotKeyManager.self) private var hotKeys
    /// Observed for the same reason: an alias edit re-renders the row's badge at once.
    @Environment(AliasStore.self) private var aliases
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// Keycaps for this entry's hotkey, or `nil` if none is bound.
    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction else { return nil }
        return hotKeys.binding(for: action)?.keycaps
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            AppIconView(app: app, pointSize: metrics.size.resultRowIcon)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)
                            .offset(y: 3)
                    }
                }
            Text(app.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            if let subtitle = app.subtitle {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let alias = aliases.alias(for: app.preferenceKey) {
                Text(alias)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, metrics.spacing.sm)
                    .padding(.vertical, metrics.spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
            if let caps = shortcutCaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            Text(app.kindLabel)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
