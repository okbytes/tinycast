# Calendar

One surface over the Mac's own calendar: a **menu-bar item** that shows what is coming up next at a
glance, lists the schedule on click, and hands any event to Calendar.app.

## Invariants

- **Nothing polls, and there is one timer.** `.EKEventStoreChanged` is the reload signal, held
  through the RAII `NotificationToken`, and `NSWorkspace.didWakeNotification` covers the sleep it
  cannot. `MeetingClock` is the only timer: one tick on the minute boundary, running **only while the
  menu bar shows the calendar item**. With `Calendar in Menu Bar` on Disabled, an idle Mac owns no
  timer at all. `CalendarCoordinator.applyClock` is the one place that decides, and the clock's `Task`
  is stored and cancelled in `stop()` and in an `isolated deinit`.
- **Recurrence comes from `predicateForEvents(withStart:end:calendars:)`**, which expands occurrences
  itself. Masters are never fetched and recurrence is never hand-rolled.
- **`MeetingSpan` narrows the fetch, never what the menu bar filters.** `calendarSpan` reaches EventKit
  through `CalendarStore.span`, so a shorter span shortens the query and both the label and the agenda
  follow from the one snapshot. Nothing filters days out of a snapshot fetched wider. The same type
  owns the wording, so a sentence naming the days can never outlive the query it describes.
- **`UpcomingWindow.agenda` is the only place that says which events count** — timed, not declined,
  not over, in start order. The label (through `MenuBarSummary`) and the agenda both go through it, so
  they cannot drift apart. Because an event ending changes nothing in EventKit, the filter alone is not
  enough: the minute tick re-derives what the item carries.
- **The menu bar's `Today` horizon follows the same empty-state rule.** It carries any remaining
  event that starts today, plus an event within 30 minutes after midnight; only then does the title
  mode read `No upcoming events`.
- **`calendarEnabled` doubles as consent**, so it is in `SettingsBackupCoverage.deliberatelyExcluded`
  and only `CalendarCoordinator.setCalendarEnabled` may write it. Tinycast's own dialog comes first,
  the macOS prompt second, and only from the gesture that asked. **It is written only after macOS
  grants**, so a prompt that fails or is dismissed can never leave the feature reading as on with no
  access. Enabling is re-offered whenever access is anything but granted — by the Calendar pane and by
  the Permissions pane — so a TCC record lost after the setting was already on never strands it.
- **Per-calendar toggles live on `CalendarStore`, not `AppSettings`.** Calendar identifiers are
  machine-specific, so they are deliberately outside the backup mirror — the same reasoning as
  `palettePosition`.
- **`MeetingEvent` carries only what the menu bar needs.** The event's URL, location and notes are
  scanned for a link and dropped, and attendees are read only for the user's own response, so a busy
  calendar's invites never sit in the snapshot every tick diffs.
- **`Model/` stays Foundation-only**; `calendar-test` compiles the shipped sources. EventKit lives in
  `Service/CalendarStore.swift` and nothing EventKit-shaped leaves it.

## The pure layer

`Model/` holds the whole decision, with every clock read injected:

- **`MeetingLink`** — the meeting link the event carries, plus its `Provider`. Ten named services,
  plus `.generic` for any other `http(s)` link.
- **`MeetingEvent`** — one occurrence, flattened out of `EKEvent`.
- **`MeetingCalendar`** — one calendar for the Settings list, with the account that owns it.
- **`UpcomingWindow`** — `agenda`, plus the `countdown` and `menuBarCountdown` the title reads.
- **`MeetingDay`** — the day a meeting falls on, titled `Today, Oct 2`, `Tomorrow, Oct 3`, then
  `Monday, Oct 5`. A meeting still running from before midnight is Today. `MeetingDayGroup.grouping`
  cuts the agenda into the menu's day sections.
- **`MeetingSpan`** — how far ahead the store reads, and the phrasing that names those days.
- **`MenuBarSummary`** — which event the menu bar carries, and for how long.

