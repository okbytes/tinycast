# Tinycast

**A tiny, fully native macOS launcher. One hotkey, everything you reach for all day, under 100 MB of
RAM.**

<p align="center">
  <img alt="Swift 6.0"
       src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white">
  <img alt="macOS 27 or later on Apple silicon"
       src="https://img.shields.io/badge/macOS-27%2B-000000?style=flat&logo=apple&logoColor=white">
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
</p>

SwiftUI and AppKit, **zero third-party dependencies**, no Electron and no telemetry. Free, open
source, and staying that way.

<p align="center">
  <img src="docs/screenshot.png" alt="Tinycast command palette" width="720">
</p>

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).
- **Dictionary** — look a word up with the Define Word command, read from the Mac's own dictionaries.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Calculator** — do math, unit, live currency and crypto conversions inline, right in the palette.
- **Apple Shortcuts** — search and run the shortcuts you built in the Shortcuts app, with aliases and
  global hotkeys.
- **Window management** — 15 Rectangle-style actions: halves, quarters, three fourths, Maximize,
  Center and edge moves.
- **System actions** — lock, sleep, restart, empty trash, toggle appearance, Bluetooth, mute, hidden
  files, and more.
- **Calendar** — what's coming up next in the menu bar, the schedule on click, and one click to open
  any event in Calendar.
- **Emoji picker** — a searchable emoji grid, one keystroke away.
- **Backup and import** — export your setup to a file, and import it on another Mac.

## Install

Releases are notarized builds attached to this private repo's GitHub releases. On any Mac with
`gh` logged in, this installs the latest into `~/Applications`, or updates it in place:

```sh
gh api repos/okbytes/tinycast/contents/scripts/install.sh -H "Accept: application/vnd.github.raw" | bash
```

In a checkout, `./scripts/install.sh` does the same. Cutting a release and the one-time signing setup
are in [docs/signing.md](docs/signing.md); a Dev build from the checkout is
`./scripts/install-dev.sh` ([docs/development.md](docs/development.md)).

## Permissions

**Accessibility** — needed when Tinycast pastes text into another app. You're prompted when you
first use a feature that needs it; grant access in **System Settings → Privacy & Security →
Accessibility**.

## Using it

1. Open **Settings → General** and record a global shortcut to summon Tinycast.
2. Press it anywhere → the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → Applications**, **Commands** or **Apple Shortcuts** — record a global shortcut for
   any row.

## Building from source

See **[docs/development.md](docs/development.md)** for the toolchain, build and packaging
workflows. **[docs/](docs/README.md)** indexes everything else — architecture, engineering
standards, the design system and one document per feature.

## License

[AGPL-3.0](LICENSE)
