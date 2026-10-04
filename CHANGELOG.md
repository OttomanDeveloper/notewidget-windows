# Changelog

## Unreleased

### Added

- **Add a note from the widget.** A small circle in the bottom-right corner,
  nearly invisible until you move the pointer over the widget, turns into a text
  field in the same spot. Type, press Enter, and the note is there. Escape or the
  cross closes it without saving. One slot that changes rather than a button
  that reveals a panel somewhere else, so there is nothing to hunt for and
  nothing new to remember — and because it lives in the bottom strip it never
  disturbs the cards, which is what the widget is for. Faint rather than absent
  when you are not hovering, because a control that only exists on hover is one
  half the people who could use it will never find.
- **The widget can be typed into, which it could not before.** The widget window
  is `WS_EX_NOACTIVATE` so that clicking it never pulls the caret out of whatever
  you are typing into — and that is also why it could never contain a text
  field. Rather than give that up for good, the flag is dropped for exactly as
  long as the composer is open and put straight back afterwards, along with the
  keyboard: the window that had focus before gets it back. An always-on-top
  widget that stole focus permanently would be unusable, and one that could never
  take it could not be typed into. `WM_MOUSEACTIVATE` had to stop refusing
  activation too, which was the same problem one layer down.
- **Escape closes the composer.** A text field that cannot be dismissed from the
  keyboard traps the keyboard, and this one is holding it. Clicking away does not
  help, because the widget has focus precisely so that typing works.

### Changed

- **A note written in the widget's composer does not become a second thing to
  fill in.** The first line becomes the title and the rest the body, which is the
  shape the widget already displays — a line, then a preview — so a note jotted
  on the desktop looks like a note written in the editor. It lands at the top of
  the list, being the most recent thing in it, but it does not steal the editor's
  selection: you are looking at the widget, and moving the editor's cursor out
  from under you would be a worse surprise than the note appearing quietly.
- **A note with a title and no body no longer says "No text yet".** Its content
  is on screen in the line above, so claiming otherwise is just wrong — and it is
  the shape every note added from the widget's composer takes, since one line of
  typing becomes the title. "No text yet" is now reserved for a note with nothing
  in it at all.
- The widget cannot be dragged or resized while the composer is open. The grab
  band runs along the very bottom of the widget, which is where the field sits, so
  a click near its edge would otherwise resize the window instead of placing the
  caret.

### Added

- **The pattern docs are now enforced, not just written.** 31 architecture
  guards in `test/architecture/`, run by `flutter test` like everything else:

  - `layer_test` — `dart:io` confined to `core/` and `data/`; only `platform/`
    builds a `MethodChannel`; every method called from Dart is handled by the
    runner. The last one matters because an unhandled method is a **silent**
    no-op: the runner answers `Success()` either way, so the Dart `await`
    completes and nothing happens.
  - `storage_guard_test` — the watcher is on the directory and filtered; the
    export goes through the atomic writer; `.bak` is taken **before** the
    replace.
  - `widget_guard_test` — the runner never answers `HTCAPTION`; the loop cursor
    comes from the gesture anchor and not `GetCursorPos`; `WS_EX_NOACTIVATE` is
    restored; focus goes back to the window it was taken from;
    `WM_MOUSEACTIVATE` defers to compose mode.
  - `docs_test` — every rule in §3 of a pattern doc has a row in its test table,
    every test it cites still exists, every guard it cites exists, and
    `AGENTS.md` does not claim a fixed rule is still broken.

  These cover the rules whose failure is **silent**. `HTCAPTION` over the widget
  body looks reasonable in a diff, and it is the reason the widget could not be
  dragged for its entire life. `File(path).writeAsString` looks correct, and it
  is the reason an interrupted export left a truncated file. A guard that cannot
  fail reads as enforcement, so **each one was broken on purpose and watched go
  red** — the list is in `docs/testing_pattern.md` §6.

  The layer guard has no allowlist, on purpose: if a write genuinely cannot go
  through `data/`, the fix is to edit the scanner where the diff shows it,
  rather than to grow a list somewhere quiet.