### Finding the link

Tinycast never opens the link. It decides two things only: the glyph **Meeting Icon** draws, and what
`Only show events with meetings` keeps.

`MeetingLink.detect(fields:)` is handed `[event.url, event.location, event.notes]` in that order and
scans each for `http(s)` runs. **A named provider anywhere beats a bare link found earlier**, so a
"reset your password" URL at the top of an invite never wins over the Meet link below it.

Link extraction is hand-rolled rather than `NSDataDetector`: a detector is not `Sendable`, and
rebuilding one per event costs more than the scan it replaces. A URL ends at whitespace or a quote,
and trailing punctuation is trimmed, so `(https://whereby.com/acme).` yields the URL alone.

**A URL on a known host that fails that provider's path rule is rejected outright, not demoted to
`.generic`** — `zoom.us/download` sits in half the invites people are sent, and `meet.google.com/tel/…`
is a dial-in helper rather than a meeting.

No brand artwork ships with the app, so every named provider draws `video.fill`; `.generic` draws
`link`.

## Reading the store

`CalendarStore` queries `MeetingSpan.interval(from:calendar:)` — midnight today through midnight one,
two or seven days on, in the Mac's own zone — and re-reads whenever `span` changes under it, but only once
it has read at all, so enabling the feature never fires two queries. **The fetch stays on the main
actor**: at most a week of events is a sub-millisecond query and `EKEventStore` is not `Sendable`, so
pushing it off-main would be a fight with no measurable gain. The launch-time load is deferred into a
`Task`, because the first EventKit query pays for its XPC warm-up and launch is protected.

The minute tick calls `reloadIfStale`, which reads again only once the snapshot is ten minutes old or
was taken before midnight: a new day changes the span itself, and EventKit announces neither.

The `EKEventStore` itself is built on first use, so a Mac with the feature off never loads EventKit.
After a grant the store is dropped and rebuilt — one built before the grant does not see the new
calendars.

`MeetingEvent.id` is the event identifier plus the occurrence's start, because a recurring series
shares one identifier across every instance. `calendarItemID` is kept separately: it is the only
handle `ical://ekevent/…` accepts, and a recurring occurrence opens its series.

A cancelled event never reaches the menu bar. A declined one is dropped by `agenda`, and an all-day or
already-finished one with it.

## The menu bar

`MenuBarSummary` decides what the menu-bar item carries: the earliest event still inside its window,
which is `[start - lead, start)` for **Automatically** and `[start - lead, min(start + hideAfter, end))`
for the timed options. Because the earliest qualifying event wins, one hiding hands the space to the
next with no extra logic. **Keep visible — show time left** leaves a started meeting up until it ends:
it reads `Now` during the first five minutes, then its remaining time.

**The calendar's item and Tinycast's own item are two independent `MenuBarExtra` scenes**, each
inserted by one preference and reading nothing off the other: `showInMenuBar` on General for
Tinycast's, `calendarMenuBarDisplay` here for the calendar's. Either may be the only one in the menu
bar, both may be, or neither. Dragging the calendar item out writes `.disabled`, which is what the
picker already said — it never touches `showInMenuBar`.

The display choice is **Disabled**, **Meeting Icon**, or **Meeting Title**; the title reads
`title • in X min` and is capped at `MenuBarSummary.titleCap` characters — a hard cap is the only
thing that bounds a menu bar. `CalendarMenuBarLabel` reads the coordinator rather than the stores,
which scopes Observation to the label instead of re-running either scene. It falls back to a calendar
glyph when nothing is due, so the calendar item never disappears out from under the user. In **Meeting
Title** mode, once no event remains today it instead reads `No upcoming events`.

