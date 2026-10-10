# Key Remapping

The **Hyper** and **Meh** keys turn one physical key on the built-in keyboard into a held chord —
⌃⌥(⇧)⌘ and ⌃⌥⇧. Tinycast does it below every event tap, by taking the built-in keyboard over and
retyping it through a virtual one, so a remap keeps working where a `CGEventTap` goes blind: Secure
Input, a stalled main thread, a missed modifier release. External keyboards are left alone.

The virtual keyboard is pqrs's [Karabiner-DriverKit-VirtualHIDDevice][driver], the driver
Karabiner-Elements and kanata use. It is installed separately and signed by its author, which is what
spares Tinycast a DriverKit entitlement: the driver's commands only have to come from root.

[driver]: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice

## Invariants

- **The helper holds the keyboard only while every report can reach the virtual one.** It seizes once
  the driver reports the virtual keyboard ready and releases the moment that stops being true, so a
  dead driver gives the keyboard back instead of swallowing it. `RemapWorker.wantsKeyboard` is that
  rule, and "ready" expires: the daemon answers every request at once, so any request unanswered
  for a second, ten seconds without a byte, or a write blocked for half a second drops the connection
  and with it the keyboard.
- **The keyboard is held only while Tinycast holds a session.** The helper is configured over XPC, and
  the session closing — a quit, a crash, a switch to another account, the Hyper and Meh keys both set
  to None — releases it. A
  stale session closing after a newer one took over releases nothing (`HelperMailbox.closeSession`).
- **A stalled keyboard thread kills the helper.** `HelperWatchdog` exits once the thread has not
  ticked for two seconds while the keyboard is held — armed from before the device is opened until it
  is closed — because the kernel frees a seized device when its process dies, and launchd starts a
  fresh helper on Tinycast's next message. A hang must never look like a dead keyboard.
- **The engine is pure, and the only owner of what goes out.** `Model/` compiles into the app, the
  helper and `key-remap-test`; nothing in it touches IOKit, a socket or a clock.
- **Report bytes match the driver's packed C++ structs exactly.** The daemon drops a request whose size
  is wrong without saying so, which would look like a keyboard that types nothing.
  `key-remap-test` pins them with bytes written out by hand.

## Pieces

| Where | What |
| --- | --- |
| `Model/HIDUsage`, `VirtualHIDReport` | A usage page and usage; a report as the driver lays it out |
| `Model/VirtualHIDWireFormat` | The daemon's client protocol: frames, requests, status pushes |
| `Model/TopRowMap` | The built-in keyboard's F-key → system-action table |
| `Model/KeyRemapEngine` | Seized input → virtual reports: chords, quick presses, the top row |
| `Model/KeyRemapConfiguration`, `KeyRemapHelperInterface` | What crosses XPC, and the shared names |
| `Service/KeyRemapManager` | The app side: registers the helper, configures it, reports its health |
| `Helper/` | The root LaunchDaemon, built as the `TinycastKeyboardHelper` target |

## The helper

`TinycastKeyboardHelper` ships in `Contents/Helpers/` and runs as root, registered with
`SMAppService.daemon`. A build step writes its plist into `Contents/Library/LaunchDaemons/` with the
label `<bundle id>.keyboard-helper`, so Tinycast Dev runs a helper of its own. The app connects with a
privileged `XPCSession`; each side checks the other is signed by the same team, and the helper also
checks the client is the app that owns it. **A self-signed build has no team, so it cannot use the
helper at all** — remapping needs a build signed by an Apple team.

The helper is launched on demand rather than kept alive. Tinycast sends its configuration every
second, which is also how a helper launchd restarted gets it back; the helper exits after thirty idle
seconds, and at once when its own executable is replaced, so an updated app never talks to an old
helper. Turning both keys off only closes the session — the registration, and the approval with it,
stays.

