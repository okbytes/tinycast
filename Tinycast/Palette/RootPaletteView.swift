import SwiftUI

struct RootPaletteView: View {
    @Environment(AppCore.self) private var core
    @Environment(PaletteState.self) private var vm
    @Environment(AppIndex.self) private var appIndex
    @Environment(ClipboardStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(VisibilityStore.self) private var visibility
    @Environment(CalculatorHistoryStore.self) private var calcHistory
    /// Observed so the card re-evaluates when a snapshot lands or consent changes.
    @Environment(CurrencyRateStore.self) private var currencyRates
    @Environment(EmojiIndex.self) private var emojiIndex
    @Environment(FrequentEmojiStore.self) private var frequentEmoji
    @Environment(DictionarySession.self) private var dictionary
    @Environment(WindowSwitchSession.self) private var windowSwitch
    @Environment(CalendarStore.self) private var calendarStore
    /// Observed so the join card's countdown redraws on the minute boundary.
    @Environment(MeetingClock.self) private var meetingClock
    @Environment(UninstallSession.self) private var uninstall
    @Environment(QuicklinkStore.self) private var quicklinks
    @Environment(SnippetsStore.self) private var snippets
    @Environment(AppSettings.self) private var settings
    @Environment(\.metrics) private var metrics
    @Environment(\.openURL) private var openURL
    @FocusState private var searchFocused: Bool
    /// Kept apart from the search field's own focus. See docs/features/palette.md.
    @FocusState private var argumentFocused: String?
    /// Which in-window menu is open; at most one, so the state cannot disagree with itself.
    @State private var openMenu: OpenMenu?
    /// Sampled once by `openActions`, so the running-only rows can't appear while the menu is up.
    @State private var selectionIsRunning = false
    /// Highlighted row of whichever menu is open; each open path sets where it starts.
    @State private var menuSelection = 0
    /// The argument field whose choices are up, so `menuContent` can rebuild the same menu.
    @State private var argumentOptionsField: String?
    @State private var menuPanel = MenuPanelController()
    /// The palette's own window, reported by `WindowReader`; the menu hangs off its frame.
    @State private var hostWindow: NSWindow?
    /// The pending scroll request; modes are exclusive, so one piece of state serves all.
    @State private var scroll = ScrollIntent(kind: .top)

    /// Compact vs. full; the source of truth is on `AppCore`, so the two can't disagree.
    private var isCollapsed: Bool { core.paletteCoordinator.paletteIsCollapsed }

    /// The current mode's screen: its rows are the visible order the flat selection indexes.
    private var screen: any PaletteScreen {
        switch vm.mode {
        case .launcher:
            return LauncherScreen(
                appIndex: appIndex, favorites: favorites, visibility: visibility,
                currencyRates: currencyRates, core: core, vm: vm, running: selectionIsRunning,
                meeting: core.calendarCoordinator.cardedMeeting, now: meetingClock.now,
                openActions: openActions, openArgumentOptions: openArgumentOptions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .uninstall:
            return UninstallScreen(
                session: uninstall, core: core, vm: vm, openActions: openActions)
        case .quicklinks:
            return QuicklinkListScreen(
                store: quicklinks, core: core, vm: vm, openActions: openActions,
                openArgumentOptions: openArgumentOptions)
        case .snippets:
            return SnippetsScreen(
                store: snippets, core: core, vm: vm, openActions: openActions)
        case .emoji:
            return EmojiScreen(
                index: emojiIndex, frequent: frequentEmoji, pinned: core.pinnedEmoji, core: core, vm: vm,
                tone: settings.emojiSkinTone, defaultColumns: settings.emojiGridColumns,
                openActions: openActions)
        case .switchWindows:
            return WindowSwitchScreen(session: windowSwitch, core: core)
        case .rooms:
            return RoomsScreen(coordinator: core.roomCoordinator, session: core.roomSession, vm: vm)
        case .roomWindows:
            return RoomPickerScreen(
                coordinator: core.roomCoordinator, session: core.roomSession, vm: vm)
        case .schedule:
            return ScheduleScreen(
                store: calendarStore, clock: meetingClock, core: core, vm: vm,
                openActions: openActions)
        case .meetingDetails:
            return MeetingDetailsScreen(store: calendarStore, core: core)
        case .clipboard:
            return ClipboardScreen(
                store: store, core: core, vm: vm, openActions: openActions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .dictionary:
            return DictionaryScreen(session: dictionary, core: core, vm: vm)
        case .calculatorHistory:
            return CalculatorHistoryScreen(
                history: calcHistory, currencyRates: currencyRates, core: core, vm: vm,
                openActions: openActions)
        }
    }

    /// Selection clamped into the results: one source for highlight, preview and activation.
    private func selection(count: Int) -> Int {
        count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    /// Takes a resolved screen — reaching `rows` costs a list build, so callers resolve it once.
    private func selection(in screen: any PaletteScreen) -> Int {
        selection(count: screen.rows.count)
    }

    private var menuOpen: Bool { openMenu != nil }

    // MARK: - Popover menu content

    /// The clipboard type filter's rows; activating one is the only way the filter changes.
    private var clipboardFilterContent: PopoverMenuContent {
        PopoverMenuContent(
            items: ClipboardFilter.allCases.enumerated().map { index, filter in
                PopoverMenuItem(
                    title: filter.title, systemImage: filter.systemImage,
                    startsSection: index == 1
                ) {
                    vm.clipboardFilter = filter
                }
            })
    }

    /// All Categories stays above the divider; the remaining rows match their section order.
    private var emojiCategoryContent: PopoverMenuContent {
        PopoverMenuContent(
            items: EmojiCategoryFilter.allCases.enumerated().map { index, filter in
                PopoverMenuItem(
                    title: filter.title, systemImage: filter.systemImage,
                    startsSection: index == 1
                ) {
                    vm.emojiCategoryFilter = filter
                }
            })
    }

    private var appMenuContent: PopoverMenuContent {
        let appName = Bundle.main.appDisplayName
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let title = version.map { "\(appName) v\($0)" } ?? appName
        return PopoverMenuContent(
            header: title,
            items: [
                PopoverMenuItem(
                    title: "Changelog",
                    systemImage: "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
                ) {
                    if let url = URL(string: "https://github.com/abue-ammar/tinycast/releases") {
                        openURL(url)
                    }
                },
                PopoverMenuItem(title: "About Tinycast", systemImage: "info.circle") {
                    core.settingsCoordinator.showAbout()
                },
                PopoverMenuItem(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                    core.settingsCoordinator.showSettings()
                },
                PopoverMenuItem(
                    title: "Quit \(appName)", systemImage: "rectangle.portrait.and.arrow.right",
                    startsSection: true, isDestructive: true
                ) {
                    NSApp.terminate(nil)
                }
            ])
    }

    /// The one source every menu path addresses rows through, so none can disagree.
    private var menuContent: PaletteMenuContent? {
        switch openMenu {
        case .actions:
            let screen = screen
            return screen.menuContent(
                at: selection(in: screen), searchQuery: ActionMenuSearchQuery(vm.menuQuery),
                menuSelection: $menuSelection,
                onActivate: activateMenuItem)
        case .app:
            let filtered = appMenuContent.matching(ActionMenuSearchQuery(vm.menuQuery))
            return PaletteMenuContent(
                popover: filtered.content, selection: $menuSelection,
                search: PopoverMenu.Search(
                    placeholder: "Search for actions…", placement: .bottom),
                onActivate: activateMenuItem, preferredSelection: filtered.bestMatch)
        case .clipboardFilter:
            return headerMenu(
                clipboardFilterContent, width: metrics.size.clipboardFilterMenuWidth)
        case .emojiCategory:
            return headerMenu(emojiCategoryContent, width: metrics.size.emojiCategoryMenuWidth)
        case .argumentOptions:
            guard let field = argumentOptionsField,
                let popover = headerAccessory?.optionsMenu(field)
            else { return nil }
            return headerMenu(popover, width: metrics.size.menuWidth)
        case nil: return nil
        }
    }

    var body: some View {
        // Resolve the screen once per render, so the flat index can't drift from the rows.
        let screen = screen
        let count = screen.rows.count
        let sel = selection(count: count)
        let showActionGroup = count > 0 && screen.hasPrimaryAction(at: sel)

        // One header position, so focus survives the swap. See docs/features/palette.md.
        return keyHandlers(
            stateObservers(
                Group {
                    if isCollapsed {
                        Color.clear
                    } else {
                        screen.body(selection: sel, scroll: scroll)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isCollapsed {
                        bottomBar(
                            pillLabel: screen.primaryActionTitle, showActionGroup: showActionGroup,
                            showActions: screen.hasActions(at: sel))
                    }
                }
                // The panel has no title bar, so this thin top margin is the only place left to grab it.
                .overlay(alignment: .top) { topDragStrip }
                // Never conditionally mounted: unmounting strands SwiftUI's hover target and eats clicks.
                .overlay {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        // Not a tap: a drifting press must still dismiss, the way a native menu's does.
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in closeMenus() })
                        .onRightClick { closeMenus() }
                        .allowsHitTesting(menuOpen)
                }
                // The menu lives in its own window; this only reports the one to hang it from.
                .background(
                    WindowReader {
                        hostWindow = $0
                        installHeaderArrowHandler(in: $0)
                    }
                )
                // The window's frame is the size source, so the glass and clip stay matched.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.Colors.panelScrim)
                .background(GlassEffectView())
                .overlay {
                    Theme.Colors.dialogDimming
                        .opacity(core.isDimmingPaletteForDialog ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .animation(
                    .easeOut(
                        duration: core.isDimmingPaletteForDialog
                            ? Theme.Duration.dialogEnter : Theme.Duration.dialogExit),
                    value: core.isDimmingPaletteForDialog
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous))),
            selection: sel)
    }

    /// The emoji grid's observers, split out so `stateObservers` stays within type-checker reach.
    @ViewBuilder
    private func emojiObservers(_ content: some View) -> some View {
        content
            .onChange(of: vm.emojiCategoryFilter) { land() }
            .onChange(of: core.pinnedEmoji.revision) { emojiGridChanged() }
            .onChange(of: (screen as? EmojiScreen)?.frequentlyUsed) { old, new in
                guard let old, let new else { return }
                (screen as? EmojiScreen)?.frequentlyUsedChanged(from: old, to: new)
                emojiGridChanged()
            }
            .onChange(of: vm.emojiGridColumnsOverride) { emojiGridChanged() }
            .onChange(of: settings.emojiGridColumns) { emojiGridChanged() }
            // ⌘0 / ⌘+ / ⌘- arrive as a token, like ⌘. does. See `PaletteState.emojiGridZoomToken`.
            .onChange(of: vm.emojiGridZoomToken) {
                guard let zoom = vm.emojiGridZoom else { return }
                (screen as? EmojiScreen)?.zoom(zoom)
            }
    }

    /// Pins and density move cells under the selection, and can change an open Actions menu's rows.
    private func emojiGridChanged() {
        guard vm.mode == .emoji else { return }
        scroll = ScrollIntent(kind: .follow)
        refreshActionsMenu()
    }

    /// Split from `body` for the same reason `keyHandlers` is: one chain cannot carry them all.
    @ViewBuilder
    private func stateObservers(_ content: some View) -> some View {
        emojiObservers(content)
            // Every show bumps focusToken so the search field refocuses.
            .onChange(of: vm.focusToken) { searchFocused = true }
            // A preserved screen re-summons as it was left, so a menu must end with the palette.
            .modifier(PaletteHideObserver { if menuOpen { closeMenus() } })
            .onChange(of: vm.query) {
                if vm.collapseQueryLineBreaks() { return }
                land()
                if vm.mode == .dictionary { dictionary.lookUp(vm.query) }
                if vm.mode == .switchWindows { windowSwitch.filter(vm.query) }
            }
            // A narrower list means the old index points at a different row, or at none.
            .onChange(of: vm.clipboardFilter) { land() }
            .onChange(of: vm.mode) {
                vm.clipboardFilter = .all
                vm.emojiCategoryFilter = .all
                vm.emojiGridColumnsOverride = nil
                if menuOpen { closeMenus() }
                land()
                searchFocused = true
                // Every way out of the Uninstall screen: back chevron, bare backspace, a fresh summon.
                if vm.mode != .uninstall { uninstall.cancel() }
                if vm.mode == .dictionary {
                    dictionary.lookUp(vm.query)
                } else {
                    dictionary.reset()
                }
                if vm.mode != .switchWindows { windowSwitch.reset() }
                if vm.mode != .meetingDetails { calendarStore.clearDetails() }
                if vm.mode != .rooms, vm.mode != .roomWindows { core.roomCoordinator.screensDidClose() }
            }
            // `prepare` may change nothing else, so this still lands the list as freshly opened.
            .onChange(of: vm.resetToken) {
                if menuOpen { closeMenus() }
                land()
            }
            // ⌘. arrives as a token rather than a key press. See `PaletteState.pinChordToken`.
            .onChange(of: vm.pinChordToken) { performShortcut(.pin) }
            .onChange(of: vm.queryRewriteToken) {
                if menuOpen { closeMenus() }
                searchFocused = true
                // Next turn, past the refocus that selects all, so typing extends the answer.
                Task { @MainActor in (hostWindow as? PalettePanel)?.moveFieldEditorCaretToEnd() }
            }
            // ⌘1…⌘0 arrives as a slot index from AppKit keyCode matching.
            .onChange(of: vm.favoriteSlotToken) {
                if let index = vm.favoriteSlotIndex { performShortcut(.favoriteSlot(index)) }
            }
            // One optional makes "exactly one menu" structural; this only presents it.
            .onChange(of: openMenu) {
                guard menuOpen else { return }
                syncMenuPanel(presenting: true)
            }
            // The hosted tree is its own hierarchy, so the highlight has to be pushed into it.
            .onChange(of: menuSelection) { syncMenuPanel(presenting: false) }
            .onChange(of: vm.menuQuery) { menuQueryChanged() }
            .onDisappear {
                menuPanel.hide()
                (hostWindow as? PalettePanel)?.onHeaderFieldBoundaryArrow = nil
            }
            // The first show builds this view after `prepare`, so no handler saw that reset.
            .onAppear {
                searchFocused = true
                land()
            }
            // Several paths flip `paletteIsCollapsed`, so resize the window to match.
            .onChange(of: core.paletteCoordinator.paletteIsCollapsed) {
                core.paletteCoordinator.syncPaletteSize()
            }
    }

    /// Split from `body`: one chain of this length is past what the type-checker will infer.
    @ViewBuilder
    private func keyHandlers(_ content: some View, selection sel: Int) -> some View {
        content
            // Repeat included: holding the key keeps stepping, as the bare-key form does.
            .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { press in
                if let reorder = movePinnedOrFavorite(1, modifiers: press.modifiers) { return reorder }
                if isCollapsed {
                    // The compact bar shows no selection, so Down reveals the list's first row.
                    vm.selection = 0
                    core.paletteCoordinator.expandFromCompact()
                    return .handled
                }
                if menuOpen {
                    moveMenu(1)
                    return .handled
                }
                return moveVertically(1)
            }
            .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { press in
                if let reorder = movePinnedOrFavorite(-1, modifiers: press.modifiers) { return reorder }
                if isCollapsed { return .ignored }
                if menuOpen {
                    moveMenu(-1)
                    return .handled
                }
                return moveVertically(-1)
            }
            // Horizontal arrows step the grid; elsewhere they stay with the caret.
            .onKeyPress(.leftArrow) {
                if menuOpen { return .handled }
                return moveHorizontally(-1) ? .handled : .ignored
            }
            .onKeyPress(.rightArrow) {
                if menuOpen { return .handled }
                return moveHorizontally(1) ? .handled : .ignored
            }
            // Plain ↵ runs an open menu's row or the selection.
            .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")], phases: .down) { press in
                let command = press.modifiers.contains(.command)
                let option = press.modifiers.contains(.option)
                if menuOpen, !command, !option {
                    activateMenuItem(menuSelection)
                    return .handled
                }
                let screen = screen
                guard command || option else {
                    guard !vm.isComposing, searchFocused else { return .ignored }
                    activateSelection()
                    return .handled
                }
                let selection = selection(in: screen)
                if command, press.modifiers.contains(.control), screen.tertiary(at: selection) {
                    return .handled
                }
                if command, press.modifiers.contains(.shift),
                    screen.perform(.copyCalculation, at: selection)
                {
                    return .handled
                }
                if command { return screen.secondary(at: selection) ? .handled : .ignored }
                return screen.pasteKeepingWindowOpen(at: selection) ? .handled : .ignored
            }
            .onKeyPress(.escape) {
                if menuPanel.isClosing { return .handled }
                switch PaletteEscapeAction.resolve(
                    menuOpen: menuOpen, menuQuery: vm.menuQuery,
                    argumentFocused: argumentFocused != nil, query: vm.query,
                    canGoBack: vm.canGoBack,
                    behavior: settings.escapeKeyBehavior)
                {
                case .clearMenuQuery, .closeMenu:
                    escapeMenu()
                case .leaveArgumentField:
                    returnFocusToSearchField()
                case .clearQuery:
                    vm.query = ""
                case .goBack:
                    goBack()
                case .hidePalette:
                    core.paletteCoordinator.hidePalette()
                    // This behavior promises a root search on reopen, whatever the delay says.
                    if settings.escapeKeyBehavior == .closeAndPopToRoot {
                        core.paletteCoordinator.popToRootNow()
                    }
                }
                return .handled
            }
            .onKeyPress(keys: [.tab], phases: .down) { press in
                if !menuOpen { advanceTabFocus(backwards: press.modifiers.contains(.shift)) }
                return .handled
            }
            // ⌘K toggles the actions panel for the current selection.
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.command),
                    ASCIIKeyboardLayout.matches(press.key, character: "k")
                else { return .ignored }
                // The Actions menu has no anchor in the compact bar, so swallow ⌘K there.
                guard !isCollapsed else { return .handled }
                let screen = screen
                guard !screen.rows.isEmpty else { return .handled }
                // An error calc card is the selection but has no actions — don't open an empty panel.
                guard screen.hasPrimaryAction(at: selection(in: screen)) else { return .handled }
                // Same for a menu the footer doesn't offer: ⌘K opens exactly what the bar advertises.
                guard screen.hasActions(at: selection(in: screen)) else { return .handled }
                toggleActions()
                return .handled
            }
            // The screen answers row chords; a bare backspace is intercepted in `sendEvent`.
            .onKeyPress(phases: .down) { press in
                let isDeleteKey = press.key == .delete || press.key == .deleteForward
                if isDeleteKey, menuOpen { return .handled }
                guard
                    let shortcut = PaletteShortcut.resolve(
                        command: press.modifiers.contains(.command),
                        shift: press.modifiers.contains(.shift),
                        option: press.modifiers.contains(.option),
                        control: press.modifiers.contains(.control),
                        isDeleteKey: isDeleteKey,
                        matches: { ASCIIKeyboardLayout.matches(press.key, character: $0) })
                else { return .ignored }
                guard !shortcut.requiresExpanded || !isCollapsed else { return .ignored }
                let screen = screen
                guard screen.perform(shortcut, at: selection(in: screen)) else { return .ignored }
                if shortcut.closesMenu, menuOpen { closeMenus() }
                return .handled
            }
            // Never gated on the rows: an over-narrow filter empties them, and this is the way out.
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.command),
                    ASCIIKeyboardLayout.matches(press.key, character: "p")
                else { return .ignored }
                return performFilterAction() ? .handled : .ignored
            }
    }

    /// A thin strip along the top edge for grabbing the window; the Appearance setting gates it.
    private var topDragStrip: some View {
        Color.clear
            .frame(height: metrics.size.headerPadding)
            .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
    }

    /// A header sliver nothing occupies — safe to drag; the search field handles its own.
    private func headerGutter(width: CGFloat) -> some View {
        Color.clear
            .frame(width: width)
            .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
    }

    private func beginDrag() { core.paletteCoordinator.beginPaletteDrag() }
    private func endDrag() { core.paletteCoordinator.endPaletteDrag() }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            // Matches the list rows and section headers' own indent below.
            headerGutter(width: metrics.spacing.md * 2)
            // Every sub-screen leaves the same way, so the slot reads the same on all of them.
            if vm.mode != .launcher {
                HeaderBackButton(help: backHelp, action: goBack)
            } else {
                Image(systemName: vm.mode.systemImage)
                    .font(metrics.typography.headerIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.size.headerIconSlot)
                    .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
            }
            // slot + xl equals a row's icon + lg, so the query starts where the row titles do.
            headerGutter(width: metrics.spacing.xl)
            // One structural position: a field inside a branch loses first responder when it flips.
            headerField
            if let accessory = headerAccessory {
                accessory.view
                // Given room last: at the default priority it would split it with the field.
                Spacer(minLength: 0).layoutPriority(-1)
            }
            // Keyed off the mode, which says which screen is up; the field just flexes narrower.
            if !isCollapsed, vm.mode == .clipboard {
                headerGutter(width: metrics.spacing.md)
                ClipboardFilterButton(
                    filter: vm.clipboardFilter, isOpen: openMenu == .clipboardFilter,
                    action: toggleClipboardFilter)
            }
            if !isCollapsed, vm.mode == .emoji {
                headerGutter(width: metrics.spacing.md)
                HeaderMenuButton(
                    title: vm.emojiCategoryFilter.title,
                    systemImage: vm.emojiCategoryFilter.systemImage,
                    isOpen: openMenu == .emojiCategory,
                    help: "Filter by category  ⌘P",
                    action: toggleEmojiCategory)
            }
            // Compact pins favorites beside the field; expanded shows them as rows.
            if isCollapsed, settings.showFavoritesInCompactMode,
                let launcher = screen as? LauncherScreen
            {
                let favorites = launcher.compactFavorites
                if !favorites.isEmpty {
                    headerGutter(width: metrics.spacing.md)
                    CompactFavoritesRow(
                        favorites: favorites,
                        showsOverflow: launcher.hasUnshownFavorites,
                        onLaunch: { core.launcherCoordinator.launch($0) },
                        onOverflow: { core.paletteCoordinator.expandFromCompact() }
                    )
                }
            }
            headerGutter(width: metrics.spacing.md * 2)
        }
        // Identical metrics in both states, so typing can't move the search bar.
        .frame(height: metrics.size.headerHeight)
        .padding(.top, metrics.size.headerPadding)
        .frame(maxWidth: .infinity)
        // Next turn, once the show's `land()` and search refocus are done, so neither undoes it.
        .onChange(of: vm.pendingArgumentEntryID) {
            Task { @MainActor in focusPendingArgument() }
        }
        .onChange(of: argumentFocused) { _, field in vm.noteEditingField(field != nil) }
    }

    /// Whichever screen offers one; the compact bar has no room for it.
    private var headerAccessory: PaletteHeaderAccessory? {
        guard !isCollapsed else { return nil }
        let screen = screen
        return screen.headerAccessory(at: selection(in: screen), focus: $argumentFocused)
    }

    /// The field, kept mounted rather than swapped: a branch would tear its editor down.
    private var headerField: some View {
        searchField
            // A ceiling, not a size, so the row squeezes a long query before the strip overruns.
            .frame(minWidth: searchFieldFloor, maxWidth: searchFieldWidth)
    }

    /// Fixed only where something shares the row: the accessory strip.
    private var searchFieldWidth: CGFloat? {
        headerAccessory.map(searchFieldWidth)
    }

    private var searchFieldFloor: CGFloat? {
        searchFieldWidth.map { min($0, metrics.size.searchFieldMinWidth) }
    }

    /// The field's own text, floored for the caret and capped so the strip stays on screen.
    /// Empty, that is the prompt where one is drawn — which is what seats the strip right after it.
    private func searchFieldWidth(for accessory: PaletteHeaderAccessory) -> CGFloat {
        let font = metrics.typography.searchFieldNSFont
        let text = vm.query.isEmpty ? searchPrompt : vm.query
        let typed = (text as NSString).size(withAttributes: [.font: font]).width
        let chrome = metrics.size.headerIconSlot + metrics.spacing.md * 3 + metrics.spacing.xl
        let room = metrics.size.panelWidth - accessory.width - chrome
        // +3pt so the caret sits after the last glyph rather than on top of it.
        return min(
            max(typed + metrics.scaled(3), metrics.scaled(18)),
            max(room, metrics.size.searchFieldMinWidth))
    }

    private var searchPrompt: String {
        // Squeezed to the caret, the field has no room for a prompt; beside one it keeps it.
        if headerAccessory?.placement == .afterQuery { return "" }
        return vm.mode.placeholder
    }

    /// The one search field — empty it's a drag handle, and any text hands every press to editing.
    private var searchField: some View {
        @Bindable var vm = vm
        return TextField("", text: $vm.query)
            .textFieldStyle(.plain)
            .font(metrics.typography.searchField)
            .tint(Theme.Colors.textPrimary)
            .focused($searchFocused)
            // Fills the row's height, so there's no gap above it for topDragStrip to meet.
            .frame(maxHeight: .infinity)
            .background(alignment: .leading) {
                // An IME's marked text leaves `query` empty, so the placeholder would overlap it.
                if vm.query.isEmpty, !vm.isComposing {
                    Text(searchPrompt)
                        .font(metrics.typography.searchField)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        // Never a click target: tapping the placeholder must still land the caret.
                        .allowsHitTesting(false)
                }
            }
            // The prompt used to carry this; without it the field would be unlabelled.
            .accessibilityLabel(Text(searchPrompt))
            // Never branches on query — that tore down the field editor mid-keystroke once.
            .overlay {
                if settings.paletteDraggable {
                    EmptyFieldDragHandle(
                        // Marked text leaves `query` empty, and composing it is still editing.
                        isEmpty: vm.query.isEmpty && !vm.isComposing,
                        onBegan: beginDrag, onEnded: endDrag,
                        // A press that never moved was aimed at the field the handle covers.
                        onClick: { searchFocused = true })
                }
            }
            // The panel resolves the pointer against this rather than hit-testing for the field.
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                vm.searchFieldFrame = $0
            }
    }

    /// The Uninstall screen's primary action is destructive, so its pill isn't white.
    private var pillTint: Color {
        vm.mode == .uninstall ? Theme.Colors.destructive : .primary
    }

    private func bottomBar(
        pillLabel: String, showActionGroup: Bool, showActions: Bool
    ) -> some View {
        // Floating controls, no bar; the edge dissolve ghosts the rows passing beneath.
        HStack(spacing: 0) {
            appMenuButton
            Spacer()
            if showActionGroup {
                actionGroup(pillLabel: pillLabel, showActions: showActions)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: metrics.size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    private var appMenuButton: some View {
        MenuCircleButton {
            if openMenu == .app { closeMenus() } else { open(.app, highlighting: 0) }
        }
    }

    /// The footer control group: primary action and the Actions toggle sharing one glass capsule.
    private func actionGroup(pillLabel: String, showActions: Bool) -> some View {
        HStack(spacing: 2) {
            BarButton(action: activateSelection) {
                HStack(spacing: metrics.spacing.sm) {
                    Text(pillLabel)
                        .font(metrics.typography.bar)
                        .foregroundStyle(pillTint)
                    KeyCapChip(text: "↵", style: .outline)
                }
            }
            if showActions {
                BarButton(action: toggleActions) {
                    HStack(spacing: metrics.spacing.sm) {
                        Text("Actions")
                            .font(metrics.typography.bar)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        HStack(spacing: metrics.spacing.xxs) {
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "K", style: .outline)
                        }
                    }
                }
            }
        }
        .padding(metrics.spacing.xs)
        .frosted(in: Capsule())
    }

    /// The one path opening the Actions menu, sampling the state its rows depend on.
    private func openActions() {
        let launcher = screen as? LauncherScreen
        selectionIsRunning = launcher.map { $0.isRunning(at: selection(in: $0)) } ?? false
        open(.actions, highlighting: 0)
    }

    private func toggleActions() {
        if openMenu == .actions {
            closeMenus()
        } else {
            openActions()
        }
    }

    /// Opens on the active filter, so the current value is the highlighted row like a pop-up's.
    private func toggleClipboardFilter() {
        if openMenu == .clipboardFilter {
            closeMenus()
            return
        }
        let active = ClipboardFilter.allCases.firstIndex(of: vm.clipboardFilter) ?? 0
        open(.clipboardFilter, highlighting: active)
    }

    private func performFilterAction() -> Bool {
        switch PaletteFilterAction.resolve(collapsed: isCollapsed, mode: vm.mode) {
        case .clipboardFilter: toggleClipboardFilter()
        case .emojiCategory: toggleEmojiCategory()
        case .ignored: return false
        }
        return true
    }

    private func toggleEmojiCategory() {
        if openMenu == .emojiCategory {
            closeMenus()
            return
        }
        let active = EmojiCategoryFilter.allCases.firstIndex(of: vm.emojiCategoryFilter) ?? 0
        open(.emojiCategory, highlighting: active)
    }

    /// Every header menu states its own width, so resizing one never moves another.
    private func headerMenu(
        _ popover: PopoverMenuContent, width: CGFloat
    ) -> PaletteMenuContent {
        let filtered = popover.matching(ActionMenuSearchQuery(vm.menuQuery))
        return PaletteMenuContent(
            popover: filtered.content, selection: $menuSelection, width: width,
            search: PopoverMenu.Search(placeholder: "Search…", placement: .top),
            onActivate: activateMenuItem, preferredSelection: filtered.bestMatch)
    }

    /// Every open path lands here, so the highlight is always stated rather than left behind.
    private func open(_ menu: OpenMenu, highlighting row: Int) {
        vm.menuQuery = ""
        menuSelection = row
        vm.noteMenuPresentation()
        openMenu = menu
        vm.menuOpen = true
    }

    private func closeMenus() {
        menuPanel.hide()
        openMenu = nil
        argumentOptionsField = nil
        vm.menuQuery = ""
        // Stated here rather than mirrored later: the window delegate reads it during this turn.
        vm.menuOpen = false
    }

    private func menuQueryChanged() {
        guard menuOpen, let content = menuContent else { return }
        let next =
            content.preferredSelection
            ?? (0..<content.rowCount).first(where: content.isSelectable) ?? 0
        guard next == menuSelection else {
            menuSelection = next
            return
        }
        syncMenuPanel(presenting: false)
    }

    /// Drives the menu's window from the two pieces of state that decide what it shows.
    private func syncMenuPanel(presenting: Bool) {
        guard let content = menuContent, let corner = menuCorner else {
            menuPanel.hide()
            return
        }
        let view = content.view(corner)
        if presenting, let hostWindow {
            menuPanel.show(
                view, corner: corner, parent: hostWindow, core: core,
                clipPath: content.clipPath, motion: content.motion,
                onKeyDown: handleMenuPanelKey, onDismiss: closeMenus)
        } else {
            menuPanel.update(
                view, corner: corner, core: core, clipPath: content.clipPath,
                motion: content.motion)
        }
    }

    private func handleMenuPanelKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
        let navigationModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if event.charactersIgnoringModifiers == "\u{1B}" {
            escapeMenu()
            return true
        }
        switch event.specialKey {
        case .some(.downArrow) where navigationModifiers.isEmpty:
            moveMenu(1)
            return true
        case .some(.upArrow) where navigationModifiers.isEmpty:
            moveMenu(-1)
            return true
        case .some(.carriageReturn), .some(.enter):
            let screen = screen
            let selection = selection(in: screen)
            if modifiers.contains([.command, .control]), screen.tertiary(at: selection) { return true }
            if modifiers.contains([.command, .shift]),
                screen.perform(.copyCalculation, at: selection)
            {
                return true
            }
            if modifiers.contains(.command) { return screen.secondary(at: selection) }
            if modifiers.contains(.option) {
                return screen.pasteKeepingWindowOpen(at: selection)
            }
            activateMenuItem(menuSelection)
            return true
        case .some(.tab), .some(.backTab):
            return true
        default:
            break
        }

        guard !modifiers.isDisjoint(with: [.command, .control]) else { return false }
        let character =
            ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
        if modifiers.contains(.control) {
            if character == "n" {
                moveMenu(1)
                return true
            }
            if character == "p" {
                moveMenu(-1)
                return true
            }
        }
        if modifiers.contains(.command), character == "k" {
            toggleActions()
            return true
        }
        if modifiers.contains(.command), character == "p", performFilterAction() { return true }
        if let shortcut = PaletteShortcut.resolve(
            command: modifiers.contains(.command), shift: modifiers.contains(.shift),
            option: modifiers.contains(.option), control: modifiers.contains(.control),
            isDeleteKey: false, matches: { character == String($0).lowercased() })
        {
            let screen = screen
            guard screen.perform(shortcut, at: selection(in: screen)) else { return false }
            if shortcut.closesMenu { closeMenus() }
            return true
        }
        if modifiers.contains(.command),
            (hostWindow as? PalettePanel)?.onCommandShortcut?(event) == true
        {
            return true
        }
        return false
    }

    private func escapeMenu() {
        if vm.menuQuery.isEmpty {
            closeMenus()
        } else {
            vm.menuQuery = ""
        }
    }

    /// An action can remove the last visible pin; never leave an invisible menu owning input.
    private func refreshActionsMenu() {
        guard openMenu == .actions else { return }
        guard menuContent != nil else {
            closeMenus()
            return
        }
        syncMenuPanel(presenting: false)
    }

    private var menuCorner: MenuPanelCorner? {
        switch openMenu {
        case .app: .bottomLeading
        case .actions: .bottomTrailing
        case .argumentOptions: .belowHeaderTrailing
        case .clipboardFilter, .emojiCategory: .belowHeaderTrailing
        case nil: nil
        }
    }

    // MARK: - Actions

    /// Every reset lands here, so handlers that fire together agree in whatever order they run.
    private func land() {
        let landing = screen.landingSelection
        vm.selection = landing
        scroll = ScrollIntent(kind: landing == 0 ? .top : .center)
    }

    private func move(_ delta: Int, in screen: any PaletteScreen) {
        let count = screen.rows.count
        guard count > 0 else { return }
        vm.selection = min(max(selection(count: count) + delta, 0), count - 1)
        scroll = ScrollIntent(kind: .follow)
    }

    /// ↑/↓: the screen's own move where it has one, else a linear step through the rows.
    private func moveVertically(_ delta: Int) -> KeyPress.Result {
        let screen = screen
        // Moving off a command takes its argument fields with it, so hand focus back first.
        if argumentFocused != nil { returnFocusToSearchField() }
        guard let next = screen.move(delta, axis: .vertical, from: selection(in: screen)) else {
            move(delta, in: screen)
            return .handled
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return .handled
    }

    /// ←/→: consumed only by a horizontally navigating screen, else the caret keeps them.
    private func moveHorizontally(_ delta: Int) -> Bool {
        let screen = screen
        guard let next = screen.move(delta, axis: .horizontal, from: selection(in: screen)) else {
            return false
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return true
    }

    /// Claimed whole on the launcher and emoji grid, so a press at an end cannot reach the caret.
    private func movePinnedOrFavorite(
        _ delta: Int, modifiers: SwiftUI.EventModifiers
    ) -> KeyPress.Result? {
        guard modifiers.contains(.command), modifiers.contains(.option), !isCollapsed else {
            return nil
        }
        if let launcher = screen as? LauncherScreen {
            if launcher.moveFavorite(delta, at: selection(in: launcher)), menuOpen { closeMenus() }
            return .handled
        }
        guard let emoji = screen as? EmojiScreen else { return nil }
        emoji.movePin(delta, at: selection(in: emoji))
        return .handled
    }

    /// Move the open menu's highlight past rows it cannot land on, stopping at the ends (no wrap).
    private func moveMenu(_ delta: Int) {
        guard let content = menuContent else { return }
        var row = menuSelection + delta
        while (0..<content.rowCount).contains(row) {
            if content.isSelectable(row) {
                menuSelection = row
                return
            }
            row += delta
        }
    }

    /// The one activation path for a menu row: run its action, then close.
    private func activateMenuItem(_ index: Int) {
        guard let content = menuContent, (0..<content.rowCount).contains(index) else { return }
        guard content.isSelectable(index) else { return }
        // Before the action: one opening a window must find the palette key again, or nothing hides it.
        closeMenus()
        // A mouse click on a row takes the caret with it; menus close back into the field.
        if argumentFocused == nil { searchFocused = true }
        content.activate(index)
    }

    /// For the chords the panel hands over as tokens, which work while a menu is open.
    private func performShortcut(_ shortcut: PaletteShortcut) {
        let screen = screen
        _ = screen.perform(shortcut, at: selection(in: screen))
    }

    /// A ring hop leaves a step back — except the hop closing the ring on the launcher, its root.
    private func cycleMode() {
        switch PaletteTabAction.resolve(mode: vm.mode, clipboardEnabled: settings.clipboardEnabled) {
        case .carryQuery(.launcher):
            vm.mode = .launcher
            vm.resetNavigation()
        case .carryQuery(let mode): vm.pushCarryingQuery(mode: mode)
        }
    }

    /// Tab walks a screen's own fields first, then the inline arguments, then rings the modes.
    private func advanceTabFocus(backwards: Bool) {
        let screen = screen
        if screen.tab(at: selection(in: screen), backwards: backwards) { return }
        guard let accessory = headerAccessory, !accessory.fieldNames.isEmpty else {
            return cycleMode()
        }
        // Read from the local value: a `@FocusState` set in this tick still reads back stale.
        let next = accessory.field(after: argumentFocused, backwards: backwards)
        argumentFocused = next
        searchFocused = next == nil
    }

    /// Right at an inline field's end and Left at its start continue the same ring as Tab.
    private func installHeaderArrowHandler(in window: NSWindow?) {
        guard let panel = window as? PalettePanel else { return }
        panel.onHeaderFieldBoundaryArrow = { boundary in
            guard !menuOpen, !isCollapsed,
                let accessory = headerAccessory, !accessory.fieldNames.isEmpty
            else { return false }
            switch boundary {
            case .leading:
                // Query's left edge keeps its normal caret behavior; an argument moves back.
                guard argumentFocused != nil else { return false }
                advanceTabFocus(backwards: true)
            case .trailing:
                advanceTabFocus(backwards: false)
            }
            return true
        }
    }

    /// AppKit selects the whole query as the field editor comes back, which is the wanted reset.
    private func returnFocusToSearchField() {
        argumentFocused = nil
        searchFocused = true
    }

    /// The palette was opened to fill one row's fields, so the caret starts in the first empty one.
    private func focusPendingArgument() {
        guard vm.pendingArgumentEntryID != nil,
            let field = headerAccessory?.firstIncompleteField
        else { return }
        argumentFocused = field
        searchFocused = false
        vm.pendingArgumentEntryID = nil
    }

    /// An `options=` field is chosen from the palette's own menu, never typed into.
    private func openArgumentOptions(_ field: String) {
        guard let accessory = headerAccessory, accessory.optionsMenu(field) != nil else { return }
        argumentFocused = field
        searchFocused = false
        argumentOptionsField = field
        open(.argumentOptions, highlighting: 0)
    }

    /// Never promises a step the click does not take: a root screen closes rather than backs.
    private var backHelp: String {
        let escape = vm.canGoBack ? "Esc to go back" : "Esc to close"
        return "\(escape) or ⌘ Esc to go to root search"
    }

    private func goBack() {
        if !vm.pop() { core.paletteCoordinator.hidePalette() }
    }

    private func activateSelection() {
        // Nothing is visibly selected when collapsed, so launch via ⌘1–⌘5 or typing.
        guard !isCollapsed else { return }
        // An unfilled field blocks the launch; focus it instead of acting on a half-typed row.
        if let incomplete = headerAccessory?.firstIncompleteField {
            argumentFocused = incomplete
            searchFocused = false
            return
        }
        let screen = screen
        screen.activate(at: selection(in: screen))
    }

}

/// The palette's in-window menus. One optional of these is the whole "only one is open" invariant.
private enum OpenMenu {
    case actions
    /// An `options=` argument field's choices, hung under the header where the chip sits.
    case argumentOptions
    case app
    case clipboardFilter
    case emojiCategory
}

/// Reads visibility in its own body, so a summon never re-renders the palette's.
private struct PaletteHideObserver: ViewModifier {
    @Environment(PaletteState.self) private var vm
    let onHide: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: vm.isVisible) { _, visible in
            if !visible { onHide() }
        }
    }
}

/// The footer's menu circle; hover lives here, so a sweep never re-renders the body.
private struct MenuCircleButton: View {
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: metrics.size.menuButton, height: metrics.size.menuButton)
            .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

/// Hover state lives here, so lighting the chevron never re-renders the header around it.
private struct HeaderBackButton: View {
    let help: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(metrics.typography.headerIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: metrics.size.headerIconSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
        .help(help)
    }
}