**Hide when there are no upcoming events** instead takes the item out whenever it would show the bare
glyph or that placeholder — whenever `menuBarEvent` is nil — so it follows `Show Upcoming Events`,
`Only show events with meetings` and `Hide Current Event` rather than adding a rule of its own: on
*Today* it leaves after the day's last event, on a minutes lead it also leaves between meetings. The
scene has to read that fact, so `CalendarCoordinator.hasMenuBarEvent` is **stored and written only
when it flips** — a derived read would re-run `TinycastApp.body`, and the main menu with it, on every
minute tick. SwiftUI writes
`false` back through `isInserted` when it removes the item itself, so the insertion setter ignores a
removal while the item is hidden for being empty: only a drag-out turns the display to `.disabled`.

`CalendarMenuBarMenu` lists calendar actions only — `Open in Calendar` and `Dismiss Event` for the
displayed event, then the agenda, then `Calendar Settings…` (⌘,) — so the two menus never repeat each
other. Each block is a `Section`, so SwiftUI draws the separators and a missing block never leaves a
stray one.

The agenda is `CalendarCoordinator.menuBarAgenda`: `UpcomingWindow.agenda` over the span, read off
`MeetingClock`, so a meeting that ends leaves on the minute, then cut into one section per day by
`MeetingDayGroup`. Each row reads `start – end title` beside a ring in its calendar's colour, filled
while the meeting is under way, and a click opens that event in Calendar.app. **It is the schedule,
not the title's candidate list**: it ignores `Only show events with meetings` and dismissals, which
decide only what the item itself shows, and keeps the displayed event so the list never shifts
under a handover.

`Open in Calendar` and an agenda row go through one path, `CalendarCoordinator.openInCalendar`, which
hands `ical://ekevent/<calendarItemID>?method=show&options=more` to Calendar.app.

`Dismiss Event` takes the displayed occurrence out of the menu bar, and `MenuBarSummary.event` filters it
out exactly as it filters a lapsed one — so the next event inside its own lead takes the space with
no second rule, and with nothing behind it the item falls back to the glyph or leaves under **Hide
when there are no upcoming events**. The set lives on `CalendarCoordinator` and lasts the launch:
a dismissal is a reaction to what is on screen now, not a preference worth persisting, and the ids
are pruned against the store so the set cannot grow. It is deliberately per occurrence rather than
per series — dismissing today's standup says nothing about tomorrow's.

## Settings

The Calendar pane reads top to bottom: the master switch (routed through the coordinator so the
consent gate cannot be bypassed), a row offering access whenever it is missing, the **Menu Bar**
section, and the **Calendars** list — a filter field over one checkbox per calendar.

The hidden-calendar set stores **exclusions**, so a calendar added after the setting was written
defaults to on. Holidays and Birthdays are what people switch off.

The menu-bar settings carry over in a backup normally, and so does `calendarSpan`: it sets how far
ahead is read rather than widening what can be reached. Only `calendarEnabled` stays out.

Because the span is a setting, the two sentences that name the days — the consent dialog and the
master switch's subtitle — interpolate `MeetingSpan.possessivePhrase` rather than spelling the days
out.

`CalendarMenuBarDisplay` and `MenuBarEvents` both put their default at `rawValue == 0`, so an unset
preference lands on `.disabled` and `.today` rather than fighting them. `MenuBarEvents` has no `Never`:
`.disabled` is the one switch that takes the item out of the menu bar, and a second one would only
disagree with it.

`CalendarStore.access` is a snapshot, refreshed on `start`, on every `reload` and after a request —
TCC announces nothing when a grant changes in Settings. `refreshAccess()` is why anything that acts on
`access` outside those three re-reads first: the enable path, so its guard cannot bounce off a stale
`.granted` and leave a dead button, and the Calendar pane on appear, so a grant made in Settings while
the feature was off is not reported as still missing.

The Permissions pane shows calendar access alongside Accessibility, and when TCC has no record it
offers the same consent path rather than only opening System Settings — the Calendars pane there
lists no app that has never asked, so a `notDetermined` state that could only be sent to Settings was
a dead end. Both entry points funnel through `CalendarCoordinator.setCalendarEnabled`, so Tinycast's
dialog still comes first. A denial is the one state that Settings alone can undo, and both panes send
it there.
