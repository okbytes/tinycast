# Command Folder

A folder of files, each a launcher command: a shell script or any executable runs, a `.url` or
`.link` file holding one address opens. The files are the whole definition — there is no editor, no
argument, no placeholder and no output window — so a command is made in an editor and turned off with
the launcher checkbox every item carries. It replaced the Quicklinks and Custom Commands features,
which carried editors, templates and output surfaces that a folder makes unnecessary.

There is no switch. The folder is `~/.config/tinycast/commands/` (`tinycast-dev` on the dev channel)
until **Settings › Command Folder › Choose…** names another; an iCloud-synced folder makes one set of
commands serve every Mac. A missing folder is an empty section, and **Show in Finder** creates it on
the way.

## Invariants

- **The file name is the identity.** The entry id is `folder-command:<file name>`, so an alias, a
  binding, a hidden checkbox and ranking follow the file, and a renamed file is a new command.
- **`run(id:)` is the single funnel** for a launcher row and a global shortcut alike, and it runs
  only a command the last read found.
- **An unreadable folder keeps the last good read**; an empty one is a real reading and frees
  everything it once held. Unlike Apple Shortcuts there is no tool that can answer "empty" by
  mistake: the folder either lists or it does not.
- **A script runs in a login shell, under Tinycast's own environment.** Tinycast launches with
  launchd's variables ([architecture.md](../architecture.md#entry-points-and-windows)), and
  `/bin/zsh -l` adds the user's `PATH` from `/etc/zprofile` and `~/.zprofile`, so `zed` and
  Homebrew's tools resolve as they do in Terminal. Nothing from Shortcuts' helper is in the way.
- **`Model/` stays Foundation-only and pure** for `folder-command-test`: the scanner hands it a
  listing, and it decides what each file makes.

## Discovery

`CommandFolderScanner.scan` lists the folder off main and reads one line of each link file, handing
`FolderCommand.commands(from:)` a `File` per regular file (symlinks followed, so a linked script
counts and a linked folder does not). The model keeps:

| File | Command |
| --- | --- |
| executable, any name | a script, run with `exec` so its shebang decides the interpreter |
| `.sh` `.zsh` `.bash` `.command`, executable or not | a script, read by zsh |
| `.url` `.link`, first non-empty line a URL with a scheme | a link, opened by the scheme's handler |
| hidden (`.…`), a folder, anything else | nothing |

The name is the file name without its extension, exactly as written: `chatgpt.link` is "chatgpt"
and `Open Jira.url` is "Open Jira". A link needs a scheme because a bare domain would open nothing.

`CommandFolderMonitor` watches the folder with a `DispatchSource`, reopening it after every event
and polling every 2 s only while it is missing, and reports once writes settle for 300 ms. The folder
is also re-read when the pane appears and on a launcher open past `AppIndex.rescanInterval`, the
app scan's own rule. An unchanged read publishes nothing.

A file that is gone from a successful read frees what it held: its alias, hidden state, ranking and
binding, through `FolderCommand.staleIDs` over the stores' keys and `boundFolderCommandIDs`.

## Running

A link hides the palette without restoring focus and hands the URL to `AppLauncher.open`. A script
hides the palette with focus restored, since a script usually acts on the app the user was in, then
`FolderCommandRunner` runs it in the home directory through `ToolRunner`: an executable as
`zsh -lc 'exec "$0"' <file>`, anything else as `zsh -l <file>`. There is **no timeout**; success is
silent and a non-zero exit shows the tool's last lines in Tinycast's own dialog. A script reads the
clipboard with `pbpaste` and writes it with `pbcopy`; nothing is piped in.

## Launcher and Settings

`AppEntry.Kind.folderCommand` is its own section, "Command Folder", published after Apple
Shortcuts. Rows are symbol tiles — `terminal` for a script, `link` for a link, decided from the file
name — and each entry's `url` is the file, so Reveal in Finder opens the folder on it.

The pane lists rows through `LauncherItemsList`, the same table the Apple Shortcuts pane uses: icon,
name, alias, shortcut recorder and the checkbox that hides a row from launcher search while its
shortcut keeps working. `HotKeyAction.folderCommand(id:)` persists under
`hotkey.folderCommand.<file name>` with a `boundFolderCommandIDs` index, the per-item case
[hotkeys.md](hotkeys.md) describes for shortcuts. `commandFolder`, the chosen path kept
`~`-relative, rides in settings backups and in the settings file as `commandFolder.path`; the files
themselves are not carried.

## Testing

`Tests/folder-command-test.swift` covers which files make commands, the display name, link
validation, entry ids, glyphs and the sweep, including that an empty folder frees everything.
