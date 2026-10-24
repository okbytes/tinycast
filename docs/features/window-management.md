# Window Management

Rectangle-style window actions — Half, Quarter, Maximize, Center and edge moves — searchable in the
palette and bindable to global shortcuts. 8 commands, no new dependencies and no new permission: they
reuse the Accessibility grant clipboard paste already needs.

Ships **off**. Settings › Window Management is the switch, and while it is off there are no launcher
entries and a still-registered shortcut moves nothing.

## Invariants

- **`WindowPlacementEngine` works exclusively in AX space**, and `AXScreens.AXGeometry` is the only place that
  converts — anchored on the **primary** display, never the window's own screen. See
  [Coordinate space](#coordinate-space); getting this wrong is invisible on one monitor and wrong on
  every mixed-size setup.
- **Nothing in this feature touches `backingScaleFactor`.** All three of `NSScreen.frame`, `visibleFrame`
  and AX coordinates are in points, so mixed-DPI correctness is automatic.
- **`WindowCommand.swift`, `WindowPlacementEngine.swift` and `WindowActionMemory.swift` stay
  Foundation + CoreGraphics and pure** — no AX, no `NSScreen`, no clock (`WindowActionMemory` takes
  `now` as a parameter). Every `AXUIElement` call and the Cocoa↔AX flip live in `Service/`.
- **`AXWindowAccess` is the one AX layer.** Its `write` is the size → position → size sequence: a
  second copy of it would land a stubborn app two ways.
- **Our own windows are written through AppKit, never AX.** `WindowMover.Surface` is the split:
  an `AXUIElement` write into our own process would stall the main thread that services it.

## Layout

| File                                             | Imports                      | Role                                                                |
| ------------------------------------------------ | ---------------------------- | ------------------------------------------------------------------- |
| `Model/WindowCommand.swift`          | Foundation                   | Catalog: id, name, symbol, group, `resizes`, `cycleLength(for:)`; Half's sides and Quarter's corners |
| `Model/WindowPlacementEngine.swift`  | Foundation + CoreGraphics    | **Pure.** Every frame the commands produce                          |
| `Model/WindowActionMemory.swift`     | Foundation + CoreGraphics    | **Pure.** Per-window cycle position                                 |
| `Service/AXWindowAccess.swift`       | AppKit + ApplicationServices | `@MainActor`. Every `AXUIElement` call, and the one write sequence  |
| `Service/AXScreens.swift`            | AppKit                       | `@MainActor`. `AXGeometry`, the one coordinate flip                 |
| `Service/WindowMover.swift`          | AppKit + ApplicationServices | `@MainActor`. Command policy: resolve, cycle, write                 |
| `Service/DockShrinkGuard.swift`      | AppKit + ApplicationServices | `@MainActor`. Undoes a Dock-height shrink, held or seen, once the reservation clears |
| `Service/DockReservationMonitor.swift` | AppKit                     | `@MainActor`. Logs the Dock's reservation, windows and app switches |
| `Service/DockLogExport.swift`        | AppKit                       | Writes the last days of that log to a file the user picks           |
| `Service/WindowTarget.swift`         | AppKit                       | `@MainActor`. Which window a command acts on                        |
| `UI/WindowCommandCoordinator.swift`  | AppKit                       | The one funnel from a palette row or a global hotkey                |

The first three compile into `Tests/window-command-test.swift`, so none of them may gain an AppKit,
SwiftUI or `NSScreen` dependency, and all must stay pure — `WindowActionMemory` takes `now` as a parameter rather than
reading a clock. CoreGraphics is needed only because `CGRect`'s `Equatable` conformance lives in that
overlay rather than in Foundation.

Adding a command is five edits in `WindowCommand.swift` (a case in `ID`, plus `name`, `symbol`,
`group` and `cycleLength(for:)` arms), arms in `WindowPlacementEngine.placement` and `firstStep`, and
bumping `commands.count == 8` and its group count in the harness. Every one of those switches is
exhaustive, so the compiler lists them. A command with a setting of its own also needs an arm in
`WindowManagementSettingsView.preference(for:)`, whose `default` will not flag a missing one. A
command opening a new family needs a `Group` case, a `SettingsAnchor` for its section, an arm in
the view's `header(for:)` and a search entry; `ID.allCases` stays in group order.

## Coordinate space

**`WindowPlacementEngine` works exclusively in AX space**: global coordinates, top-left origin, +Y pointing
_down_. `AXScreens.AXGeometry` is the only place that converts to and from Cocoa's bottom-left space.
The visible consequence is that a top-left Quarter has `minY == usableFrame.minY`, which the harness asserts
specifically to stop a bottom-left convention creeping back in.

The flip is anchored on the **primary** display's height — the display whose Cocoa frame origin is
`(0, 0)` — never on the window's own screen. Both global spaces are anchored on the primary; flipping
through the window's own screen height shears every rect on a differently-sized display by the height
difference. That bug is invisible on a single monitor and wrong on every mixed-size multi-monitor
setup, so it is worth stating twice.

`AXGeometry` is snapshotted once per command: `NSScreen.screens` can change between calls on hotplug,
wake or a resolution change, and mixing two anchors inside one command corrupts the result.

Nothing here touches `backingScaleFactor`. `NSScreen.frame`, `NSScreen.visibleFrame` and AX
coordinates are all in points, so mixed-DPI correctness is automatic; a scale factor appearing anywhere
in this feature is a bug.

**The Dock is ignored.** Each display's `usableFrame` is its full frame minus only the menu bar (and
the notch inside it): `AXScreens` keeps `visibleFrame`'s top edge, which the Dock never occupies, and
takes the other three from `frame`. With the Dock auto-hidden, tiles occasionally came up a Dock's
height short; a Dock that stays shown is simply covered. Avoiding it again would be a new feature,
not a fix. Ignoring it when placing is only half of it: macOS or the app can still shorten the window
later, which [Holding a tile over the Dock](#holding-a-tile-over-the-dock) undoes.

## Geometry

**Tiles** — Half, Quarter and Center — come from fractional bounds of `usableFrame`, with no gap
between windows. Rects are rounded on their four **edges**, not origin + size, so two tiles sharing a
fractional boundary (720.5 for halves of 1441) round it identically — no overlaps, no one-point seams.

**Free-floating commands** (Maximize and the four moves) work in `canvas`, the rounded `usableFrame`.

**Move Left / Right / Up / Down** push the window flush against that edge of the canvas, keeping its
size and its position on the other axis — a vertically centred window moved left stays vertically
centred, a top-aligned one stays top-aligned. A second press is a no-op, and neither the size nor the
display ever changes.

**Center** is a share of the display's width at its full height, horizontally centred. The share is
**Center width** in Settings, 75% unless changed, between 20% and 100%, and 100% is a Maximize.
settings.json and a backup refuse a width outside that range and keep the current one;
`clampedCenterWidth` catches anything else, such as a raw `defaults write`. A window that can't take
the size, or an app that caps its width, is centred on both axes rather than left on the slot's edge.

An oversized or off-screen window is always clamped back onto the display; `clamped` pins the leading
edge rather than shoving the window off the far side.

## Cycling

**Half and Quarter cycle; nothing else does.** `WindowCommandCatalog.cycleLength(for:)` is the whole
rule: 2 for Half, 4 for Quarter, 1 for the rest. A step is an index into the command's own order,
`HalfSide.cycle` (left, right) or `QuarterCorner.cycle` (top left, top right, bottom right, bottom
left, so each step moves to a neighbouring corner rather than across the diagonal). Both commands
resolve through that one order, so a new side or corner joins the cycle by joining the array.

**Settings names where a chain starts, never where it goes next.** A press that starts a new chain
lands on `WindowPlacementEngine.firstStep` — **Half starts on** (Left unless changed) or **Quarter
starts at** (Top Left unless changed). A press that continues one takes the slot after the one the
window is in, which `WindowActionMemory` records as an index. Changing the starting position between
two presses therefore never reinterprets a chain under way: the window keeps moving from where it
is. The two choices travel with Center's width as `WindowPlacementEngine.Preferences`, and
`Preferences.standard` is the one place their defaults are written.

A press continues a chain only when the user hasn't moved the window since our last action, so
`WindowActionMemory` answers that once. It is generic over the key so it stays Foundation-only: the
app keys by `AXUIElement` (via `CFEqual`/`CFHash` plus the pid), the harness keys by `Int`.

`decide` is a pure query returning the next slot, or nil when the press starts a new chain — cycle
state is never hidden inside the geometry. Its rules, in order:

1. No record → nil.
2. The frame drifted from `appliedFrame` by more than 2 pt → nil.
3. A different command, a different display, a `cycleLength` of 1, or a lapsed `cycleTimeout` → nil.
4. Otherwise → `(step + 1) % cycleLength`.

**Rule 2 compares against the frame we observed, never the one we asked for.** Terminal resizes in
whole character cells and never lands exactly on target; comparing against the target would read as
"the user moved it" on every press and break cycling for such apps.

**A press that changes nothing moves on a slot.** With no chain to continue — a window tiled before
Tinycast started, or one evicted from the memory — a Half pressed on a window already at the left
half would otherwise re-apply the left half. `WindowMover.place` compares where the window *landed*
with where it was: when a new chain's first write moved it by no more than 2 pt, it writes the next
slot, once. Comparing the landing rather than the slot is what keeps the rule working for a window
that never takes a slot exactly, such as Terminal or a width-capped app.

Growth is bounded three ways: an LRU cap of 64, an `NSWorkspace.didTerminateApplicationNotification`
observer (the house `NotificationToken` RAII idiom) dropping a quit app's keys, and lazy invalidation
when a read fails. Nothing is persisted.

## Choosing a target

Our panels are `.nonactivatingPanel`, so opening one never makes Tinycast frontmost and
`NSWorkspace.frontmostApplication` keeps naming the app *behind* it rather than the window the user
is looking at. `WindowTarget` is the answer to "what does this command act on": it prefers a key
window of ours, falling back to the frontmost app only when there is none.

`canBecomeMain` is the filter, and it needed no new flag — every transient panel in the app already
declines it, which leaves exactly the `AppWindowController` windows. When a key child window is in
front, `WindowTarget` looks one level up through `parent`, so the command places the window it
belongs to.

`PalettePanel` is the one main-capable panel of ours and would pass the filter. It never reaches
here, because `WindowCommandCoordinator.handOffTarget()` branches on `paletteCoordinator.isVisible`
first and a hidden palette cannot be key. **That ordering is the invariant; do not reorder those two
branches.** The palette branch reads `previousOwnWindow`, which `PaletteWindowController` records
from whatever held key at summon time regardless of which app was frontmost — for the same reason
this section exists.

## Applying a placement

`WindowMover.perform(_:target:preferences:)` is the only entry point. `target` is **explicit**
because the palette is frontmost when a command dispatches from it — `WindowCommandCoordinator` passes
a `WindowTarget`, which is either an external app or one of our own windows (see
[Choosing a target](#choosing-a-target)), and restores focus to it rather than dropping it. The own
case skips AX and the Accessibility prompt entirely: placing our own window needs no grant. It is
synchronous: every AX call is a bounded mach round trip capped by a 1s
messaging timeout, and `await` would only add reentrancy between a held hotkey's repeats. The timeout
is set on the application element _and again_ on the window element — it is per-element and never
inherited.

The write sequence is **size → position → size**. Whichever single order you pick is wrong in one
direction: growing first fails when the source display is smaller than the target size, shrinking first
leaves the window shrunken after a cross-display move. Writing the size on both sides of the position
write costs one extra round trip and makes both directions correct with no branching; one of the two is
always a no-op.

**Failing quietly** is a requirement, not a nicety, and has three distinct paths:

- Position not settable → return with **zero** writes; the window is untouched.
- Size not settable → the move-only branch: one position write placing the size it already has inside
  the slot per the placement's anchor. One coherent move, never a half-applied one.
- The position write fails after the shrink → roll the size back. Net visible effect: nothing.

The frame is read back **once** afterwards, for three reasons: to detect a size the app overrode
(AX exposes no attribute for its limits, so the read-back is the only way to learn them), to record a
truthful `appliedFrame`, and to report whether anything actually changed. When the app refused the
width — wider for a minimum, narrower for a cap or a cell grid — or raised the height, the window is
re-placed per the placement's `anchor`, so a left half stays left-aligned, a right half stays flush
right and Center stays centred. A short height is left alone: that is the Dock reservation's clamp,
which [Holding a tile over the Dock](#holding-a-tile-over-the-dock) handles. **One correction, no loop** — iterating against an app that fights back just makes the window
visibly jitter.

Windows that are minimized, not `AXWindow`-roled (sheets, popovers), already natively fullscreen, or
that report no position or size are rejected before any work happens.

`AXEnhancedUserInterface` is cleared for the duration of the writes and restored immediately, because
some apps reinterpret frame writes while it is on — but never while VoiceOver is running, which would
break the screen reader. **This mitigation is inherited convention and unverified on macOS 27**; if a
stock Electron app tiles correctly without it, delete the helper rather than keep it.

## Holding a tile over the Dock

Placing over the Dock was not enough on its own. With the Dock auto-hidden, a window Tinycast tiled to
the bottom of the screen could still, later and with no command pressed, have its bottom edge pulled up
by the Dock's height. Tinycast writes nothing between commands, so that is macOS or the app re-fitting
the window. macOS 27 reports a hidden Dock's space in `visibleFrame` for a while — an *episode*, which
[Recording Dock episodes](#recording-dock-episodes) documents — and while it does, AppKit clamps every
drag and every AX write to that line, so nothing can grow a window past it. Tinycast cannot stop the
re-fit, only undo it once the reservation clears.

`DockShrinkGuard` does that, in two halves.

**Held windows.** After a command whose placement reaches the bottom of the canvas, the mover hands it
the observed frame and the window — or the *asked* frame, when a reservation stood and the landing was
a Dock shrink of it, since the observed one is the clamp — and it registers an `AXObserver` for
resized, moved and destroyed. `WindowPlacementEngine.heldFrameChange` classifies every change against
the held frame:

- **Unchanged**, within `clampTolerance`: nothing to do. Our own restore lands here.
- **Dock shrink**: top-left and width kept, only the bottom edge raised, by at most `dockReserveLimit`.
  With no reservation standing, after a 500 ms settle so the restore lands after the app's last
  re-fit, the held frame is written back through `AXWindowAccess.write`. With one standing the write
  would only be clamped again, so the watch waits for the episode's end.
- **Anything else**, a mouse button held during the change, or the window closing: the window is
  the user's again and the guard lets go.

**Two restores in ten seconds is the limit.** An app that re-applies the shrink a third time wins, for
the same reason the write does no correction loop: fighting it only makes the window jitter. Every
restore and every give-up is logged under `window-management`.

**Episodes.** The guard also watches `didChangeScreenParameters` and reads
`AXScreens.dockReservationStands`, true while any display holds space on a Dock edge. When that turns
true it notes every other app's on-screen layer-0 window from `CGWindowListCopyWindowInfo`, and
polls them every 2 s while it lasts: apps re-fit lazily, often only when activated, so the whole episode
is watched rather than its first moment. A window whose change against that note reads as a Dock
shrink, with no mouse button held, is remembered with both frames. When the reservation clears, after
the same settle, every held window is restored as above and every remembered one is put back: its AX
window is found by the frame it was seen at, since frames are the only key a window number and an
`AXUIElement` share, and written its earlier frame with a top-leading anchor. A remembered window that
has since moved or closed is simply not found and left alone. Each put-back is logged.

The mover releases a window before every write, so the size → position → size sequence never reads as
a shrink, and the guard drops a quit app's windows with the cycle memory. It holds at most 16 windows,
oldest dropped first. Only external windows are held; our own go through AppKit and are left alone.
Only a bottom Dock is covered: a side Dock shrinks the width, which reads as any other change.

## Recording Dock episodes

Nothing so far says what starts an episode, and an episode on the work Mac leaves no trace this
checkout can read, so Tinycast keeps its own record. `DockReservationMonitor`, started from
`AppCore.start()` whether or not window management is on, writes one line per event to the unified
log under `com.tinycast.app` / `dock-watch`:

- `screens notified` on every `didChangeScreenParameters`, and `screens changed silently` when a
  2 s poll finds `NSScreen.screens` changed without one: each display's frame, `visibleFrame`, and
  its menu-bar, bottom, left and right insets, then the Dock's on-screen windows and the mouse.
- `episode began` / `episode ended` when a Dock-side inset appears on a display or clears, with the
  reservation in points and how long it stood.
- `dock` when the Dock's own windows change, which is how a reveal or a hide reads.
- `shrink` / `grow` when an on-screen window's bottom edge moves with its top-left and width kept,
  from `CGWindowListCopyWindowInfo` on the same poll, with the owning app and the mouse buttons.
- `activated`, `launched`, `quit`, `space changed`, `screens slept` / `woke`, `system woke`, and
  the session resigning or becoming active.

`WindowMover` adds `landed N pt short` under `window-management` when a resizing command lands
short of its height, and `DockShrinkGuard`'s restores and give-ups are under the same category.
Everything is logged at notice with public interpolation, so `log show` keeps it and shows it.

Settings › Window Management › Options › **Dock log › Save…** runs `log show` over the last
`DockLogExport.days` days for both categories, prefixes the build, macOS version, Dock settings and
the screens as they are now, writes the file where the save panel points, and reveals it. Attach
that file when reporting an episode; the same lines stream live with
`log stream --predicate 'category == "dock-watch"'`.

The monitor reports and decides nothing; the repair is `DockShrinkGuard`'s, in
[Holding a tile over the Dock](#holding-a-tile-over-the-dock).

## Wiring

- **`AppEntry.Kind.windowCommand`** — entries are `window-command:<id>`, published by
  `AppIndex.setWindowCommandsVisible(_:)` between the system-action and built-in command slices.
  `LauncherView.rows` mirrors that position with a "Window Management" section; the slice order is the
  flat-selection invariant, so the two must move together.
- **`HotKeyAction.windowCommand(id:)`** — persisted under
  `hotkey.windowCommand.<raw-id>`, matching the shared `HotKeyAction.defaultsKey` convention. Unlike
  folder commands there is no bound-ID index to maintain: the catalog is fixed, so `HotKeyManager.start`
  and `conflictOwner` iterate `WindowCommand.ID.allCases` and `register` no-ops on an unbound command.
- **`WindowCommandCoordinator.runWindowCommand(id:)`** is the one funnel for both palette activation and the global
  hotkey, so the feature switch cannot be bypassed by either.
- **Settings** — `windowManagementEnabled` (off), `windowManagementShowInLauncher` (on),
  `windowHalfStart` (`.left`), `windowQuarterStart` (`.topLeft`) and `windowCenterWidth` (75). All
  five ride in settings backups: they grant no permission class of their own. Each of the last three
  sits in Settings › Window Management directly under the command it tunes.
- **Per-command visibility** reuses `VisibilityStore` as-is; clearing a recorded shortcut is how a
  hotkey is disabled, so there is no separate per-command enabled flag. Each command
  row carries an alias field, dimmed while its entry is hidden from the launcher. Window commands
  deliberately get **no** launcher-category pane of their own — they are managed inside Settings ›
  Window Management.

## Testing

`Tests/window-command-test.swift` (183 assertions) covers the catalog, the AX-space convention lock,
tiling on divisible and non-divisible screens, off-origin and negative-coordinate displays, Center's
width and its clamp, edge moves, screen overlap, Half and Quarter cycling from every starting slot —
pressed the way `WindowMover` presses them, including the step past a no-op for a window that lands
inexactly and a starting position changed mid-chain — every
`WindowActionMemory` rule, and a fuzz sweep over every command × screen × preferences × step ×
degenerate window frame checking for non-finite output, negative dimensions, off-screen results,
non-determinism and drift on repeat.

Everything runs headless because the layer is pure. `WindowMover` is not compiled into the harness
and has no automated coverage — the AX path needs manual verification, particularly:

1. A non-resizable window (System Information) must fail silently, left untouched rather than
   half-moved.
2. **A mixed-resolution multi-monitor setup** — the coordinate-flip bug appears nowhere else. Tile on
   the secondary display with Half and Quarter.
3. Cycling: Half twice lands left then right; Quarter four times visits every corner clockwise. Drag
   the window, and the next press starts over on the starting slot.
4. The Dock guard, with the Dock auto-hidden: tile a window to the left Half, then sleep and wake the
   displays or plug one in. The window must end up full height again, and
   `log stream --predicate 'category == "window-management"'` shows a restore if anything shrank it.
   Dragging its bottom edge up afterwards must stick.
5. The Dock record: `log stream --predicate 'category == "dock-watch"'` shows `activated` lines as
   you switch apps, and Settings › Window Management › Dock log › Save… writes a file that opens
   with the build and the screens and ends with those lines.
