# TODO

What this fork is for, and what comes next. Ordered by payoff over effort. Items move to a
feature doc once they ship; nothing here is a promise about order.

## Where things stand

A personal fork of abue-ammar/tinycast, stripped to the features its owner uses, as a Raycast
replacement without AI, monetisation or Raycast compatibility. `main` is the fork and diverges on
purpose, one commit per checkpoint. Every checkpoint passed the full definition of done in
[docs/testing.md](docs/testing.md): harnesses, warning-free Debug build, lint, purity grep, docs.

Upstream is harvested, never merged. Branch `upstream-reviewed` on `origin` marks the last upstream
commit read. Never use GitHub's "Sync fork", which merges all of upstream.

```sh
git remote add upstream https://github.com/abue-ammar/tinycast.git   # once per clone
git fetch --all
git log --oneline origin/upstream-reviewed..upstream/main   # what is new
git cherry-pick -x <sha>                                     # take what fits
git push origin upstream/main:upstream-reviewed             # mark it all read
```

Known flakes under parallel load: `clipboard-text-test` (timing-based scheduler) and
`icon-cache-test` (icon rendering). Both pass in isolation.

Findings from the initial survey that still shape the plan:

- `AppCore` is an 850-line service locator and `RootPaletteView` a 1,300-line view; both are
  where new wiring lands, so touch them surgically.
- Two fuzzy scorers exist: `LauncherMatch` for the root search, `SearchRelevance` for every
  sub-screen.
- Persistence is mixed (SQLite, UserDefaults JSON, loose JSON, `.md` files) and most writes are
  `try?`, so failures are silent.
- Space switching synthesizes a trackpad-swipe `CGEvent` with undocumented fields; expect it to
  break on OS updates.
- The Hyper key remaps Caps Lock by shelling out to `hidutil` and wipes any other mapping.

## Done

- Removed AI, MCP, Quick Actions, the Support window and reminder, the in-app updater, the website.
- Removed File Search, Raycast extensions and Menu Search.
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
