# Roadmap

What this fork is for, and what comes next. Ordered by payoff over effort. Items move to a
feature doc once they ship; nothing here is a promise about order.

## Done

- Removed AI, MCP, Quick Actions, the Support window and reminder, the in-app updater, the website.
- Removed File Search, Raycast extensions and Menu Search.

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

## Notes — a global capture surface

Used to capture details mid-meeting or mid-interview with a video call and other windows up, so the
window must never fight the call for focus. The TextKit editor stays; the panel and coordinator
change.

- One hotkey that summons and dismisses from anywhere without stealing focus from the call.
- Stays above the meeting window, follows Spaces, optional hide-on-focus-loss.
- Zero friction to start typing into a fresh or recent note; auto-height until resized; remembered
  position.
- A quick note list beyond the ⌘P switcher; external-edit detection so another editor is never
  clobbered.
- Reference implementation: Pane (ColeMei/pane).

## Clipboard

- Capture and paste back rich text (RTF/HTML), not just the plain string.
- Restore the previous clipboard after a paste-back; dedupe images by hash.
- A size cap alongside the age-based retention.
- Replace the fixed 80 ms sleep before the synthetic ⌘V with a wait on the target app activating.

## Hotkeys

- Surface a failed registration (another app owns the chord) instead of showing it as bound.
- Check against system shortcuts via `CopySymbolicHotKeys` before recording.
- The Hyper key's Caps Lock remap must preserve other `hidutil` mappings and self-heal after a crash.

## Window management

- Multi-level undo; action memory that survives a relaunch.
- Re-apply layouts when displays change.
- Window switcher thumbnails.
- Decide whether the synthesized trackpad-swipe Space switching stays or the Space commands go.

## Cross-cutting

- Replace the Raycast backend for currency rates with an open source such as frankfurter.app, or
  make rates opt-in. It is the last unconditional network call at launch.
- Review the Raycast settings import in Backup: a one-time migration path that may no longer earn
  its keep.
