import AppKit

/// Owns the calendar's menu bar: the consent gate, the event it carries, feature presence.
@MainActor
@Observable
final class CalendarCoordinator {
    private let store: CalendarStore
    private let clock: MeetingClock
    private let settings: AppSettings
    /// The consent dialog, so it stays owned by `AppCore`.
    private unowned let core: AppCore

    /// Stored and written only on a flip: the menu-bar scene reads it, and must not re-run per tick.
    private(set) var hasMenuBarEvent = false
    /// Dismissed from the menu bar this launch: a reaction to what is on screen, not a preference.
    private var dismissedFromMenuBar: Set<MeetingEvent.ID> = []

    init(
        store: CalendarStore,
        clock: MeetingClock,
        settings: AppSettings,
        core: AppCore
    ) {
        self.store = store
        self.clock = clock
        self.settings = settings
        self.core = core
    }

    /// The calendar label keeps its plain icon until today's events are exhausted, with a small
    /// grace across midnight for a meeting that starts imminently.
    var hasUpcomingMenuBarEvent: Bool {
        MenuBarSummary.hasUpcomingEvent(from: store.events, now: clock.now)
    }

    /// The event the menu bar carries, or nil for the plain icon.
    var menuBarEvent: MeetingEvent? {
        guard settings.calendarEnabled, settings.calendarMenuBarDisplay != .disabled else {
            return nil
        }
        let summary = MenuBarSummary(
            leadMinutes: settings.menuBarEvents == .today ? nil : settings.menuBarEvents.rawValue,
            hideAfterMinutes: settings.hideCurrentEvent.minutes,
            linkedOnly: settings.menuBarLinkedEventsOnly,
            hideCurrentAtStart: settings.hideCurrentEvent.hidesAtStart)
        return summary.event(
            from: store.events, now: clock.now, dismissed: dismissedFromMenuBar)
    }

    /// The menu bar's day-by-day list; clock-driven, so a meeting that ends leaves on the minute.
    var menuBarAgenda: [MeetingDayGroup] {
        let now = clock.now
        return MeetingDayGroup.grouping(
            UpcomingWindow.agenda(from: store.events, now: now), now: now, calendar: .current)
    }

    /// Dismisses what the menu drew: a handover mid-click must not eat the arriving event.
    func dismissMenuBarEvent(_ meeting: MeetingEvent) {
        dismissedFromMenuBar.insert(meeting.id)
        refreshMenuBarEvent()
    }

    // MARK: - Feature switch

    /// The switch funnels here so enabling, which is also consent, confirms first.
    func setCalendarEnabled(_ enabled: Bool) {
        if !enabled {
            guard settings.calendarEnabled else { return }
            settings.calendarEnabled = false
            return
        }

        // Asking again is the only way back: Settings cannot add an app TCC has no record of.
        store.refreshAccess()
        guard !settings.calendarEnabled || store.access != .granted else { return }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable calendar?",
                    message:
                        "Tinycast reads \(settings.calendarSpan.possessivePhrase) events "
                        + "for the menu bar. Nothing leaves this Mac.",
                    symbol: "calendar", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }

            guard await store.requestAccess() else { return }
            // The flag is consent, so it is written only once macOS has actually granted access.
            settings.calendarEnabled = true
            applyEnabled()
        }
    }

    /// Starts or stops everything the feature runs, as the switch says.
    func applyEnabled() {
        let enabled = settings.calendarEnabled
        guard enabled else {
            store.stop()
            clock.stop()
            refreshMenuBarEvent()
            return
        }
        store.onChange = { [weak self] in
            self?.refreshMenuBarEvent()
        }
        clock.onTick = { [weak self] in self?.minuteDidPass() }
        applySpan()
        store.start()
        applyClock()
    }

    /// Changing which days are read re-queries EventKit, so it goes through the store.
    func applySpan() {
        store.span = settings.calendarSpan
    }

    /// The clock runs only while the menu bar shows the calendar; otherwise no timer exists.
    func applyClock() {
        let watched = settings.calendarMenuBarDisplay != .disabled
        guard settings.calendarEnabled, watched else {
            clock.stop()
            return
        }
        clock.start()
        refreshMenuBarEvent()
    }

    /// An event ending changes nothing in EventKit, so the tick is what drops it.
    private func minuteDidPass() {
        store.reloadIfStale(now: clock.now)
        refreshMenuBarEvent()
    }

    private func refreshMenuBarEvent() {
        forgetStaleDismissals()
        let hasEvent = menuBarEvent != nil
        guard hasEvent != hasMenuBarEvent else { return }
        hasMenuBarEvent = hasEvent
    }

    /// Assigned only on a change: a write every tick would re-run the label for nothing.
    private func forgetStaleDismissals() {
        guard !dismissedFromMenuBar.isEmpty else { return }
        let live = dismissedFromMenuBar.intersection(store.events.map(\.id))
        guard live != dismissedFromMenuBar else { return }
        dismissedFromMenuBar = live
    }

    /// Calendar.app's own handle; a recurring occurrence opens its series.
    func openInCalendar(_ meeting: MeetingEvent) {
        guard
            let url = URL(
                string: "ical://ekevent/\(meeting.calendarItemID)?method=show&options=more")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
