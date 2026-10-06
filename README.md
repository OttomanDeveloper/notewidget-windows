<p align="center">
  <img src="assets/brand/winnotes_wordmark_light_800x240.png" alt="WinNotes" width="400">
</p>

<p align="center">
  Desktop notes that stay on the screen and come back by themselves.<br>
  Windows 11 Pro. Nothing leaves this PC.
</p>

<p align="center">
  <img src="docs/images/hero.png" alt="The WinNotes editor window beside the always-on-top widget, both showing the same notes" width="900">
</p>

---

Microsoft Sticky Notes is a good app trapped inside an ordinary window, so it gets
covered, gets closed, and never returns on its own. On a phone, notes live on the
home screen and survive everything. WinNotes is that idea, built for Windows.

No account, no sign-up, no server, no cloud, no sync. Your notes are one plain
file in your own profile folder.

## Download

Grab the latest from
**[the Releases page](https://github.com/OttomanDeveloper/notewidget-windows/releases)**.

| Download | What it is |
| --- | --- |
| `WinNotes-<version>-windows-x64.zip` | Portable. Unzip anywhere and run `win_notes.exe`. |
| `WinNotes-<version>-setup.exe` | Installs per-user into `%LOCALAPPDATA%\Programs\WinNotes`, adds a Start menu entry, and offers a startup entry. |

The installer asks for **no administrator rights** — the app never needs any. Its
notes live in your profile folder and its startup entry is under your own account.

**Releases are not code-signed**, so SmartScreen shows *"Windows protected your
PC"* on first run. Choose **More info → Run anyway**. That is normal for an
unsigned open-source build. Prefer not to? Build it yourself below.

**Upgrading** installs over the old version. Notes and settings live in
`%APPDATA%`, not in the program folder, so they are untouched.

**Uninstalling** removes the program and the startup entry, never your notes.
They are in `%APPDATA%\WinNotes` and belong to you.

## Features

### The widget

- **Stays on screen, above other windows.** Always-on-top, acrylic backdrop, no
  title bar, no taskbar button. Steps aside while the editor is in use, and
  floats again when you leave it.
- **Comes back by itself after every restart.** One entry under the per-user `Run`
  key. No administrator rights, and it appears in Task Manager → Startup like any
  other app.
- **Draggable and resizable**, from anywhere on the card or any corner, and it
  remembers which monitor you left it on. If that monitor is unplugged it comes
  back on the nearest remaining one.
- **Write a note without leaving what you were doing.** The circle in the
  bottom-right corner turns into a text field in the same spot. Enter saves,
  Escape throws it away. The first line becomes the title.
- **One large card, the rest compact.** The large card prefers notes you have not
  finished, so ticking one off moves on to the next instead of leaving a line
  through the thing you are looking at.
- **Clicking never steals your caret.** The window is `WS_EX_NOACTIVATE`, so
  clicking the widget never pulls the caret out of whatever you are typing in —
  except while you are writing a note in it, which is the point.

### Notes

- **A title and a body.** They sort by most recently edited, and search covers
  both as you type.
- **Mark one done** from the widget or the editor. A circle on every card and
  every row, plus `Ctrl+D`. Marking a note done deliberately does *not* count as
  editing it, so the list does not jump around as you work through it.
- **Markdown, per note.** A switch beside the title turns it on for that note;
  the body becomes a source field with a rendered preview beside it. Headings,
  lists including task lists, quotes, code blocks, bold, italic, strikethrough,
  links and tables. Off by default, and **what you typed is never rewritten** —
  the export still exports it and turning it off gives your asterisks back.
- **Written as you type.** No save button. A burst of keystrokes costs one write
  rather than one per character, and a burst that never pauses still lands within
  1.5 seconds.
- **Plain-text export and import.** Deliberately boring, so a backup taken years
  from now is still readable without this app.

### The app

- **An ordinary window, because it is the one you are deliberately looking at.**
  Real title bar, resizes from any edge, will not go below 520 × 360.
- **`Ctrl+Alt+N`** opens it from any application, full-screen ones included.
  Changeable in Settings; a collision with another app's shortcut is reported
  rather than silently ignored.
- **Nine colour schemes.** Picking one changes the accent *and* the surfaces built
  around it, in both windows, immediately. `Coral` is the original and still the
  default; `Graphite` is nearly grey.
- **The tray icon is the app's home.** Show or hide the widget, open the editor,
  quit. Quitting asks first.
- **A failed write never costs you a note.** Antivirus or a backup tool holding
  the file is retried rather than mistaken for unreadable notes.

## Settings

Opens from the tray icon or the editor's ⋮ menu. Everything applies immediately —
no restart.

| Setting | Default | What it does |
| --- | --- | --- |
| **Keep the widget above other windows** | On | Stays on top of ordinary windows. It never covers the editor. |
| **Lock the widget in place** | Off | Dragging does nothing, so it stays where you put it. A locked widget says so rather than silently ignoring you. Resizing still works. |
| **Colour** | Coral | One of nine schemes. A curated list rather than a free picker, because these surfaces float over an arbitrary wallpaper and a swatch you could pick might not be readable. |
| **Hotkey** | `Ctrl+Alt+N` | Opens the editor from anywhere. |

## Your notes

`%APPDATA%\WinNotes\`

| File | What it is |
| --- | --- |
| `notes.json` | Every note. The only file that matters. |
| `notes.json.bak` | The previous good version, kept automatically. |
| `settings.json` | Appearance, hotkey, storage location. |
| `widget_state.json` | Where the widget was left, and on which monitor. |

**If `notes.json` cannot be read, WinNotes stops rather than starting with an empty
list.** Notes that were never read are worse than notes that take a moment longer
to open, and every write is blocked meanwhile so nothing can overwrite a file the
app has not managed to read.

It is not stuck. The screen offers whatever is worth trying:

| What you see | What it means | What to press |
| --- | --- | --- |
| *Something is holding your notes file* | Antivirus, a backup tool or a sync client has it open. Your notes are almost certainly fine. | **Try again** — it opens the moment the file is let go. |
| *Your notes file could not be read* | The content is wrong. Writes are atomic, so WinNotes cannot have caused it. | **Restore the previous version** from `notes.json.bak`, or **Start fresh instead**. |

**Start fresh never deletes anything.** The unreadable file is renamed to
`notes.json.broken-<timestamp>` beside a new empty one, so the damaged content is
still there if you want it.

A **deleted** file is not a problem: a missing file is a first run. Every write
goes through a temporary file and an atomic replace, so being killed mid-sentence
cannot leave it half-written — and nothing here holds a lock, so you can copy your
notes out while the app runs. Hand-editing is the sharp edge: `notes.json` belongs
to the editor, so an edit made in Notepad while it is open will be overwritten.
Close it first, or use the in-app export.

## Build it from source

```
git clone https://github.com/OttomanDeveloper/notewidget-windows.git
cd notewidget-windows
flutter pub get
flutter test          # 389 tests
flutter run -d windows
```

Requires **Flutter 3.47.5** or newer on the stable channel. To produce the
artifacts a release publishes:

```
flutter build windows --release
pwsh -File tool/release/package.ps1
```

That writes the portable ZIP and compiles `setup.exe` with
[Inno Setup](https://jrsoftware.org/isinfo.php).

To cut a release, bump `version:` in `pubspec.yaml`, push, and tag that commit
`v<version>`. The [release workflow](.github/workflows/release.yml) checks the tag
matches, runs the tests, builds, launches the staged build to prove it starts,
verifies the ZIP, compiles the installer, and publishes. Nothing is published from
a branch.

## Not built

No accounts, no sync, no folders, no tags, no reminders, no due dates, no
encryption, no network code of any kind.

**[PROJECT.md](PROJECT.md)** is the design document, including a section on things
that were considered and left out, and why.

## Reporting a bug

Use the **Report a bug** button on the
[issues page](https://github.com/OttomanDeveloper/notewidget-windows/issues).

Two things help more than anything else:

- **Try a fresh profile first.** Close WinNotes, rename `%APPDATA%\WinNotes` to
  `WinNotes.old`, and launch again. That one step tells us whether it is a data
  problem or a code problem.
- **Paste `notes.json`**, having removed anything you would not want published. It
  is plain JSON and reproduces the exact state the app was in. Issues are public
  the moment you submit.

**[ISSUE_REPORTING.md](ISSUE_REPORTING.md)** covers the rest, including how to
report a security problem privately.

## Contributing

Patches are welcome — see **[CONTRIBUTING.md](CONTRIBUTING.md)** for the build
setup, the design rules most mistakes break, and how releases are cut.

Read **[AGENTS.md](AGENTS.md)** before changing anything. It is one page and points
at the docs worth your time:

| Doc | What it covers |
| --- | --- |
| [storage](docs/storage_pattern.md) | One writer per file, atomic replace, recovery that never destroys |
| [widget](docs/widget_pattern.md) | Why the widget hit-tests as `HTCLIENT` everywhere, how it borrows the keyboard, how Markdown is budgeted |
| [provider](docs/provider_pattern.md) | Where state lives, `watch` vs `read` vs `select`, and why `setState` is gone |
| [isolate](docs/isolate_pattern.md) | The two surfaces, who writes each file, and the flush-on-teardown hazard |
| [platform](docs/platform_pattern.md) | The 28 Dart-to-runner methods and what each one does on failure |
| [testing](docs/testing_pattern.md) | What the 465 tests are allowed to claim, and the traps that have already cost time |
| [rulebook](docs/flutter_architecture_pattern.md) | The architecture, performance and Riverpod rules this app is built to, and where each one is checked |

Each ends with a table naming the tests that pin its rules.

## Layout

```
lib/core/             theme, paths, atomic files, runner channel, shared widgets
lib/features/notes/   note model, repositories, providers, editor screens + widgets
lib/features/widget/  widget state, provider, surface screens + widgets
lib/features/settings/ settings model, provider, dialog screens + widgets
lib/main.dart         both isolates' entry point, one ProviderScope each
windows/runner/       native host: windows, tray, hotkey, autostart
installer/            setup.exe definition
test/architecture/    guards that check the rules rather than behaviour
tool/check_architecture.ps1   the file-size and widget-privacy caps, standalone
```

Two surfaces, two Flutter engines, two Dart isolates. They share files and never
talk to each other directly, so there is no merge logic anywhere and they cannot
disagree about a note. Everything Windows-shaped is hand-written against Win32
rather than taken from a plugin, which is why it can be read and tested rather
than trusted.

## Licence

MIT. See [LICENSE](LICENSE).