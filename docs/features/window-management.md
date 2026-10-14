# Window Management

Rectangle-style window actions — halves, quarters, three fourths, Maximize, Center and edge moves —
searchable in the palette and bindable to global shortcuts. 15 commands, no new dependencies and no
new permission: they reuse the Accessibility grant clipboard paste already needs.

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
| `Model/WindowCommand.swift`          | Foundation                   | Catalog: id, name, symbol, group, `cyclesOnRepeat`, `resizes`       |
| `Model/WindowCycle.swift`            | Foundation                   | The three cycling modes a repeat press can run                      |
| `Model/WindowPlacementEngine.swift`  | Foundation + CoreGraphics    | **Pure.** Every frame the commands produce                          |
| `Model/WindowActionMemory.swift`     | Foundation + CoreGraphics    | **Pure.** Per-window cycle position                                 |
| `Service/AXWindowAccess.swift`       | AppKit + ApplicationServices | `@MainActor`. Every `AXUIElement` call, and the one write sequence  |
| `Service/AXScreens.swift`            | AppKit                       | `@MainActor`. `AXGeometry`, the one coordinate flip                 |
| `Service/WindowMover.swift`          | AppKit + ApplicationServices | `@MainActor`. Command policy: resolve, cycle, write                 |
| `Service/DockShrinkGuard.swift`      | AppKit + ApplicationServices | `@MainActor`. Undoes a later Dock-height shrink of a bottom tile    |
| `Service/WindowTarget.swift`         | AppKit                       | `@MainActor`. Which window a command acts on                        |
| `UI/WindowCommandCoordinator.swift`  | AppKit                       | The one funnel from a palette row or a global hotkey                |
| `Model/WindowShortcutPreset.swift`   | Foundation + Carbon          | **Pure.** Rectangle / Magnet and Spectacle tables, and the apply plan |
| `UI/WindowShortcutPresetCoordinator.swift` | Foundation             | Applies a preset, confirming first when it replaces a user's key   |

The first four compile into `Tests/window-command-test.swift`, so none of them may gain an AppKit,
SwiftUI or `NSScreen` dependency, and all must stay pure — `WindowActionMemory` takes `now` as a parameter rather than
reading a clock. CoreGraphics is needed only because `CGRect`'s `Equatable` conformance lives in that
overlay rather than in Foundation.

Adding a command is four edits in `WindowCommand.swift` (a case in `ID`, plus `name`, `symbol` and
`group` arms), an arm in `WindowPlacementEngine.placement` or `tileFractions`, and bumping
`commands.count == 15` and its group count in the harness. A command opening a new family also needs
a `Group` case and its `title` arm; `ID.allCases` stays in group order.

## Coordinate space

**`WindowPlacementEngine` works exclusively in AX space**: global coordinates, top-left origin, +Y pointing
_down_. `AXScreens.AXGeometry` is the only place that converts to and from Cocoa's bottom-left space.
The visible consequence is that Top Left Quarter has `minY == usableFrame.minY`, which the harness asserts
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

**Tiles** come from fractional bounds of `usableFrame`. Gaps use one rule that composes across every
family: an edge sitting on the screen boundary takes the full gap, an interior edge takes half. Two
adjacent tiles therefore leave exactly `gap` between them and every screen edge is inset by `gap`, with
no per-family special cases. Rects are rounded on their four **edges**, not origin + size, so two tiles
sharing a fractional boundary (480.333 for thirds of 1441) round it identically — no overlaps, no
one-point seams.

**Free-floating commands** (Maximize, Center and the four moves) work in
`canvas = usableFrame.insetBy(gap)` instead: a centred window has no neighbour to gutter against.

**Move Left / Right / Up / Down** push the window flush against that edge of the canvas, keeping its
size and its position on the other axis — a vertically centred window moved left stays vertically
centred, a top-aligned one stays top-aligned. A second press is a no-op, and neither the size nor the
display ever changes.

**Center** centres horizontally only: the window keeps its size and its vertical position, clamped
back onto the display if it hangs off it.

**Center Three Fourths** is three quarters of the width at full height, horizontally centred, so it
shares the quarter grid with First and Last Three Fourths.

An oversized or off-screen window is always clamped back onto the display; `clamped` pins the leading
edge rather than shoving the window off the far side.

## Cycling

Cycling reduces to one question — _has the user moved this window themselves since our last
action?_ — so `WindowActionMemory` answers it once. It is generic over the key so it stays Foundation-only: the app
keys by `AXUIElement` (via `CFEqual`/`CFHash` plus the pid), the harness keys by `Int`.

