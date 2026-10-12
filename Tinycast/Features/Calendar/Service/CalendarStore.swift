import AppKit
import EventKit

/// The span's meetings, read from EventKit. See docs/features/calendar.md.
@MainActor
@Observable
final class CalendarStore {
    /// Flattened occurrences over `span`, newest query wins.
    private(set) var events: [MeetingEvent] = []
    private(set) var calendars: [MeetingCalendar] = []
    private(set) var access: CalendarAccess = Permissions.calendarAccess()

    /// Changing it re-reads: nothing may filter a snapshot into a span it never fetched.
    var span: MeetingSpan = .todayAndTomorrow {
        didSet {
            guard span != oldValue, lastReloadAt != nil else { return }
            reload()
        }
    }

    /// Fired whenever `events` changes, so the menu bar re-checks the event it carries.
    @ObservationIgnored var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let hiddenKey = "hiddenMeetingCalendars"
    /// Exclusions, not inclusions, so a calendar added after this was written defaults to on.
    private var hiddenCalendarIDs: Set<String>

    /// Built on first use, so a Mac with the feature off never loads EventKit at launch.
    @ObservationIgnored private var eventStore: EKEventStore?
    @ObservationIgnored private var changeObserver: NotificationToken?
    @ObservationIgnored private var wakeObserver: NotificationToken?
    @ObservationIgnored private var lastReloadAt: Date?

    /// Covers the day rolling over and a Mac that slept; edits come from EventKit.
    private static let staleAfter: TimeInterval = 10 * 60

    init() {
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    }

    /// TCC sends nothing when a grant changes in Settings, so anything acting on `access` re-reads.
    func refreshAccess() {
        access = Permissions.calendarAccess()
    }

    // MARK: - Lifecycle

    func start() {
        refreshAccess()
        guard access == .granted else { return }
        observeWake()
        // Deferred: the first EventKit query pays for its XPC warm-up, and launch protects itself.
        Task { reload() }
    }

    func stop() {
        changeObserver = nil
        wakeObserver = nil
        eventStore = nil
        lastReloadAt = nil
        publish([])
        calendars = []
    }

    /// Tinycast's own consent dialog has already been accepted by the time this runs.
    func requestAccess() async -> Bool {
        let granted = await Permissions.requestCalendarAccess()
        refreshAccess()
        guard granted else { return false }
        // A store built before the grant never sees the new calendars; drop it and rebuild.
        changeObserver = nil
        eventStore = nil
        reload()
        return true
    }

    /// EventKit says when to reload; the minute tick covers what it never announces.
    private func observeStoreChanges() {
        guard changeObserver == nil, let eventStore else { return }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        changeObserver = NotificationToken(token, center: center)
    }

    /// A Mac asleep through a meeting wakes with a stale snapshot and no edit to trigger a reload.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        wakeObserver = NotificationToken(token, center: center)
    }

    // MARK: - Reading

    /// The per-minute refresh: cheap when the snapshot still holds, which is almost always.
    func reloadIfStale(now: Date) {
        guard let lastReloadAt else {
            reload()
            return
        }
        let aged = now.timeIntervalSince(lastReloadAt) >= Self.staleAfter
        // A day boundary invalidates the span itself, however fresh the snapshot is.
        let rolled = !Calendar.current.isDate(lastReloadAt, inSameDayAs: now)
        guard aged || rolled else { return }
        reload()
    }

    /// `EKEventStore` is not `Sendable`, so this stays on main; only pure values leave.
    func reload() {
        refreshAccess()
        guard access == .granted else {
            publish([])
            return
        }
        let store = eventStore ?? EKEventStore()
        eventStore = store
        observeStoreChanges()
        lastReloadAt = Date()

        let sources = store.calendars(for: .event)
        calendars =
            sources
            .map {
                MeetingCalendar(
                    id: $0.calendarIdentifier, title: $0.title, accountName: $0.source.title)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let selected = sources.filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty,
            let interval = span.interval(from: Date(), calendar: .current)
        else {
            publish([])
            return
        }
        // The predicate expands recurrence itself; rolling our own never works.
        let predicate = store.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: selected)
        publish(store.events(matching: predicate).compactMap(Self.meeting(from:)))
    }

    private func publish(_ next: [MeetingEvent]) {
        guard next != events else { return }
        events = next
        onChange?()
    }

    private static func meeting(from event: EKEvent) -> MeetingEvent? {
        // A cancelled event is not happening, so it never reaches a surface.
        guard event.status != .canceled, let start = event.startDate, let end = event.endDate,
            let calendar = event.calendar
        else { return nil }
        let me = event.attendees?.first { $0.isCurrentUser }
        return MeetingEvent(
            id: occurrenceID(of: event, start: start),
            title: event.title ?? "(No Title)",
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            isDeclined: me?.participantStatus == .declined,
            calendarColor: color(of: calendar),
            calendarItemID: event.calendarItemIdentifier,
            link: MeetingLink.detect(
                fields: [event.url?.absoluteString, event.location, event.notes]))
    }

    private static func occurrenceID(of event: EKEvent, start: Date) -> MeetingEvent.ID {
        (event.eventIdentifier ?? event.calendarItemIdentifier)
            + "|\(start.timeIntervalSinceReferenceDate)"
    }

    private static func color(of calendar: EKCalendar) -> MeetingEvent.CalendarColor? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let components = calendar.cgColor?.converted(
                to: space, intent: .defaultIntent, options: nil)?.components,
            components.count >= 3
        else { return nil }
        return MeetingEvent.CalendarColor(
            red: components[0], green: components[1], blue: components[2])
    }

    // MARK: - Per-calendar switches

    func isEnabled(_ calendar: MeetingCalendar) -> Bool {
        !hiddenCalendarIDs.contains(calendar.id)
    }

    func setEnabled(_ enabled: Bool, for calendar: MeetingCalendar) {
        if enabled {
            hiddenCalendarIDs.remove(calendar.id)
        } else {
            hiddenCalendarIDs.insert(calendar.id)
        }
        defaults.set(Array(hiddenCalendarIDs), forKey: hiddenKey)
        reload()
    }
}
