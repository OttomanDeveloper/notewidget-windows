# Changelog

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