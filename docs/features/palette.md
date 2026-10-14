# Palette

The command palette is a borderless floating `NSPanel` hosting SwiftUI; see
[architecture.md](../architecture.md) for window ownership.

## Invariants

- **`PaletteWindowController` solely owns the palette frame.** The hosting view sets
  `sizingOptions = []` so SwiftUI never drives the window size — otherwise the hosting view resizes the
  panel to fit content and the top edge drifts on the compact↔expanded swap. Nothing else moves the
  panel: there is no drag handle and no remembered position.
- **The flat `selection` index must match the visible row order exactly**, including the inline
  calculator card at index 0 when present. Selection is the single source of truth for highlight and
  activation. `Features/PaletteRowIndex.swift` is that mapping and stays **Foundation-only and pure** —
  no SwiftUI, no AppKit — so `palette-selection-test` compiles the shipped type rather than a copy.
  Section headers are not selectable and never consume an index.
- **A menu owns native text input while it is open.** Its panel becomes key so the menu field gets an
  AppKit field editor; the palette field stays mounted and inert beneath it.
- **The search field is never mounted conditionally**, because flipping a branch around it tears its
  field editor down.
- **Focus restoration is load-bearing.** Paste targets the recorded `previousApp` and requires the
  Accessibility permission (`Permissions.ensureAccessibility()`).
- **Input-source switching is a palette session.** The source active at summon time is captured before
  the panel becomes key, the configured source is applied through `PalettePanel.fieldEditorContext`, and
  the captured source is restored on hide and on termination — but only when the palette is still on the
  source it applied, so a switch made since, by the user or another app, stands. Never applied globally:
  the panel does not activate, so a global switch would land on whichever app is still frontmost.

## Summoning

```
⌥Space (Carbon) → HotKeyCenter → HotKeyManager.perform → AppCore's onTogglePalette closure
                                                              ↓
                                          PaletteCoordinator.togglePalette()
                                                              ↓
                                          PaletteWindowController.show()
                                            · records previousApp (the paste / focus target)
                                            · resolves PasteTarget once per summon
                                            · resolves the screen anchor once per summon
                                            · captures the input source to restore, once per summon
                                            · positions, lays out off-screen, orders front
                                                              ↓
                                                    RootPaletteView.body
                                            · focuses the search field
                                                              ↓
                                            PalettePanel.makeFirstResponder
                                            · applies the configured source to the field editor
```

Everything resolved "once per summon" is resolved there deliberately, not per render. `AppCore` holds
only the closure wiring; the behaviour is `PaletteCoordinator`'s.

## Screens