`decide` is a pure query returning the cycle step, which is then fed into `WindowPlacementEngine.Input.step` —
cycle state is never hidden inside the geometry. Its rules, in order:

1. No record → step 0.
2. The frame drifted from `appliedFrame` by more than 2 pt → step 0.
3. A different command, a different display, a `cycleLength` of 1, or a lapsed `cycleTimeout` → step 0.
4. Otherwise → `(step + 1) % cycleLength`.

`cycleLength` comes from `WindowPlacementEngine.cycleLength(for:screens:cycle:)`, so the memory holds
no opinion about what a step means: 1 covers cycling switched off *and* a command that never cycles,
which is why `WindowActionMemory` no longer reads the catalog at all.

**Rule 2 compares against the frame we observed, never the one we asked for.** Terminal resizes in
whole character cells and never lands exactly on target; comparing against the target would read as
"the user moved it" on every press and break cycling for such apps.

**Cycling covers Left and Right Half only**, and `WindowCycle` picks one of three modes,
`.off` by default so a repeat press stays idempotent unless asked otherwise:

- **`.sizes`** — ½ → ⅓ → ⅔ in place, hugging the half's own edge. The thirds have no commands of
  their own, so they are expressed as fractions.
- **`.displays`** — every display contributes two half-slots to one strip, ordered left-to-right by
  `ordered(_:)`. Left walks it backwards and Right forwards, both wrapping, so one
  shortcut sweeps the whole desktop in one direction: on two displays, Left Half gives
  D1-left → D2-right → D2-left → D1-right. The walk counts from the display the chain started on,
  which `decide` carries as `originScreenID`: from the second press the window already sits on the
  display it was moved to, and counting from there would overshoot a slot. One display makes the
  mode a quiet no-op — a length of 1 — rather than a left/right flip in place.

The two are deliberately exclusive rather than composable: a 12-press chain over two displays is not a
shortcut any more, and Raycast's own setting is the same single choice. `Half` names the edge a slot
hugs, which makes both modes one expression: the same edge decides which side a ⅓ hugs.

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

`WindowMover.perform(_:target:gap:cycle:)` is the only entry point. `target` is **explicit**
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

The frame is read back **once** afterwards, for three reasons: to detect an app-imposed minimum size
(AX exposes no attribute for it, so the read-back is the only way to learn it), to record a truthful
`appliedFrame`, and to report whether anything actually changed. When the app refused to shrink, the
window is re-placed per the placement's `anchor` so a left half stays left-aligned instead of drifting
centre. **One correction, no loop** — iterating against an app that fights back just makes the window
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
the window. The trigger is unconfirmed; the likeliest is a `visibleFrame` that briefly reports the Dock
around a display or Dock change. Tinycast cannot stop the re-fit, only undo it.

`DockShrinkGuard` does that. After a command whose placement reaches the bottom of the canvas, the
mover hands it the observed frame and the window, and it registers an `AXObserver` for resized, moved
and destroyed. `WindowPlacementEngine.heldFrameChange` classifies every change against the held frame:

- **Unchanged**, within `clampTolerance`: nothing to do. Our own restore lands here.
- **Dock shrink**: top-left and width kept, only the bottom edge raised, by at most `dockReserveLimit`.
  After a 500 ms settle, so the restore lands after the app's last re-fit, the held frame is written
  back through `AXWindowAccess.write`.
- **Anything else**, a mouse button held during the change, or the window closing: the window is
  the user's again and the guard lets go.

**Two restores in ten seconds is the limit.** An app that re-applies the shrink a third time wins, for
the same reason the write does no correction loop: fighting it only makes the window jitter. Every
restore and every give-up is logged under the `window-management` category.

The mover releases a window before every write, so the size → position → size sequence never reads as
a shrink, and the guard drops a quit app's windows with the cycle memory. It holds at most 16 windows,
oldest dropped first. Only external windows are held; our own go through AppKit and are left alone.
Only a bottom Dock is covered: a side Dock shrinks the width, which reads as any other change.

## Shortcut presets

Settings › Window Management › Options › **Shortcut preset**, a pop-up and an Apply button, fills
in the stock window shortcuts of Rectangle / Magnet (one option: Rectangle adopted Magnet's scheme
and only added to it) or Spectacle.
It is a one-shot action rather than a mode, so nothing is persisted, there is no `SettingsFileKey`,
and every shortcut stays editable afterwards.