### Changed

- **The pattern doc tables now carry the rule number.** Checked by set rather
  than by counting rows, because a count is satisfied by thirteen rows all
  pointing at §3.1 — which is exactly the rot the check exists to catch. A rule
  with no row, or a row citing a test that has been renamed, fails the build.
- **Four rules that had no test now have one.** The `.bak` holds the *previous*
  content rather than the new one; `loadFrom` keeps the notes it can read when
  one entry is malformed; the widget hides when no note has text; and writing an
  export puts a whole file on disk. The first of those exists because I broke it
  while extracting the atomic write into a shared helper, which is the second
  time that ordering has nearly gone wrong.
- **`docs/widget_pattern.md` §3.4 is no longer "manual only".** Scroll-versus-
  drag by extent is thoroughly tested already — both directions, with a real
  overflowing list — and the doc claimed otherwise. Same for §3.3's Dart half.
  One rule genuinely remains manual: §3.13, the runner's size clamp, whose
  failure is a widget too small to read rather than a crash.

### Fixed

- **The plain-text export is now atomic.** It was written with
  `File(path).writeAsString` from the UI layer, so an interrupted export left a
  truncated file — and that file is what you reach for when everything else has
  failed. It goes through `AtomicJsonFile.writeTextAtomically` now, the same
  temp-and-rename the notes file uses, and the other five `dart:io` calls in
  `ui/` are behind `BackupService.readFrom` and `NotesRepository.describeFile`.
  `dart:io` outside `core/` and `data/` is now zero, and stays that way.
- **The watcher is confirmed to be on the directory.** It was, but nothing said
  so. `File.watch()` holds a handle on the file on Windows, which blocks the
  other isolate's atomic rename, blocks a backup tool, and stops you copying
  your own notes out by hand — with nothing thrown and no error message.

### Documentation

- **`AGENTS.md` and three pattern docs.** `docs/storage_pattern.md`,
  `docs/widget_pattern.md` and `docs/testing_pattern.md`, each documenting one
  seam and ending with a table naming the tests that pin its rules.

  Written because the hard-won parts of this project lived in code comments,
  which you only read if you are already in the file that has the bug. Two
  shipped bugs are now explained rather than merely fixed: the widget could not
  be dragged for its entire life because `HTCAPTION` over the body is dead code
  (the Flutter view covers the client area, so it is never consulted; and
  `DefWindowProc` will not start the move loop without `WS_CAPTION` or
  `WS_THICKFRAME`), and the reads had no retry ladder because `dart:io` cannot
  hold an exclusive lock, so no Dart-only test could have reproduced a scanner.

  Deliberately **not** thirteen documents. There is no backend, sync,
  permissions, localisation, region handling or database here, so those
  concerns would have had no subject matter.

- **`AGENTS.md` records the known divergences and the one known bug.** It also
  lists which guards enforce what, and names the single rule that remains manual
  verification rather than leaving "Win32 is not covered" as a vague area. The
  first-launch widget bug is recorded as **unrooted** rather than quietly left as
  folklore. (The export divergence it originally listed is now fixed — see
  Fixed above — and `docs_test` fails if this file claims otherwise.)

- **A whitespace-only note body is now pinned as normalising to empty** through
  the plain-text backup round trip, while a body with text keeps its own
  whitespace. It was true before and asserted nowhere.

164 tests, `flutter analyze` clean.

### Fixed

- **Antivirus can no longer stop the app from starting.** This was the worst bug
  in the project and it was invisible until the file was actually held open. The
  write path had always retried, because something holding the destination is
  routine on a live desktop; the read path did not. So a virus scanner passing
  over `notes.json` for a few milliseconds could make a perfectly valid file
  appear unreadable, and the app refused to open — saying your notes were damaged,
  when they were intact — until it was restarted. Reads now walk the same kind of
  retry ladder, about two and a half seconds of it, which covers a real-time scan
  and is only ever paid when something is genuinely in the way.