Everything on the keyboard path lives on one thread, `RemapWorker`'s: the seized device's
`IOHIDQueue`, the driver socket, the engine and a 250 ms tick. Nothing on it takes a lock or hops an
actor, so a keystroke goes from the queue callback to the socket write without waiting on anything.
`HelperMailbox` is the single place the XPC threads meet it — a configuration in, a status out — and
the tick is what reads it, so a configuration lands within a quarter second.

The seize reads input through an `IOHIDQueue` over every input element: a device-level value callback
received nothing once the built-in keyboard was seized.

### Permissions

The helper needs no grant of its own. macOS attributes a daemon to the app that registered it, so the
Accessibility grant Tinycast already holds covers the seize; without it the seize fails with
`kIOReturnNotPermitted`, which Settings reports. Turning a key on asks the user to allow the helper
once under **Login Items & Extensions**.

## The driver protocol

pqrs ships a C++ client; Tinycast speaks the protocol itself rather than vendoring it and its
dependencies. The daemon listens on a root-only stream socket. A frame is a big-endian `UInt32`
length, a kind byte, and for requests and responses a big-endian `UInt64` id; a request's body is the
client protocol version (`UInt16`, native order), a request byte, then the report or parameters packed
as the driver's structs. The daemon pushes status changes as requests of its own, each of which wants
an empty response, and closes a client it has not heard from, so the helper heartbeats every three
seconds.

**The protocol version is pinned to 7**, which driver v8 speaks. The daemon answers any other version
with nothing, and v7 changed the transport outright, so a driver update can break remapping. An empty
answer to the keyboard's initialization is that rejection — initialization otherwise answers with
statuses — and Settings reports it as an unsupported driver, as it does the daemon's own
`driver_version_mismatched`, which compares the daemon with the driver extension instead.

The helper starts pqrs's daemon itself when nothing answers the socket, rather than registering it as
a second login item; when Karabiner-Elements is installed, its daemon answers and is used instead.

**The virtual keyboard presents as an Apple Aluminum keyboard**, as Karabiner-Elements' does: product
`0x024F`, `0x0250` or `0x0251` for the built-in keyboard's ANSI, ISO or JIS `StandardType`, since
Apple's driver translates layout-specific keys by type. With Apple's ids macOS attaches that driver,
which marks the keyboard as having a Globe key and brings the fn layer for the arrows, Delete and
Return; with pqrs's default ids, fn+← arrived as a plain ←. Apple keyboards also ignore a brief Caps
Lock press, which a Quick Press tap is, so the helper overrides that delay to zero on the virtual
keyboard, as Karabiner-Elements does. Each seize starts and ends with a keyboard reset, so nothing
the virtual keyboard still held from an earlier one survives it.

## The engine

`KeyRemapEngine` keeps what is down per report kind and emits only the reports that changed.

- A **bound key** never reaches the virtual keyboard. While held it ORs its modifiers — the left-side
  bits, which every consumer reads as fully pressed — into the keyboard report.
- **Quick Press**: a bound key pressed with nothing else held and released within 250 ms, with nothing
  pressed in between, lifts the chord and then taps Escape or Caps Lock. A tap never lifts a key the
  user is physically holding.
- Every other key, modifier, Globe and media key passes through on its own page.

### The top row

The built-in keyboard reports its top row as plain F1–F12; turning them into brightness, Mission
Control, Spotlight, Dictation and the media keys is its own driver's job, and that driver is bypassed
by the seize. The virtual keyboard's driver would do it with the Aluminum keyboard's older table, so
the engine does it instead, from `FnFunctionUsageMap` — the table the built-in keyboard's driver
publishes in the registry, read at seize time.

The engine sends the action exactly where the built-in driver would: when fn is held **and** "Use F1,
F2, etc. keys as standard function keys" is on, or neither is. Otherwise the plain F-key goes out, in
a state where the virtual keyboard's driver leaves it alone. A key's release matches its press, even
if fn moved in between.

## Setup

1. Install the driver package from its releases page and run its manager's `activate`, approving the
   driver extension under **Login Items & Extensions → Driver Extensions**.
2. Choose a Hyper or Meh key in **Settings → General**, and allow the helper when asked.
