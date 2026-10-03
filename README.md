<div align="center">
  <img src="assets/brand/winnotes_wordmark_800x240.svg" alt="WinNotes" width="420" />

  <p><strong>Desktop notes that stay on your screen and come back on every boot.</strong></p>

  <p>
    <a href="#what-it-does">What it does</a> •
    <a href="#why-not-sticky-notes">Why</a> •
    <a href="#features">Features</a> •
    <a href="#privacy">Privacy</a> •
    <a href="#build">Build</a> •
    <a href="PROJECT.md">Design doc</a>
  </p>
</div>

---

**WinNotes** is a desktop notes widget for **Windows 11 Pro**. A frameless note
floats on top of your desktop, and it reappears by itself every time the PC
boots.

It fills the one gap between Microsoft Sticky Notes and an Android home-screen
widget. Sticky Notes is a genuinely good app trapped inside an ordinary window,
so it gets covered, gets closed, and never comes back on its own. On a phone,
notes live on the home screen and survive everything. WinNotes is that same idea,
built for Windows.

Built with **Flutter** and a native **Win32** runner. No account, no server, no
network code at all.

## What it does

Two surfaces, one set of notes:

| Surface | What it is |
| --- | --- |
| **The widget** | A frameless, transparent, always-on-top overlay window on the desktop. No title bar, no taskbar button. It never steals focus while you type. |
| **The editor** | An ordinary window that appears only when you ask for it (`Ctrl+Alt+N` from anywhere, including full-screen apps). List on one side, editor on the other. |

Notes are plain text with a separate title line, written to disk the moment you
type. There is no save button, because there is no save step to miss.

## Why not just Sticky Notes?

Sticky Notes already exists, is free, and is good. It cannot do the two things
WinNotes is built around:

1. **It vanishes when you close it.**
2. **It never comes back on its own after a reboot.**

WinNotes closes its windows without ending the app, and registers a per-user
`Run` entry so the widget comes back after every restart. Quitting is explicit
and lives only in the tray menu, where it asks first.

## Features

- **Always-on-top widget** — frameless and transparent, holds its place above
  ordinary windows without stealing the caret mid-sentence.
- **Docks to the nearest screen edge** by default, and stays where you drag it
  across restarts. Resizable from any corner.
- **Per-monitor position** — it returns to the monitor you left it on. Unplug
  that monitor and it moves to the nearest remaining screen instead of
  disappearing somewhere you can never click it again.
- **Autostart that you can see** — one entry under the per-user `Run` key. No
  admin rights, and it shows up in Task Manager → Startup where you can disable
  it the way you would any other app. The toggle removes the entry rather than
  leaving it disabled somewhere.
- **Global hotkey** — `Ctrl+Alt+N` by default, changeable in Settings, and the
  app tells you if another program already claimed the combination.
- **Tray menu** — show/hide the widget, open the editor, open Settings, quit.
  Closing a window never ends the app.
- **Single instance** — launching it again raises the existing widget instead of
  stacking a second copy on top.
- **Search** — matches title and body, filters as you type.
- **Plain-text export/import** — deliberately boring format so a backup taken
  years from now is still readable without this app.
- **Theme follows Windows** — Light, Dark, or System, with an acrylic backdrop
  behind the widget that picks up your wallpaper and taskbar. Falls back to a
  plain translucent surface where Windows cannot provide it.
- **Respects reduced motion** when Windows reports it.

## Privacy

WinNotes has **no network code**. No telemetry, no analytics, no update check, no
crash upload — which also means nobody to send your data to and nobody to call
for help.

Every note is a plain-text file on your PC, at `%APPDATA%\WinNotes\notes.json`,
in your own user profile folder:

```
%APPDATA%\WinNotes\
├── notes.json          ← your notes, one file you can read or delete
├── settings.json       ← appearance, startup, hotkey, storage location
├── widget_state.json   ← where the widget was left, and on which monitor
└── selection.json      ← which note is focused, shared by both surfaces
```

Notes are written on change with a short debounce, via a write-temp-then-rename,
so a half-finished write can never leave the notes broken. **If the file is
unreadable or not valid JSON, the app refuses to start rather than overwriting
notes it never read** — and offers the file as an import target so you can
restore a backup by hand.

Losing notes is possible in exactly one way: deleting that folder by hand, the
same as any local app. Nothing in the app destroys a note without being asked.

## Build

Requires **Flutter** with the **Windows** desktop toolchain and **Visual Studio
2022** with the *Desktop development with C++* workload.

```bash
git clone https://github.com/OttomanDeveloper/notewidget-windows
cd notewidget-windows
flutter pub get
flutter run -d windows
```

Release build:

```bash
flutter build windows --release
```

The executable lands in `build\windows\x64\runner\Release\win_notes.exe`. To make
the widget survive a reboot, point the autostart entry at the *installed* copy
(under `%LOCALAPPDATA%\Programs`), not at the build directory — the in-app
toggle does this for you once the app is running from an install.

Run the tests with:

```bash
flutter test
```

### Project layout

```
lib/
├── main.dart                 # one entrypoint, both surfaces
└── src/
    ├── core/                 # app paths, atomic JSON writes
    ├── data/                 # Note, repositories, settings, backup format
    ├── platform/             # Dart side of the runner channel
    ├── state/                # notes / settings / widget controllers
    └── ui/                   # editor, widget, settings, theme
windows/runner/               # native Win32 host: windows, tray, hotkey, acrylic
tool/brand/                   # icon and wordmark generation
```

The native runner creates **two Windows windows**, each with its own Flutter
engine and isolate, and both call `main()`. A `--surface` argument decides which
one is booting, so there is no second entrypoint to keep in sync.

## Not included, on purpose

No due dates, reminders, priorities, or projects. No folders, tags, backlinks,
markdown, or formatting toolbar. No clipboard watching, no screen annotation, no
share links. No encryption at rest — notes sit in your own profile folder, which
Windows already protects with your account password, so a second layer would
only add a key to store, back up, and lose.

If you need notes that hold genuinely sensitive material, encryption becomes the
first thing to build, and it should be built properly rather than bolted on.

See [PROJECT.md](PROJECT.md) for the full design rationale, the open decisions,
and what is planned next (multiple widgets at once, desktop layer mode via
`SetParent`, note pinning, Markdown export).

## Status

Early and actively developed. The feature set described in `PROJECT.md` is the
target; see the git history and open issues for where it actually is.

## License

MIT — see [LICENSE](LICENSE).