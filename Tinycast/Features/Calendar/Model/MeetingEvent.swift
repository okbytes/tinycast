import Foundation

/// One calendar occurrence, flattened out of EventKit so nothing EventKit-shaped reaches a view.
struct MeetingEvent: Identifiable, Hashable, Sendable {
    /// Unique per occurrence: a recurring series shares one event identifier across every instance.
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isDeclined: Bool
    let calendarColor: CalendarColor?
    /// EventKit's `calendarItemIdentifier` — the only handle Calendar.app's `ical://` URL accepts.
    let calendarItemID: String
    let link: MeetingLink?

    func isInProgress(now: Date) -> Bool { start <= now && now < end }
}

extension MeetingEvent {
    /// The owning calendar's colour as sRGB components, so the model stays free of AppKit.
    struct CalendarColor: Hashable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }
}