- **A file that is merely held open is no longer reported as damaged.** A file
  that cannot be *opened* is nearly always being looked at by antivirus, a backup
  tool or a sync client, and it is fine underneath. That case now says so, and
  offers **Try again**, which recovers the moment whatever was holding it lets go.
  A file that opens but does not parse is still treated as damaged, because
  waiting cannot make bad content become good content.
- **Starting fresh no longer requires renaming a file by hand.** It used to exist
  only as a sentence of small grey text at the bottom of the screen, telling you
  to do it in Explorer and restart — the right instruction for someone reading it
  calmly and the wrong experience for someone whose notes had just failed them.
  It is a button now, behind a confirmation that spells out what happens.
- **Starting fresh keeps the damaged file.** It is renamed with the time on the
  end rather than deleted, so a second incident cannot overwrite the first one's
  evidence and the text is still there for anyone who can read JSON by hand. The
  new name is shown once it has happened.

### Added

- **`notes.json.bak` — the previous good version, kept automatically.** Written
  before every atomic replace, so it is one write behind: at most the debounce
  window of typing, a fraction of a second. Because writes are atomic, WinNotes
  can never produce a file it cannot read, which means corruption is always
  something external — a hand-edit, a sync client writing two copies at once, a
  disk dropping a sector. In every one of those cases the thing that saves the
  notes is the last state this app put on disk, and now there is one.
- **"Restore the previous version"**, offered first on the problem screen, above
  anything you have to go and find yourself. No backup you had to remember to
  make, no file to locate. Recovering through it does not consume it: the good
  copy is still there afterwards, so a second incident can be recovered the same
  way.

### Changed

- The problem screen now leads with whatever is most likely to recover the notes,
  in the order: the rolling backup, **Try again** if the file is only being held,
  a backup you choose, then starting fresh. Nothing is offered when it would do
  nothing — with no previous version there is no "restore the previous version"
  button, rather than a greyed-out one inviting the question "of what?".

### Added (continued)

- **Mark a note as done, from the app or the widget.** Every note gets a circle
  on its left; press it and a line goes through the note's title and body, and
  press it again to bring it back. It is on every note in the widget's cards, on
  every row in the editor's list, and beside the title of the note you are
  editing, with `Ctrl+D` for the keyboard. Pressing it in the editor's list does
  not also open the note, because working through a list means pressing the same
  small circle a dozen times in a row.
- The widget's large card now skips notes that are already done, so ticking off
  the task you were looking at reveals the next one instead of leaving a line
  through the middle of it. An explicitly selected note still wins over that, and
  when everything is finished the most recent note is used, so the card never
  goes missing.

Finished state is kept in `notes.json` as a `completedAt` timestamp, so it
survives a restart and you can answer "when did I finish this" later. Notes
written before this are unaffected, and an unfinished note writes no extra field
at all, so your file does not change just because the app was updated.

Not part of the plain-text backup: `Export as text` writes only what you wrote,
because that file is meant to be readable in Notepad, and a note's finished state
has no plain-text spelling that would not also become a formatting convention you
would then have to keep reading. Importing a backup restores the text and leaves
everything open.

### Changed

- Marking a task done deliberately does **not** count as editing it, so notes do
  not jump to the top of the list as you work through them. Finishing something
  is a change of state, not an edit.
- The widget surface can now write `notes.json`, but only when there is no
  editor window to own it. With an editor open it asks the runner to route the
  toggle to the editor, which is the single writer of that file; on an autostart
  launch there is no editor and therefore nothing to lose, so it writes the file
  itself rather than refusing to work. Writing it unconditionally would race the
  editor's debounced keystrokes and lose them.

### Fixed

