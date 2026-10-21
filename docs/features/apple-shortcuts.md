# Apple Shortcuts

The shortcuts a user builds in Apple's Shortcuts app appear in the launcher as their own section,
searchable by name and runnable with ↵ or a global shortcut. Tinycast lists and runs
them and nothing else: creating, editing, permissions and the actions themselves stay with Shortcuts.

The feature ships **off**. **Settings → Apple Shortcuts** carries the one switch, and lists the
library only while it is on. Off is fully off: the `shortcuts` tool is never spawned, the launcher
section is empty, and `AppleShortcutCoordinator.run(id:)` refuses to run anything. Bindings stay
registered, so re-enabling restores every global shortcut.

## Invariants

- **Shortcuts owns the library.** Nothing about a shortcut is stored except what every launcher entry
  already keys by `preferenceKey` — alias, visibility, ranking — and its hotkey binding.
- **`run(id:)` is the single funnel** for a launcher row and a global shortcut alike, so the switch
  can't be bypassed.
- **A failed read keeps the last good library.** Emptying the launcher because one spawn failed would
  look like every shortcut was deleted.
- **Only a successful read frees anything.** A shortcut missing from one loses its binding, alias,
  visibility and ranking; a failed read changes nothing, since it can't tell deleted
  from unreadable. An empty read and turning the feature off free nothing either.
- **`Model/` stays Foundation-only and pure** for `apple-shortcut-test`.

## Discovery

There is no public API that enumerates shortcuts, so `AppleShortcutRunner` runs Apple's own
`/usr/bin/shortcuts` through `ToolRunner`. It needs no TCC grant and no Apple-event entitlement.

```text
shortcuts list --show-identifiers   →   Set Volume to 50% (97A1DDFA-76F3-4872-A672-25D5F35B7882)
```

`AppleShortcut.parseList` anchors on the **trailing** `(UUID)`, so a name carrying parentheses of its
own survives, and drops every other line — `ToolRunner` merges standard error into the output. The
identifier, not the name, is the shortcut's identity: it survives a rename in Shortcuts, so an alias
or a binding follows the shortcut rather than its old title. The entry id is
`apple-shortcut:<uuid>`, with no bundle id, so shortcuts never share a `preferenceKey` with the
Shortcuts app itself.

The list is re-read when the Settings pane appears, when the switch turns on, and when the launcher
opens more than 15 s after the last successful read (`AppIndex.rescanInterval`; a launcher open
inside that window keeps the library it has, and a library dropped by switching the feature off never
counts as fresh). The tool answers in ~10 ms, so an overlapping request is simply dropped rather than
queued. An unchanged list publishes nothing.

## Sweeping deleted shortcuts

A read that differs from the last one — and the first read after launch, so a shortcut deleted while
Tinycast wasn't running is caught too — sweeps. `AppleShortcut.staleIDs` collects every
`apple-shortcut:` key the alias, visibility and ranking stores hold, plus
`boundAppleShortcutIDs`, and returns those the library no longer names. Each is unbound and its
per-entry preferences removed. A shortcut renamed in Shortcuts keeps its UUID, so a rename is never a
deletion.

**An empty read never sweeps.** Deleting every shortcut and a tool that answers with an empty list
look identical, and guessing wrong would free every binding at once. The cost is that the last
shortcut's references linger until the library holds one again.

## Running

`shortcuts run <uuid>` runs the shortcut headless. The palette hides first and hands focus back, since
a shortcut usually acts on the app the user was in. There is **no timeout** — a shortcut can wait on a
dialog of its own for as long as it likes. Success is silent; a non-zero exit shows the tool's last
lines in Tinycast's own dialog.

**A shortcut's shell actions run in Shortcuts' own helper**, which exports
`DIRHELPER_USER_DIR_SUFFIX=com.apple.shortcuts.mac-helper`, so an app such an action opens inherits a
per-user temp folder (`…/T/com.apple.shortcuts.mac-helper/`) whose socket paths overrun macOS's
104-byte limit — OpenCode's SSH failed exactly so. Tinycast's own environment cannot reach inside a
shortcut, so the pane's footer tells the user to start such an action with
`unset DIRHELPER_USER_DIR_SUFFIX; export TMPDIR="$(getconf DARWIN_USER_TEMP_DIR)"`. A shortcut that
is only a shell action belongs in the [command folder](command-folder.md) instead, which runs it
under Tinycast's own environment. Tinycast itself,
when a shortcut relaunches it through `install.sh`, adopts the Dock's environment at startup
(`InheritedEnvironment`, [architecture.md](../architecture.md#entry-points-and-windows)).

## Launcher and Settings

`AppEntry.Kind.appleShortcut` is its own section, published right after Applications. It is file-backed
rather than a symbol tile: every row's `url` is Shortcuts.app, so each draws that app's icon from one
cached bitmap. Reveal in Finder is refused, because the file is the app, not the shortcut.

The pane lists rows through `LauncherItemsList`, the same table the launcher-category panes use: icon,
name, alias, shortcut recorder and the checkbox that hides one row from launcher search while its
shortcut keeps working. Its filter is membership in `AppIndex.matches`, so it answers to aliases.

`HotKeyAction.appleShortcut(id:)` persists under `hotkey.appleShortcut.<uuid>` with a
`boundAppleShortcutIDs` index. `appleShortcutsEnabled` rides in settings backups, since running a
shortcut the user built grants no permission class. Bindings are not in
`HotkeyBackup`.

## Standalone harness

```sh
./scripts/run-tests.sh apple-shortcut-test
```
