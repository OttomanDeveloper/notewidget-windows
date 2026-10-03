# Changelog

## Unreleased

### Fixed

- **The widget can be dragged again.** 1.1.0 shipped the position lock switched
  on by default, which meant the widget could not be moved at all unless you
  found a switch in Settings. Dragging now works out of the box and the lock is
  opt-in, for when the widget is parked somewhere you want it to stay.
- **A locked widget now says so.** Dragging one used to do nothing whatsoever,
  with nothing on screen to suggest the lock was the reason. It now shows a short
  hint naming both the state and where to change it, and only after someone has
  actually tried to drag, so it never nags anyone who has not.

### Added

- **Downloadable releases.** Every tagged version publishes a portable ZIP and a
  per-user `setup.exe` to the Releases page. Pushing a `v*` tag is all it takes:
  the workflow checks the tag against `pubspec.yaml`, runs the tests, builds,
  launches the staged build to prove it starts, verifies the ZIP really contains
  the Flutter engine, and compiles the installer. If any of that fails, nothing
  is published.
- **The installer asks for no administrator rights.** It installs into
  `%LOCALAPPDATA%\Programs\WinNotes` rather than Program Files, because the app
  keeps its notes in `%APPDATA%` and its startup entry under `HKCU`, and its
  whole promise is that it needs no elevation. Uninstalling removes the program
  and the startup entry, and never touches your notes.
- **A structured bug report form**, and [ISSUE_REPORTING.md] explaining what to
  include — particularly why trying a fresh `%APPDATA%\WinNotes` first, and why
  pasting `notes.json` after checking it, is worth more than anything else in a
  report.
- **[CONTRIBUTING.md]**, covering the build setup, the two design rules most
  mistakes break, and how a release is cut.
- **Lock the widget in place.** New switch in Settings → Widget, on by default.
  While it is on, dragging the widget does nothing, so a stray drag across the
  card cannot move a widget that was deliberately placed. Turning it off makes
  the widget draggable again straight away, with no restart: the widget watches
  `settings.json`, so the change reaches the window as it is made. Resizing from
  a corner is unaffected, because locking is about position, not size.
- **A dedicated Widget settings group.** "Keep the widget above other windows"
  moves here from Appearance, so the two switches about where the widget sits
  and whether it gets in the way are described together. `alwaysOnTop` itself is
  unchanged and still defaults to on.

### Changed

- The widget is draggable by default again. 1.1.0 made "Lock the widget in
  place" default to on, which removed dragging altogether rather than merely
  guarding against accidental drags.
- The version reported by the executable was `0.1.0` while the changelog claimed
  `1.0.0`. `pubspec.yaml` is now the single source of truth, and the release
  workflow fails if the tag disagrees with it.

### Fixed

- **The test suite left a temporary directory behind on most runs.**
  `AtomicJsonFile` creates its parent directory before every write, so a write
  still queued when `tearDown` deleted the temp folder would recreate it a moment
  later. Every test stayed green and about 18 folders accumulated per run, in
  the developer's `%TEMP%` and on every CI run. Controllers are now drained
  before the directory is removed.
- **The tray menu no longer advertises a shortcut that did nothing.** It
  labelled Settings as `Ctrl+Alt+S`, which was never registered with Windows —
  only `Ctrl+Alt+N` is, and that one is changeable and can be switched off. Both
  entries now print no accelerator at all, because any shortcut printed there
  would go stale the moment it was changed.
- **A failed write no longer disables saving for the rest of the session.**
  Replacing a file on Windows fails outright whenever Search Indexer, antivirus
  or a backup tool happens to hold the destination open, which happens routinely
  on a live desktop. That failure was being treated as unreadable data: every
  subsequent write became a no-op and the app showed the "these notes are
  corrupt, we will not overwrite them" screen. One moment of antivirus
  interference could therefore cost every edit for the rest of the session.
  A write that could not land now keeps its value queued and retries with
  backoff. Only a genuinely unreadable file stops writes.
- **Editing a note always moves it to the top of the list.** The clock has
  millisecond resolution and the ordering tie-breaks by id, which is random, so
  editing a note in the same millisecond another note was last touched left the
  edited note second instead of first. Timestamps now step past the current
  newest, making it an invariant rather than a coin flip. This also stopped the
  widget from showing the note you were looking at as its large card.
- **Test flakiness.** Two tests asserted on the exact millisecond a write landed
  and on ordering that depended on the clock, so they failed intermittently
  under parallel test runs.

## 1.0.0

First release. Windows 11 Pro, Flutter, no third-party runtime dependencies.

### Added

- **Notes.** Title and body, nothing else. Most-recently-edited ordering with a
  stable tie-break. Search across titles and bodies, filtering as you type.
- **Widget.** Frameless, layered, always-on-top window with no taskbar button.
  Acrylic backdrop over the wallpaper where Windows provides it, plain
  translucent surface where it does not. Never takes focus when clicked.
  Draggable, resizable from any corner, remembers its monitor and position.
  Multiple notes in one scrolling column: the focused note is rendered large,
  the rest compact.
- **Editor.** Two panes, or one at a time on a narrow window. Plain text, no
  toolbar, no save button. Search with `Ctrl+F`.
- **Delete with undo.** Confirmation first, then a six-second undo that puts the
  note back in its original position.
- **Storage.** One `notes.json`, written whole and atomically, debounced by
  250ms with a ceiling so continuous typing still reaches disk.
- **Refusal to overwrite unreadable notes.** An unreadable or non-WinNotes file
  blocks every write and produces a screen offering a restore, rather than
  starting with an empty list.
- **Plain-text export and import**, readable without this app.
- **Autostart** through one per-user `Run` key entry, with a configurable delay
  that applies to autostart only.
- **Global hotkey**, `Ctrl+Alt+N` by default, with collision detection reported
  in Settings rather than silently ignored.
- **Tray icon** matching the taskbar theme, with show/hide widget, open editor,
  settings and quit. Quit is the only exit and it confirms first.
- **Single instance.** A second launch raises the existing surfaces instead of
  stacking a duplicate.
- **Per-monitor recovery.** If the monitor holding the widget is unplugged, it
  returns to the nearest remaining screen rather than off-screen.
- **Settings** in four flat groups: appearance, startup, hotkey, storage.
- **Light, dark and system themes**, following Windows by default.
- **Reduced motion** respected when Windows reports animation is off.
- **Logo**, generated from SVG masters with every `.ico` frame verified.

### Notes on the build

Zero runtime dependencies. The native host owns the windows, tray, hotkey,
registry entry and acrylic directly against Win32 rather than through plugins, so
the behaviour above is verifiable by reading the code. The two Flutter surfaces
share state through files with one writer per file, which removes cross-isolate
merge logic entirely.