- The widget now flushes `notes.json` on the way out, not just its own state.
  Without this, quitting within a quarter of a second of ticking a task from the
  widget silently undid the tick.

- **The widget can be dragged and resized at all.** This is the big one, and it
  was not a lock or a settings problem: the widget has never been movable. It
  reported `HTCAPTION` for its body so that Windows would run the drag loop for
  it, and that could not work twice over. The Flutter view covers the client
  area, so the system hit-tested the child and never asked the widget anything.
  And even when it did ask, `DefWindowProc` only starts a move or size loop for a
  window with `WS_CAPTION` or `WS_THICKFRAME`, which a borderless popup has
  neither of. Dragging the body and grabbing a corner now both work, to the
  pixel, in any direction.
- **Cards are still tappable.** Answering `HTCAPTION` over the body would have
  fixed dragging and broken everything else on the same pixels — Windows delivers
  a message to one target per pixel — so the widget is now `HTCLIENT`
  throughout, and both the drag and the resize are recognised in Dart and handed
  to the runner, which tracks the cursor in screen space. Tapping a card,
  scrolling the list and double-clicking through to the editor all still work,
  and a press that does not travel is still a tap.
- **Settings opens.** Clicking Settings did nothing: the menu opened, the row was
  clicked, and no dialog appeared. `EditorApp` returns a `MaterialApp`, which
  puts its own State's context *above* the Navigator, so `showDialog` from there
  had no Navigator to push onto and threw instead. Export still appeared to work
  because it reached for a native file dialog first and only fell over on the
  confirmation afterwards, which is what made this look like "Settings is
  broken" rather than "a context is in the wrong place". The same fault silently
  swallowed the "Exported N notes" confirmation and the import merge question.
- **Scrolling and dragging no longer fight.** They are the same gesture shape, so
  the widget now decides by the scroll extent: scroll while there is more to
  read, and once the list is at its end, keep going and the widget comes with
  you. Deciding by which notification arrived first was a race, and a list with
  nothing left to scroll never sent one at all.
- **A first drag on a fresh install works.** With no saved geometry, the widget's
  idea of its own position was empty and there was nothing for a drag to move
  relative to. It now asks the runner where the window actually is at startup.
- **The widget cannot be dragged off the screen or shrunk out of reach.** A resize
  is clamped to a floor, so a fast flick cannot leave a window nobody can find.
- **A locked widget now says so.** Dragging one used to do nothing whatsoever,
  with nothing on screen to suggest the lock was the reason. It now shows a short
  hint naming both the state and where to change it, and only after someone has
  actually tried to drag, so it never nags anyone who has not.
- **The widget can be dragged out of the box again.** 1.1.0 shipped the position
  lock switched on by default, which meant it could not be moved at all unless you
  found a switch in Settings. The lock is now opt-in, for when the widget is
  parked somewhere you want it to stay.

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
- **Lock the widget in place.** New switch in Settings → Widget, off by default.
  While it is on, dragging the widget does nothing, so a stray drag across the
  card cannot move a widget that was deliberately placed, and the widget says so
  rather than ignoring you. Turning it off makes the widget draggable again
  straight away, with no restart: the widget watches `settings.json`, so the change
  reaches the window as it is made. Resizing from an edge or a corner is
  unaffected, because locking is about position, not size.
- **A dedicated Widget settings group.** "Keep the widget above other windows"
  moves here from Appearance, so the two switches about where the widget sits
  and whether it gets in the way are described together. `alwaysOnTop` itself is
  unchanged and still defaults to on.

### Changed

- The widget is draggable by default again. 1.1.0 made "Lock the widget in
  place" default to on, which removed dragging altogether rather than merely
  guarding against accidental drags.
- The grab band for resizing is a little wider than it looks like it needs to
  be. The window is clipped to a rounded region, so the literal corner pixels do
  not exist and a grab aimed at one arrives at nothing.
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