`PaletteState` (mode / query / selection / `focusToken`) is the bridge between the panel and the app.
Preparing a screen resets state and bumps `focusToken` (a UUID). `PaletteWindowController.show()`
also bumps it before presenting the panel, so a preserved screen re-focuses its search field too.
Closing a palette menu explicitly restores search focus after its panel returns key status.
`prepare` is one of four motions over the screen — see [Navigation](#navigation).

Hiding schedules Pop to Root Search, and `PaletteWindowController.popToRoot` is its only path: the
palette returns to the launcher, at once or after `popToRootTimeout`, unless a re-summon inside that
window consumes the pending reset first.

Each `PaletteMode` maps to one type conforming to `PaletteScreen`, and the protocol is what keeps the
selection invariant honest: a screen exposes `rows` as its single source of visible order, and the
palette indexes into it. Adding a mode means adding a conformer, not a branch in `RootPaletteView`.
A chord aimed at the selected row — ⌃X, ⇧⌘F and the rest — follows the same rule:
`PaletteShortcut` recognises the key and carries its compact-bar and open-menu guards, and the screen
answers through `perform(_:at:)`, so a new chord never adds a cast to the shell.

Where a reset leaves the highlight is the screen's to say too. Every reset — an open, a new query, a
new filter — goes through `RootPaletteView.land()`, which reads `landingSelection`, so handlers that
fire in one update agree whatever order they run in. `onAppear` lands as well: the first show builds
the view after `prepare` has run, so no change handler ever sees that reset. The landing is row 0 on
every screen but one: the clipboard lands past its pins
([clipboard.md](clipboard.md#pinned-entries)).

| Mode | Screen | Inner list |
| --- | --- | --- |
| `.launcher` | `LauncherScreen` | `LauncherList` |
| `.clipboard` | `ClipboardScreen` | `ClipboardList` + preview |
| `.calculatorHistory` | `CalculatorHistoryScreen` | `CalculatorHistoryList` |
| `.emoji` | `EmojiScreen` | `EmojiGridView` |
| `.uninstall` | `UninstallScreen` | `UninstallList` (see [uninstall.md](uninstall.md)) |
| `.dictionary` | `DictionaryScreen` | `DictionaryEntryView` (see [dictionary.md](dictionary.md)) |

**Tab rings the two surfaces a reader opens directly — launcher ↔ clipboard**; every other
mode stays off the ring, and is reached by a command or a global hotkey, with Uninstall only from a
launcher app's Actions menu, scoped to that app. Clipboard is skipped when `clipboardEnabled` is off,
which leaves Tab on the launcher with nowhere to go.

The flat `selection` index is the single source of truth for highlight / activation and **must always
match the visible row order**, including the card at index 0 when present — the calculator's (see
[calculator.md](calculator.md)) or the colour card (see [clipboard.md](clipboard.md#colours)), never
both.

### Navigation

**The summon decides where a screen sits, not the mode.** `PaletteCoordinator.navigate(to:)` is the
one rule: a palette already on screen is being *navigated*, so the current screen is pushed and
becomes the step back; a hidden one is being *summoned*, so the new screen is a root with nothing
behind it. Every mode command and every global hotkey funnels through `showPalette`, which calls it —
so typing "Clipboard History" at the root and pressing ↵ leaves a step back to the search that found
it, while the Clipboard History hotkey does not. **The launcher is the exception, because it is the
root** — ⌘Space over an open clipboard opens the root search with nothing behind it, rather than
stacking the launcher over the screen it replaced. Nothing per-feature encodes this.

`PaletteState` holds the screens below `mode` as `[PaletteFrame]` — mode, query and selection, enough
that returning looks like never having left — and offers four motions over it:

| Motion | Meaning |
| --- | --- |
| `prepare(mode:)` | become the root: open fresh, drop the stack |
| `replace(mode:)` | swap the screen, keep what it was opened over |
| `push(mode:)` | open over the current screen, which a back step returns to |
| `pushCarryingQuery(mode:)` | the same step, with the query and row kept: Tab's hop into the ring |
| `pop()` | restore the screen underneath; `false` when this one is the root |

`pop()` bumps `followToken` rather than `resetToken`: the reset token exists to land a list afresh,
which would throw away the very selection being restored.

**Escape clears a non-empty query before it leaves the screen**, so one press clears and the next
leaves: a pushed screen pops, and a root hides the palette. A bare backspace in an empty field takes
the same step **but never closes**: on a root screen summoned by its own hotkey it falls to the root
search, which is the step Escape would have taken had that screen been reached by typing its name.
⌘⎋ skips the whole stack for that same root search from any depth.

`EscapeKeyBehavior` (General settings) can trade the walk back for the old behavior: under
`closeAndPopToRoot` an empty field closes the window and resets it immediately, whatever Pop to Root
Search says. Clearing the query is still the first press either way.

The header draws a back chevron on **every** screen but the launcher: leaving is what the icon
slot means once you are off the root, and a slot that changed shape with provenance would read
as two different controls. Where the click lands still depends on the stack — a pushed screen
pops, a root one closes — so `backHelp` says which, rather than promising a step that is really
a close. It lights to `textPrimary` under the pointer over `Theme.Duration.hover`, and
`HeaderBackButton` keeps that hover state to itself so the header around it never re-renders.

`PaletteTabAction` decides where Tab goes *and* what happens to the typed text: both ends
`.carryQuery` — the text rides along, since one search narrows either list — and a sub-screen exits
to the launcher.

**A ring hop is a step, so Escape walks back out the way Tab came in** — launcher → clipboard takes
one press to unwind, and the back chevron's tooltip stops promising a step it cannot take. The
launcher is the ring's root, so the hop that closes the ring resets the stack instead of stacking
another screen; ringing round forever therefore never grows the stack past two.

## Window placement

`PaletteWindowController` resolves an anchor (left edge + top edge) **once per summon** and reuses it
for every compact↔expanded resize, so only the height changes and the top edge never drifts. The
anchor is dropped on hide, so the next summon re-resolves for wherever the user is then.

The anchor is `PalettePlacement.defaultAnchor`: centred on the display, its top edge
`Theme.Size.paletteTopMarginFraction` of the way down. `PalettePlacement` is CoreGraphics-only and
takes every screen fact as a parameter, so `palette-placement-test` drives the shipped rule rather than
a copy of it.

The display is always the one under the pointer: `NSScreen.underCursor`, the screen holding
`NSEvent.mouseLocation`. **Never `NSScreen.main`**, which is documented as the screen of the window
with keyboard focus — the frontmost app's, wherever the user last clicked — so it follows focus across
displays rather than the pointer.

The cursor hit test is `NSMouseInRect(mouse, screen.frame, false)`, **not** `CGRect.contains`. A mouse
location is the CoreGraphics cursor position flipped about the primary display's height, so a screen's
rows land in the half-open interval `(minY, maxY]`: the topmost row is exactly `maxY`, which `contains`
excludes, while that same value is the `minY` of the display stacked above. `contains` would therefore
hand a pointer parked at the top of one display to its neighbour. `NSMouseInRect` exists for this.

## The placeholder is Tinycast's, not the field's

The search field is a SwiftUI `TextField` with **no `prompt`**; `RootPaletteView` draws the
placeholder itself as a leading-aligned background `Text`.

AppKit gives an `NSTextField` a field editor one point taller than the field (measured: a 24pt editor
in a 23pt field), and a `prompt` is rendered by whichever of the cell and the editor currently owns
the text. The same placeholder glyphs therefore sit **one point higher** once the field takes the
panel's shared field editor. That editor is created lazily and then cached on the window for its
lifetime, so the step was only ever visible on the first summon after launch — and only where the eye
could track it, when the outgoing and incoming placeholders share a leading word.

Drawing it in SwiftUI pins it to the layout instead: measured ink is identical in both focus states,
against a two-backing-pixel step for the real prompt. It is a **background**, not an overlay, so the
caret still draws over it, and it carries `allowsHitTesting(false)` so clicking the placeholder still
lands the caret. `PaletteMode.placeholder` is still the one source of the strings; the field takes an
explicit `accessibilityLabel` because the prompt used to supply it.

This is the same class of bug as the freeze below — both come from the cell/field-editor swap.

### IME composition

A hand-drawn placeholder has one cost the real prompt does not. An IME composes into the field
editor's own storage, so the bound `query` stays empty for the whole romanisation and the placeholder
would sit under the in-flight pinyin. `PalettePanel` publishes the editor's `hasMarkedText()` as
`PaletteState.isComposing`, and the placeholder is gated on `query.isEmpty && !isComposing`.

The same empty `query` would read as "nothing left to delete" to the bare-backspace step back, so
`PalettePanel.sendEvent` asks the editor's `hasMarkedText()` itself and lets Backspace through to the
IME while a composition is in flight. That covers every screen.

The observation follows first responder, since SwiftUI hands the window's one field editor to
whichever field holds focus, and it watches `NSTextView.didChangeSelectionNotification`. Measured,
that is the **only** notification a marked-text change posts: `NSText.didChangeNotification` fires on
the commit alone, which is the whole composition too late.

`trackComposition()` re-reads the editor rather than assuming, and `windowDidBecomeKey` calls it as
well as `makeFirstResponder`: a key transition can commit or drop marked text without posting
anything, and a re-summon inside the Pop to Root window skips `prepare(mode:)` and never moves first
responder, so neither of the other two paths would fire.

## The panel settles the pointer itself

`PalettePanel.applyCursorPolicy` sets the cursor after every mouse event: the I-beam inside the search
field's frame, the arrow everywhere else. Without it the palette's pointer sticks as an I-beam over the
whole window and flickers along the field's edge — the two AppKit mechanisms that claim a cursor here
disagree, and neither yields.

- SwiftUI's `HostingClipView` claims the **arrow** across the entire window as a *cursor rect*.
- The field editor claims the **I-beam** from its own *tracking area*.

Both fire on the same crossings, so the cursor alternates while the pointer is over the field, and the
last claim simply stays put once it leaves — nothing re-evaluates a cursor rect until the pointer
crosses one, and the arrow rect spans the window, so leaving the field crosses nothing.

Two measured details the policy depends on:

- **The field publishes its own frame.** `RootPaletteView` reports it into `PaletteState.searchFieldFrame`
  via `onGeometryChange`, and the panel does a containment test against that. Hit-testing for the field
  instead does not work: SwiftUI rebuilds it as it re-renders, and a hit test taken mid-rebuild misses
  it and reads as *the pointer left the field*. The frame only moves on layout, so it never lies.
  It arrives top-left-down and is flipped into AppKit's bottom-left-up window space.
- **The rect is outset by 2pt.** AppKit's field editor is a point taller than the field it serves — the
  same measurement the placeholder section above rests on — so its I-beam overhangs the published
  frame. Without the slack that 1pt band is a disagreement, and it flickers.

The policy runs after `super.sendEvent`, so it has the last word, and it writes only when the cursor
actually differs. It must stay **symmetric**: an earlier version left the field alone and only forced
the arrow outside it, and AppKit's own alternation over the field came straight back.

## One menu at a time

`RootPaletteView` holds a single `OpenMenu?` rather than a flag per menu, so "at most one is open" is
structural instead of a pair of `onChange` handlers pushing each other closed. The ⌘K Actions menu
hangs `.bottomTrailing`, the app menu `.bottomLeading`, and everything drawn as a header control —
the clipboard type filter and the emoji category filter — hangs `.belowHeaderTrailing`, under its
own button. `menuContent` resolves the open case to one `PaletteMenuContent` — a row count, a row
action and a view built on demand — so ↑/↓, plain ↵, Esc and the click-away catcher serve every menu
without knowing which is up. A screen supplies its rows as a `PopoverMenuContent` through
`actions(at:)`, and `PaletteScreen.menuContent` wraps them. The view is a closure because `moveMenu`
resolves the open menu on every arrow key and needs the row count alone. Every open path goes through `open(_:highlighting:)`
and states where the highlight starts: the first row, except a pop-up-shaped menu — the type
filter — which opens on the choice it already holds.

**The palette window consumes a click-away press through its release.** While a menu is open,
`PalettePanel` dismisses it on either mouse button's press and consumes the matching drag and release
before SwiftUI sees them. A row or footer button beneath the menu cannot inherit a partial click,
and the next click reaches its control normally. The menu controller installs the dismissal callback
only while the menu is open and clears it before restoring the palette's key status.

Every row closes the menu behind it — `activateMenuItem` is the one path, and a row that reorders the
list under itself (Move Favorite Up/Down) is no exception, so no row ever runs against a rebuilt menu.

`PopoverMenuItem.startsSection` draws a separator with the list inset (8pt) above and below it, so a
row sits as far from it as from the search field's hairline. That height joins the menu's exact
sizing, but the separator takes no selection index, so navigation still walks only rows. A menu
taller than its cap ends its viewport mid-row, so the fold never lands on a separator or section
title, and both hairlines are one device pixel.
The app menu keeps its five actions in one group and caps the list at four and a half rows, leaving
Quit partially visible above the search band until scrolling or keyboard navigation reveals it.
Built-in action menus mark boundaries between opening or copying, managing the item, settings, and
deletion. Menus offering one kind of action, such as calculator copies, color formats, or emoji
transfers, keep their rows in one group.

Every launcher Action Menu has a native, row-height search field. Footer menus place it below their
rows; header menus place it above them. `ActionMenuSearchQuery` folds the shared fuzzy query once per
menu rebuild, then each menu filters its own rows and preserves section boundaries. A search with no
match keeps the header, when present, and centres **No Results** in one row. The list has no edge
dissolve beside a search field. Its resting inset travels with the scroll content, so rows can reach
the panel edge without moving their initial position. Footer menus add 30pt to the standard menu
width; their hover keeps the shared 10pt menu-row corner.

### The menu's own window

A menu is **not** an overlay inside the palette: `MenuPanelController` hosts it in a `MenuPanel`, a
borderless non-activating `NSPanel` added as a **child window** of the palette's, which is what makes
it vanish with the palette. Glass renders against the desktop rather than inside an
already-blurred, clipped panel, and no menu can be cropped by `RootPaletteView`'s `clipShape` however
long it grows. The menu temporarily becomes key so its native `TextField` owns the caret and selection, while
`MenuPanel` hands navigation and action shortcuts back to `RootPaletteView`. It restores key status
to the palette when it closes, and `closeMenus()` restores search focus.
Resigning to the palette closes only the menu; resigning to another
app closes the palette as well. `MenuPanel.sendEvent` also mirrors `PalettePanel`'s hover arming — rows
light on real pointer movement, never on a scroll under a still cursor.
Deferred focus-loss dismissal checks the presentation identity and that the menu has not regained key
status, so an old callback cannot close a reopened menu.

The panel is a second SwiftUI hierarchy, so it observes nothing of `RootPaletteView`'s `@State`:
`syncMenuPanel` pushes a rebuilt tree on every `openMenu` or `menuSelection` change, and
`paletteEnvironment` injects the same stores into both hierarchies so they cannot drift.
`WindowReader` reports the palette's `NSWindow`, which the menu's frame is placed against.

`PaletteMenuContent` may supply its own host-layer clip path and motion.
The hosting layer scales inside a canvas sized for the largest frame, anchored to the button or
header control that opened it, so neither the surface nor its shadow is cropped. AppKit refreshes
the shadow after layout and display. Native `PopoverMenu` content reads its motion from
`Theme.MenuMotion`; the controller applies a supplied clip path as an opaque value and never
reconstructs the menu's geometry.

## Menu-open input freeze

While a popover menu is open, its native field takes key status so AppKit supplies the blinking
caret, mouse selection and standard editing commands.

- `RootPaletteView` mirrors the open state into `PaletteState.menuOpen`, whose `didSet` fires
  `onMenuOpenChanged`.
- The searchable field binds directly to `PaletteState.menuQuery`; Escape clears a non-empty query,
  then closes the menu on the next press. A click outside still closes it immediately. `MenuPanel`
  keeps ↑/↓, ↵, Tab and action chords on the menu while leaving text editing, selection and
  clipboard commands to AppKit.
- The palette window delegate ignores this intentional key transfer. Losing key status to anything
  else still dismisses the palette, and closing the child restores key status before it fades out.
- The caret is hidden by clearing SwiftUI's **own** live field editor's `insertionPointColor`. SwiftUI
  force-casts its field editor to a private subclass, so vending a custom one crashes. The searchable
  menu draws no caret of its own; AppKit draws the caret in its field editor.
- SwiftUI resolves `tint` into a fixed caret colour on focus and never refreshes it, and the search
  field keeps focus across hide and show. `PalettePanel.makeFirstResponder` re-colours the editor with
  the dynamic `textPrimary`, so the caret follows a Light/Dark switch.

## ↵ never commits the search field

Plain ↵ is claimed by `RootPaletteView`'s own `onKeyPress` whenever the search field holds focus, and
`activateSelection` runs from there — the field carries no `onSubmit`. Letting the field submit ends
editing, and AppKit tears the field editor down and selects the whole string when focus returns, so a
screen opened with a carried query came up with that query selected. An
IME's composition is left alone, as is a press while the search field does not hold focus: the
handler returns `.ignored` for both.

## The query is one line

A paste, a drop or ⌥↵ can put line breaks into the search field, which then wraps its text out of
view. `PaletteState.collapseQueryLineBreaks()` joins the lines with a space and drops breaks at
either end. It runs from `RootPaletteView`'s `onChange(of: vm.query)`, which returns early so the
filtering runs once, on the rewritten query. It cannot live in `query`'s setter: measured, SwiftUI's
field editor keeps the text it just set and ignores a rewrite made inside that same set. The rewrite
moves the caret to the end, which only differs from a normal paste when pasting mid-query.

## Chords `onKeyPress` never sees

Most ⌘/⌃ chords reach SwiftUI's `onKeyPress` fine. Several kinds do not. All but the last are
handled in `PalettePanel.sendEvent` before `super` hands the event to the responder chain:

- **A bare backspace** — the field editor consumes it as an edit (`onBareBackspace`).
- **Chords with no main menu item** — ⌘, and ⌘w, which an app with a menu bar would never see here.
- **The physical number-row slots.** `FavoriteSlots` matches ⌘1…⌘0 by key code before fixed command
  chords, then publishes the resolved position to the active screen. Only the launcher and clipboard
  screens intercept these slots; other screens keep their own ⌘-number shortcuts.
- **Chords AppKit has already bound to a selector.** `⌘.` is the one that bites: AppKit binds it to
  `cancelOperation:` alongside Escape, so `interpretKeyEvents` hands it to the field editor and
  `onKeyPress(keys: ["."])` never fires. Pin (⌘.) therefore arrives through `onCommandShortcut`,
  which bumps `PaletteState.pinChordToken`; `RootPaletteView` observes that and resolves the row
  through the current screen, so **which** row gets pinned still comes from `screen.rows` alone.
- **Emoji zoom chords.** `⌘0`, `⌘+` and `⌘-` take the same `onCommandShortcut` path on the emoji
  screen, Shift allowed since `+` is a shifted `=`. They bump `PaletteState.emojiGridZoomToken`, and
  `EmojiScreen.zoom` applies the same bounded change as its Actions rows.
- **Chords the window server keeps for itself.** ⌘⎋ is the one that bites: macOS binds it before any
  app sees it, so unlike ⌘. there is no keystroke left for `sendEvent` to intercept — a handler in
  the responder chain compiles, runs never, and looks like a palette bug. `CommandEscapeTap` takes it
  at the head of the HID stream instead, the one place earlier than the system's own binding, and
  `prepare(mode: .launcher)`s: one chord back to the root search from any depth, window still open.
  The tap is enabled only while the palette is on screen, watches `keyDown` alone, and declines the
  chord whenever the panel is not key, so nothing else on the system loses ⌘⎋ to it. It is a
  modifying tap, so it needs Accessibility — without that grant the chord is simply unavailable,
  which is the only path this codebase has to it.

Adding a chord that "does nothing" is almost always one of these — check `sendEvent`, and then
whether macOS has claimed the chord, before assuming the handler is wrong.

## Emacs navigation chords

⌃N/⌃P and ⌃F/⌃B navigate exactly as ↓/↑ and →/← do — on the emoji grid all four step the selection,
and everywhere else the horizontal pair falls through to the caret, which is what a native search field
does.

None of them reach `onKeyPress` on their own: AppKit's key-binding table hands the field editor
`moveDown:` / `moveUp:` / `moveForward:` / `moveBackward:` first, and in a one-line field the vertical
pair walks the caret to the end or the start rather than moving anything.

`PalettePanel.sendEvent` therefore rewrites each chord into its arrow and re-dispatches, ahead of every
other rule it applies. Nothing else changes: the arrow handlers in `RootPaletteView` are the only
navigation code, so the compact bar's expand-on-↓, the grid's row and column steps, menu highlight
movement and the scroll-into-view intent all follow for free. The caret keeps ⌃F/⌃B off the grid
because `moveHorizontally` leaves →/← `.ignored` there, and the field editor then moves by a character
exactly as the chord natively would. A chord carrying any modifier beyond ⌃ — ⌃⇧Q, say — is left alone.

Character shortcut handlers accept every key so SwiftUI still calls them when the active input
source produces a non-ASCII character. Inside the callback, `ASCIIKeyboardLayout` resolves
`NSApp.currentEvent.keyCode` through the current ASCII-capable layout before comparing the shortcut.
Panel-owned chords use the same translation directly. A ⌘ chord translates through the layout's own
Command table, so "Dvorak – QWERTY ⌘" keeps giving QWERTY positions while Command is held; a ⌃ chord
translates without it, since only Command is remapped. A non-ASCII input source or IME therefore
cannot turn ⌘K into a different logical key, while Dvorak and other ASCII layouts keep their own
letter positions. A key SwiftUI spells in the private-use area — the arrows, and the page, home and
forward-delete keys — skips the recovery outright: `UCKeyTranslate` answers those keycodes with ASCII
control characters, which the ASCII test would otherwise accept in place of the key itself, and a
layout has no letter position to recover for them anyway. No replacement event is synthesized, and
unmodified typing stays on the active input source and follows the normal composition path.

## The keyboard belongs to the search field

`PalettePanel.makeFirstResponder` declines any responder whose subtree is marked
`KeyboardFocusRefusing`. That mark exists for one shape of problem: a preview that embeds AppKit
controls of its own. Clicking play on an `AVPlayerView` makes `AVDesktopButton` — a private control
inside its transport — the window's first responder, and the search field silently stops receiving
keystrokes with nothing on screen to say so. Refusing costs the transport nothing, since a button
performs its action from the click, not from focus; both preview players are marked, and the field
keeps the caret through a click on play.

The mark sits on the player view and the check walks up from the responder, because the control that
claims focus is private and several levels down — there is nothing to override on it.

## Focus restoration (load-bearing)

`PaletteWindowController` records `previousApp` (the frontmost app) on show. Paste then targets that
app:

- `Paster.paste` activates it and posts a synthetic ⌘V via `CGEvent`.
- `Paster.pasteInPlace` posts ⌘V straight to the app's PID _without_ activating it, so the palette can
  stay open and frontmost (used by "paste keeping window open").

Both require the Accessibility permission (`Permissions.ensureAccessibility()`).

The same show also mirrors that app into `PaletteState.pasteTarget` (a `PasteTarget`: localized
name + bundle path), so Clipboard and Emoji can name it — the footer pill reads "Paste to Notes" and
the ⌘K paste rows carry the app's icon. Resolved once per summon, never per render, and deliberately
not cleared by `prepare` (pop-to-root resets the screen, not the target).
