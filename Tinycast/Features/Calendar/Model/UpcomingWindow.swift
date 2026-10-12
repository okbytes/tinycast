import Foundation

/// Which meeting is worth showing, and whether it is time. Every clock read is an injected `now`.
struct UpcomingWindow: Sendable {
    /// The one place the rule lives, so the menu bar's label and its agenda cannot drift.
    static func agenda(from events: [MeetingEvent], now: Date) -> [MeetingEvent] {
        events
            .filter { !$0.isAllDay && !$0.isDeclined && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    static func countdown(to start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)
        if delta > 0 { return "in \(duration(delta, rounding: .up))" }
        return "Now"
    }

    /// The menu bar names the time left once a meeting has been underway for five minutes.
    static func menuBarCountdown(for event: MeetingEvent, now: Date) -> String {
        if now < event.start { return countdown(to: event.start, now: now) }
        if now < event.start.addingTimeInterval(5 * 60) { return "Now" }
        if now < event.end { return "\(duration(event.end.timeIntervalSince(now), rounding: .down)) left" }
        return "Now"
    }

    private static func duration(
        _ interval: TimeInterval, rounding: FloatingPointRoundingRule
    ) -> String {
        let minutes = max(1, Int((interval / 60).rounded(rounding)))
        guard minutes > 60 else { return "\(minutes) min" }
        let hours = max(1, Int((Double(minutes) / 60).rounded()))
        return "\(hours) hr"
    }
}
