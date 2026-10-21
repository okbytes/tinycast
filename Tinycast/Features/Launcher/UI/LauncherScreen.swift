import SwiftUI

/// The root search: suggestions, then one section per kind, led by any card.
struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let visibility: VisibilityStore
    let core: AppCore
    let vm: PaletteState
    /// Sampled by `openActions`, so Restart and Quit can't move while the menu is up.
    let running: Bool
    let openActions: () -> Void
    /// Called when an action reorders the list, so the highlight scrolls back into view.
    let scrollToFollow: () -> Void

    /// The one ordered result list; an empty query leads with suggestions.
    private let results: [AppEntry]
    private let calc: CalcResult?
    /// The colour the query itself spells, if it spells one; nil for every other query.
    private let color: ColorValue?
    /// How many of `results` lead as Suggestions; zero unless the field is empty.
    private let suggestionCount: Int
    private let matchCount: Int
    /// Resolved in `init`: the palette indexes this several times per event, so it can't recompute.
    let rows: [Row]

    init(
        appIndex: AppIndex, visibility: VisibilityStore,
        currencyRates: CurrencyRateStore, core: AppCore, vm: PaletteState, running: Bool,
        openActions: @escaping () -> Void,
        scrollToFollow: @escaping () -> Void
    ) {
        self.appIndex = appIndex
        self.visibility = visibility
        self.core = core
        self.vm = vm
        self.running = running
        self.openActions = openActions
        self.scrollToFollow = scrollToFollow

        let ordered = appIndex.orderedResults(
            query: vm.query, visibility: visibility, hotKeys: core.hotKeys)
        var results = ordered.entries
        var matchCount = ordered.matchCount
        // A typed web address leads: nothing the index holds answers it better.
        if let browser = CommandCatalog.openInBrowser(for: vm.query),
            visibility.isVisible(browser)
        {
            results.insert(browser, at: 0)
            matchCount += 1
        }
        let calc = CalcMemo.evaluate(vm.query, rates: currencyRates.rates, format: core.calcNumberFormat)
        // After the calculator: `#FF5733` is never arithmetic, so the two can't both answer.
        let color = calc == nil ? ColorValue.parse(vm.query) : nil
        let entries = results.map(Row.entry)
        let isEmptyQuery = vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.results = results
        self.calc = calc
        self.color = color
        self.suggestionCount = isEmptyQuery ? ordered.suggestionCount : 0
        self.matchCount = matchCount
        if let calc {
            self.rows = [.calc(calc)] + entries
        } else if let color {
            self.rows = [.color(color)] + entries
        } else {
            self.rows = entries
        }
    }

    /// The card is a row like any other, so the flat selection indexes `rows` with no offset.
    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case color(ColorValue)
        case entry(AppEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .color: return "color-card"
            case .entry(let app): return app.id
            }
        }
    }

    /// The pill carries no selection, so the screen applies the clamp the palette applies.
    private var clampedSelection: Int {
        let count = rows.count
        return count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    var primaryActionTitle: String {
        switch row(at: clampedSelection) {
        case .calc: return "Copy Answer"
        case .color: return "Copy Color"
        case .entry(let app): return app.kind.descriptor.openVerb
        case nil: return "Open Application"
        }
    }

    private func row(at selection: Int) -> Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func entry(at selection: Int) -> AppEntry? {
        guard case .entry(let app) = row(at: selection) else { return nil }
        return app
    }

    private func isCardSelected(_ selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc, .color: return true
        case .entry, nil: return false
        }
    }

    /// Whichever card leads, in the terms the list draws it in.
    private var leadCard: LauncherList.LeadCard? {
        if let calc { return .calc(calc) }
        if let color { return .color(color) }
        return nil
    }

    /// An error card is selectable but has no action: it must drive neither the pill nor ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection) else { return true }
        return result.isActionable
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .color(let color):
            return ColorActionsMenu.content(color: color, core: core)
        case .entry(let app):
            return AppActionsMenu.content(
                app: app, searchQuery: vm.query, core: core, running: running,
                onResetRanking: {
                    core.launcherCoordinator.resetRanking(for: app)
                    // Reset can move the item; keep the highlight on the item whose action ran.
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                },
                onHideFromSearch: { _ = hideFromSearch(at: selection) })
        case nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        // Error cards no-op — copyCalculatorResult only acts on value payloads.
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .color(let color):
            core.clipboardCoordinator.copyColor(color, as: ColorFormat.primary(for: color))
        case .entry(let app):
            core.launcherCoordinator.launch(app, searchQuery: vm.query)
        case nil: break
        }
    }

    /// ⌘↵ — an answer becomes the query, an entry on disk is revealed.
    func secondary(at selection: Int) -> Bool {
        if case .calc(let result) = row(at: selection) {
            return core.calculatorCoordinator.putAnswerInSearchBar(result)
        }
        guard let app = entry(at: selection), app.canRevealInFinder else { return false }
        core.launcherCoordinator.showInFinder(app)
        return true
    }

    /// Offered only for an `.application` entry `RunningAppsMonitor` reports running.
    private func runningApplication(at selection: Int) -> AppEntry? {
        guard let app = entry(at: selection), app.kind == .application,
            core.runningApps.isRunning(app)
        else { return nil }
        return app
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .hideFromSearch: return hideFromSearch(at: selection)
        case .quit, .forceQuit: return quit(at: selection, force: shortcut == .forceQuit)
        case .restart: return restart(at: selection)
        case .copyCalculation: return copyCalculation(at: selection)
        default: return false
        }
    }

    private func copyCalculation(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection), result.isActionable else { return false }
        core.calculatorCoordinator.copyCalculationWithExpression(result)
        return true
    }

    /// ⌃⇧Q or ⌃⌥⇧Q — the screen owns the chord, but only a running app has anything to quit.
    private func quit(at selection: Int, force: Bool) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.quit(app, force: force)
        return true
    }

    /// ⌘R — mirrors the Restart Application row.
    private func restart(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.restart(app)
        return true
    }

    /// ⇧⌘H — the row leaves the list for good, so the highlight takes the place it vacated.
    private func hideFromSearch(at selection: Int) -> Bool {
        guard let app = entry(at: selection), !CommandCatalog.isQueryDriven(app),
            let index = results.firstIndex(of: app)
        else { return false }
        if app.canHideFromSearch {
            visibility.setItemVisible(false, for: app)
        } else {
            return false
        }
        select(row: min(index, max(reorderedResults().entries.count - 1, 0)))
        return true
    }

    /// Re-read the order the change just invalidated; this warms the key the next render reads.
    private func reorderedResults() -> AppIndex.Results {
        appIndex.orderedResults(query: vm.query, visibility: visibility, hotKeys: core.hotKeys)
    }

    private func select(row index: Int) {
        vm.selection = index + (leadCard == nil ? 0 : 1)
        scrollToFollow()
    }

    /// The sample `openActions` takes; only an app row can ever carry the running-only actions.
    func isRunning(at selection: Int) -> Bool {
        guard let app = entry(at: selection) else { return false }
        return core.runningApps.isRunning(app)
    }

    func body(selection: Int) -> AnyView {
        AnyView(content(selection: selection))
    }

    @ViewBuilder
    private func content(selection: Int) -> some View {
        LauncherList(
            results: results,
            selectedRowID: row(at: selection)?.id,
            suggestionCount: suggestionCount,
            matchCount: matchCount,
            card: leadCard,
            cardSelected: isCardSelected(selection),
            onActivateCard: {
                vm.selection = 0
                activate(at: 0)
            },
            onCardActions: {
                guard hasPrimaryAction(at: 0) else { return }
                vm.selection = 0
                openActions()
            },
            onActivate: { core.launcherCoordinator.launch($0, searchQuery: vm.query) },
            onActions: { app in
                if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                openActions()
            },
            onDropped: { core.paletteCoordinator.dragLanded() }
        )
    }
}
