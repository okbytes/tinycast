# TODO

What this project is for, and what comes next. Ordered by payoff over effort. Items move to a
feature doc once they ship; nothing here is a promise about order.

## Where things stand

A personal launcher that began as a fork of abue-ammar/tinycast and now stands alone, stripped to
the features its owner uses: a Raycast replacement without AI, monetisation or Raycast
compatibility. `main` moves one commit per checkpoint. Every checkpoint passed the full definition of done in
[docs/testing.md](docs/testing.md): harnesses, warning-free Debug build, lint, purity grep, docs.

Known flakes under parallel load: `clipboard-text-test` (timing-based scheduler) and
`icon-cache-test` (icon rendering). Both pass in isolation.

Findings from the initial survey that still shape the plan:

- `AppCore` is an 850-line service locator and `RootPaletteView` a 1,300-line view; both are
  where new wiring lands, so touch them surgically.
- Persistence is mixed (SQLite, UserDefaults JSON, loose JSON, `.md` files) and most writes are
  `try?`, so failures are silent.

## Done

- Removed AI, MCP, Quick Actions, the Support window and reminder, the in-app updater, the website.
- Removed File Search, Raycast extensions and Menu Search.
- Removed the Raycast import (`.rayconfig` and script folders); `.tinycast` backups are the one import.
- Removed About: its Settings pane, the About command and both menu items.
- Removed Navigation, the window switcher.
- Removed Notes.
- Removed window Layouts, Rooms and Custom Sizes; window commands, cycling, gaps and presets stay.
- Trimmed window commands to Left/Right Half, the quarters, the three fourths, Maximize, Center and
  the four moves. Top/Bottom Half, thirds, the other sizing commands, Restore, display moves,
  Toggle Fullscreen and Space switching are gone.
- Trimmed Calendar to the menu-bar item: next event, the agenda on click, Open in Calendar. Joining,
  auto join, the camera preview, launcher rows, My Schedule, event details, Create Event and the
  calendar commands are gone.
- Removed launcher Fallbacks.
- Removed System Settings panes from the launcher; the System Settings app itself is still listed.
- Removed Quicklinks; bookmarks live in Apple Shortcuts.
- Removed Custom Commands; scripts run as Apple Shortcuts.
- Removed Snippets, with the text injection and template engine Quicklinks also used.
- Merged upstream through #1410 (`71279c8`), leaving out Dictation and the update-check toggle.
- Cherry-picked upstream through #1481 (`da2c4e4`): 14 of 24 taken; the rest were for removed
  features, plus #1451, whose posture rewrite would loosen latest-only.

## Calculator — fluidity

- Spoken operators: `plus`, `minus`, `times`, `x`, `divided by`, `over`, `squared`, `to the`.
- `ans` and `_` for the previous result; simple variables (`rent = 1800`, then `rent * 12`).
- Forgiving input: auto-close parens, ignore a dangling operator, accept `what is`, `=` and `?`.
- Later: a multi-line scratch mode on the history screen. Numbat and Qalculate are the grammars
  to crib from.

## Emoji — speed

- Precompute lowercased name and keyword tokens at load; cache more than one query.
- Recents as the first row, not a tie-breaker.
- Per-emoji skin-tone picker, and tone support for ZWJ sequences (only 133 single-scalar emoji
  take tones today).
- Persist the grid zoom.

## Clipboard

- Capture and paste back rich text (RTF/HTML), not just the plain string.
- Restore the previous clipboard after a paste-back; dedupe images by hash.
- A size cap alongside the age-based retention.
- Replace the fixed 80 ms sleep before the synthetic ⌘V with a wait on the target app activating.

## Hotkeys

- Surface a failed registration (another app owns the chord) instead of showing it as bound.
- Check against system shortcuts via `CopySymbolicHotKeys` before recording.

## Key remapping

Shipped in 0.12.0: Hyper and Meh through a root helper driving pqrs's virtual keyboard instead of
an event tap ([key-remap.md](docs/features/key-remap.md)). Hyper app-switch shortcuts are in daily use
on two Macs; the old event tap eventually went dead, so long uptime is the test that matters.

- Verified on hardware: Hyper reaching the system as ⌃⌥⇧⌘ (an ✦ binding fired), fn+arrows, the
  Input Monitoring grant picked up in two seconds, updates keeping the grant. Not yet: Meh, the top
  row's actions from the built-in map, a Globe tap, the Caps Lock light while seized, a Caps Lock Quick Press against the delay override, sleep and
  wake, no stuck modifier after `sudo killall TinycastKeyboardHelper` mid-chord, and typing latency
  measured rather than felt.
- Binding Caps Lock while it is latched no longer clears the latch.
- Try the helper in `Contents/MacOS` with no embedded Info.plist. The spike, built that way, was
  credited to the app's Accessibility grant and needed no Input Monitoring entry of its own; the
  embedded plist exists only to set the signing identifier, which `--identifier` can do instead.
- The driver protocol is pinned to 7 (driver v8.x); a driver update can break remapping.
- More than Hyper and Meh: per-key chords, tap-versus-hold roles, external keyboards.
- `HyperKeyPhysicalKey` now names the Meh key's choice too; rename it to say so.

## Window management — the hidden Dock

With the Dock auto-hidden, windows in any app (Helium, Chrome, Zed, Claude) sometimes come back with
their bottom edge pulled up by the Dock's height: after un-minimizing from the Dock or a Tinycast app
hotkey, or on clicking back to the app. Seen on both Macs under macOS 27.0.1.

Caught live on 2026-10-19: with auto-hide on and no Dock window on screen, `NSScreen.visibleFrame`
on the 1920×1080 display read `(0, 67, 1920×983)`, and the Claude window ended at y 1013, exactly
1080 − 67. A fresh read about a minute later was back to `(0, 0, 1920×1050)`. So macOS briefly
reserves a hidden Dock's space, and any app that fits itself to the usable area during that time
stays shrunk afterwards. Rectangle's `DockUtil` works around the same stale `visibleFrame`
(rxhanson/Rectangle#467).

- Done: tiles ignore the Dock (`40cad3fd`), and `DockShrinkGuard` puts back a window Tinycast tiled
  if an app later shortens it (`2b1d4c28`, v0.15.0). Windows sized by hand are not covered.
- Ruled out: Tinycast itself (nothing moves windows between commands since v0.12.0); a plain AppKit
  window un-minimized directly or through the reopen route, intact on both Macs; Helium's own
  restore, intact here; third-party window tools, none running at work; revealing the Dock and
  pulling away mid-animation; about 40 Helium ↔ Claude switches. A monitor ran for about 40 minutes
  of normal use without catching another episode.
- Unknown: what starts an episode, how long one lasts, and whether `didChangeScreenParameters` fires
  at its start and end.
- Next: catch an episode with a long-running monitor that logs each screen's `visibleFrame`, the Dock's
  on-screen windows, the frontmost app, the pointer at the bottom edge, and windows whose bottom edge
  rises off a screen's bottom with no mouse button held. With the trigger known, a repair pass:
  note window frames when the reservation appears, then put back any window whose bottom edge was
  pulled up to it once it clears. File it with Apple too.

## Cross-cutting

- Replace the Raycast backend for currency rates with an open source such as frankfurter.app, or
  make rates opt-in. It is the last unconditional network call at launch.