- **Fill in, never replace wholesale.** A command the preset doesn't name keeps its binding, unless it
  holds a key the preset gives to another command — then it is *displaced* and cleared.
- **Confirm only over the user's own keys.** `WindowShortcutPresetPlan` lists every command whose
  existing binding would change or be displaced; when that list is empty the preset applies at once,
  otherwise `WindowShortcutPresetCoordinator` asks through `AppCore.confirm` first.
- **Never take a key from outside the feature.** A preset key already held by any other action (the
  palette toggle, an app hotkey, …) is skipped, the command keeps its previous binding when that is
  still free, and the closing HUD counts the skips.
- **Key codes, not letters.** Each table stores Carbon key codes, as the original apps register them,
  so ⌃⌥U lands on the same physical key under Dvorak or AZERTY. Actions with no Tinycast equivalent
  are left out.
- **Choose, then Apply.** The pop-up holds a choice that is never stored, and Apply stays disabled
  until one is made — and while `WindowShortcutPreset.matching` reports the chosen preset as fully
  set (other commands don't count), so one edited or cleared key re-enables it.
- **No Raycast preset.** Raycast ships its window commands unbound, so there is nothing to fill in.

## Wiring

- **`AppEntry.Kind.windowCommand`** — entries are `window-command:<id>`, published by
  `AppIndex.setWindowCommandsVisible(_:)` between the system-action and built-in command slices.
  `LauncherView.rows` mirrors that position with a "Window Management" section; the slice order is the
  flat-selection invariant, so the two must move together.
- **`HotKeyAction.windowCommand(id:)`** — persisted under
  `hotkey.windowCommand.<raw-id>`, matching the shared `HotKeyAction.defaultsKey` convention. Unlike
  Apple Shortcuts there is no bound-ID index to maintain: the catalog is fixed, so `HotKeyManager.start`
  and `conflictOwner` iterate `WindowCommand.ID.allCases` and `register` no-ops on an unbound command.
- **`WindowCommandCoordinator.runWindowCommand(id:)`** is the one funnel for both palette activation and the global
  hotkey, so the feature switch cannot be bypassed by either.
- **Settings** — `windowManagementEnabled` (off), `windowManagementShowInLauncher` (on), `windowGap`
  (0) and `windowCycle` (`.off`). All four ride in settings backups: they grant no
  permission class of their own.
- **Per-command visibility** reuses `VisibilityStore` as-is; clearing a recorded shortcut is how a
  hotkey is disabled, so there is no separate per-command enabled flag. Each command
  row carries an alias field, dimmed while its entry is hidden from the launcher. Window commands
  deliberately get **no** launcher-category pane of their own — they are managed inside Settings ›
  Window Management.

## Testing

`Tests/window-command-test.swift` (279 assertions) covers the catalog, the AX-space convention lock,
tiling on divisible and non-divisible screens, off-origin and negative-coordinate displays, gap
arithmetic including degenerate values, sizing, edge moves, screen ordering and overlap, both cycling
modes including the strip walk, its wrap and a run of real presses across displays, every
`WindowActionMemory` rule, and a fuzz sweep over every command × gap × screen × cycle × step ×
degenerate window frame checking for non-finite output, negative dimensions, off-screen results,
non-determinism and, at step 0, drift on repeat.

`Tests/window-preset-test.swift` covers the preset tables (no key used twice, a commanding modifier
on each) and `WindowShortcutPresetPlan`: a fresh apply, a repeat apply, a replaced user key, a
displaced command and an unrelated one left alone, plus when `matching` names a preset.

Everything runs headless because the layer is pure. `WindowMover` is not compiled into either harness
and has no automated coverage — the AX path needs manual verification, particularly:

1. A non-resizable window (System Information) must fail silently, left untouched rather than
   half-moved.
2. **A mixed-resolution multi-monitor setup** — the coordinate-flip bug appears nowhere else. Tile on
   the secondary display, and walk Left Half across both displays under `.displays`.
3. Cycling, in both modes: under `.sizes`, three presses of Left Half, then drag the window and confirm
   the next press restarts at ½. Under `.displays` on two monitors, four presses of Left Half must
   visit every half-slot once and return to the first.
4. The Dock guard, with the Dock auto-hidden: tile a window to Left Half, then sleep and wake the
   displays or plug one in. The window must end up full height again, and
   `log stream --predicate 'category == "window-management"'` shows a restore if anything shrank it.
   Dragging its bottom edge up afterwards must stick.
