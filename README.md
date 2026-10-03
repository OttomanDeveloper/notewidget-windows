<p align="center">
  <img src="assets/brand/winnotes_wordmark_light_800x240.png" alt="WinNotes" width="400">
</p>

<p align="center">
  Desktop notes that stay on the screen and come back by themselves.<br>
  Windows 11 Pro. Nothing leaves this PC.
</p>

---

WinNotes is a notes widget for Windows 11. It fills the one gap between
Microsoft Sticky Notes and an Android widget: Sticky Notes is a good app trapped
inside an ordinary window, so it gets covered, gets closed, and never returns on
its own. On a phone, notes live on the home screen and survive everything.
WinNotes is that idea, built for Windows.

There is no account, no sign-up, no server, no cloud and no sync. Every note is
one plain-text file in your own profile folder.

## Two surfaces

**The widget** is a frameless window that sits on the desktop, above ordinary
windows, with no title bar and no taskbar button. Clicking it never steals the
caret from whatever you are typing in. It survives every restart.

**The editor** is an ordinary window with an ordinary title bar, because it is
the one surface you are deliberately looking at. You ask for it; it never appears
on its own at boot.

Neither is more real than the other. They are two views of the same notes.

## Running it

```
flutter pub get
flutter run -d windows
```

Release build:

```
flutter build windows --release
```

Output lands in `build/windows/x64/runner/Release/`.

There is no install step. Copying that folder anywhere on the machine is a
complete installation, and Settings → Startup will point the autostart entry at
wherever it actually lives.

## What it does

- **Notes** are a title and a body. Nothing else, ever. They sort by most
  recently edited and search covers titles and bodies, filtering as you type.
- **Writing is immediate.** There is no save button. Changes are written as they
  are typed, debounced by a fraction of a second so a burst of keystrokes costs
  one write rather than one per character.
- **The widget comes back by itself** after every restart, via one entry under
  the per-user `Run` key. No administrator rights, and it shows up in Task
  Manager → Startup like any other app.
- **`Ctrl+Alt+N`** opens the editor from any application, full-screen ones
  included. Changeable in Settings, and a collision with another app's shortcut
  is reported rather than silently ignored.
- **The tray icon is the app's home.** Show or hide the widget, open the editor,
  quit. Quit is the only thing that ends the app, and it asks first.
- **Acrylic backdrop**, so the widget picks up the wallpaper the way native
  Windows 11 surfaces do, falling back to a plain translucent surface where
  Windows cannot provide it.
- **Per-monitor position.** The widget returns to the screen you left it on. If
  that monitor is unplugged, it comes back on the nearest remaining one instead
  of somewhere it can never be clicked again.
- **Plain-text export and import.** The format is deliberately boring, so a
  backup taken years from now is still readable without this app.

## Where the notes live

`%APPDATA%\WinNotes\`

| File | Written by | Purpose |
| --- | --- | --- |
| `notes.json` | the editor | Every note. The only file that matters. |
| `settings.json` | the editor | Appearance, startup, hotkey, storage location. |
| `widget_state.json` | the widget | Where the widget was left, and on which monitor. |
| `selection.json` | either | Which note is focused. |

One writer per file. That is the whole concurrency story: there is no merge
logic anywhere in this project, because there is never a moment when two
surfaces write the same file.

`notes.json` is written whole, via a temporary file and an atomic replace, so a
kill mid-sentence cannot leave it half-written.

**If `notes.json` cannot be read, WinNotes refuses to start** rather than
replacing it with an empty list, and says so on a screen offering a restore. Every
write is blocked while that is true. Notes that were never read are worse than
notes that take a moment longer to open.

You can open, read, back up, edit or delete any of these in Notepad while the app
is running.

## The logo

Deep indigo plate, off-white note card, a coral caret. The caret is the accent
because it is the part of the mark that means *being written right now*.

| File | Use |
| --- | --- |
| `assets/brand/winnotes_mark.svg` | Primary mark. 1024 master grid. |
| `assets/brand/winnotes_mark_small.svg` | Small-size mark, for 16-32px. |
| `assets/brand/winnotes_tray_light.ico` | Tray, light taskbar. |
| `assets/brand/winnotes_tray_dark.ico` | Tray, dark taskbar. |
| `assets/brand/winnotes_wordmark*.svg` | Lockups, light and dark surfaces. |
| `assets/brand/winnotes.ico` | App icon, 256 down to 16. |

Regenerate every derived file from the SVG masters:

```
pwsh -File tool/brand/generate_assets.ps1
```

The script rasterises with headless Chrome and packs the `.ico` files itself.
It also **verifies every icon frame** by re-reading each embedded PNG's IHDR
header and comparing its real dimensions against the directory entry, because a
malformed entry produces a file that looks fine and renders as garbage at one
specific size.

Two details worth knowing if you edit the artwork:

- **Small sizes are redrawn, not scaled.** `winnotes_mark_small.svg` is a
  separately drawn, much heavier mark. The full-detail master turns to mush
  below 32px.
- **Both wordmarks ship.** The near-white-on-dark lockup is invisible on a white
  page, so a light-surface variant exists for docs.

## Layout

```
lib/
  main.dart                  entry for both surfaces
  src/
    core/                    paths, atomic JSON file with debounce and watch
    data/                    note model, repositories, backup format
    platform/                typed wrapper over the runner's method channel
    state/                   notes, settings and widget controllers
    ui/
      editor/                the editor window
      widget/                the widget window
      settings/              the settings dialog
      common/                confirm dialog, undo toast, empty states
windows/runner/              native host: windows, tray, hotkey, autostart
assets/brand/                logo sources and derived assets
tool/brand/                  asset generator
test/                        100 tests
```

### How the two windows work

Each surface is a separate top-level Win32 window with its own Flutter engine and
its own Dart isolate. Both call the same `main()`; a `--surface` argument decides
which one is running.

They do not talk to each other directly. They share files: the editor writes
`notes.json`, the widget watches it and re-reads on change. That is why there is
no cross-isolate merge code, and why it is impossible for the two to disagree
about a note.

The native layer owns everything Windows-shaped: frameless layered windows, the
acrylic backdrop, the tray icon, the global hotkey, the registry entry, and
single-instance behaviour. `window_manager`-style plugins were not used, so the
behaviours above are implemented directly against Win32 and can be tested by
reading the code rather than by trusting a dependency.

## Tests

```
flutter test
```

100 tests covering the parts where being wrong loses data: atomic writes and
concurrent readers, the refusal to overwrite unreadable notes, undo ordering,
search, the plain-text backup format including bodies that contain a divider,
settings validation and clamping, and the widget's card rendering.

## Deliberately not built

No accounts, no sync, no Markdown, no folders, no tags, no reminders, no due
dates, no encryption, no network code of any kind.

`PROJECT.md` is the design document, including a section on things that were
considered and left out, and why.