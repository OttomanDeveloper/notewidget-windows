# Changelog

## 1.3.3

### Fixed

- The widget's failure path now starts with a scope, like the normal one.
- CI pins its Flutter version, so a green local run and a red CI run can no longer be the same commit.

## 1.3.2

- The widget's failure path now starts with a scope, like the normal one.
### Fixed

- The storage guard reads source with either line ending, so a CRLF checkout no longer fails it with a range error.
- The packaging gate re-runs the suite once before refusing, and reports when it does.

## 1.3.1

- A design that draws an edge at the bottom of the card reserves room for it, so a ticket's perforations and a receipt's torn edge no longer cut through the text.
- The Stamp widget design sets the whole note in capitals, body included, rather than only the title.
- The storage guard reads source with either line ending, so a CRLF checkout no longer fails it with a range error.
- The packaging gate re-runs the suite once before refusing, and reports when it does.
### Fixed

- The packaging gate runs the suite serially, so a loaded runner cannot fail the release over a test that measures real elapsed time.
- The debounce-ceiling test asserts the property instead of wall-clock arithmetic, which overshot exactly when the machine was busy.

## 1.3.0

- Five widget designs - Paper, Stamp, Ticket, Soft, Receipt - chosen in Settings and applying to the whole widget.
- The focus behaviour when a card is dragged, pinned or auto-hidden is unchanged.
### Added

- Frame timings are recorded to a file when `WIN_NOTES_FRAME_LOG` is set, for stalls a widget test cannot see.
- `tool\verify\verify.ps1`: the gate. Seven stages in dependency order, about two minutes, the same command CI runs.
- `tool\verify\run_scenarios.ps1`: drives the Windows scenarios with synthetic input and records a verdict per row.
- `docs/testing/`: the Windows test program — 27 scenarios in 6 waves, the A/B/C evidence classes, the feature matrix, and a results ledger.
- `docs/flutter_architecture_pattern.md`: a Flutter architecture, performance and Riverpod rulebook, carried in verbatim, with an appendix recording where it contradicted this repository and what the migration did about it.
- `flutter_rules_guard_test`: pins the rules of that rulebook that apply here, with a decision table covering every section.
- `lib/core` and `lib/features/notes|widget|settings`: the feature-first tree from rulebook §4, with `data/`, `domain/` and `presentation/` per feature.
- Domain repository interfaces; providers and notifiers depend on them, with `@override` on every implementation.
- Derived providers (`selectedNote`, `focusedNote`, `visibleNotes`, `noteById.family`, theme fields); screens watch slices via `ref.select`.
- `widgetDisplayNotesProvider` + `widgetNoteByIdProvider.family`: the surface derives the list, each card watches its own note.
- `settings_dialog.dart` is a 40-line composition; its 12 widgets live in their own folders.
- Comments run at most 3 lines; `flutter_rules_guard_test` fails anything longer.
- `tool/check_architecture.ps1` runs the §9 size and privacy checks outside `flutter test`, and in CI.
- `widget_surface.dart`, `editor_screen.dart` and `note_editor_pane.dart` are compositions; composer, cards chrome, corrupt screen, app bar and editor sections live in their own folders.
- `always_specify_types` on, with `omit_local_variable_types` off: 2210 annotations across 112 files.
- The rest of the rulebook's lints, unchanged.
- `changelog_guard_test`: fails on an entry longer than one bullet.
- `docs/provider_pattern.md`, `docs/isolate_pattern.md`, `docs/platform_pattern.md`.
- `AGENTS.md` section 0.7 to 0.11: no `setState`, no injected dependencies, a `WidgetRef` lifetime rule, a declared channel contract, construction in providers.
- `no_set_state_test`, `provider_guard_test`, `platform_guard_test`, `isolate_guard_test`.
- `lib/core/utils/app_providers.dart`: the dependency graph, replacing ten hand-written constructions across the two roots.
- Riverpod and flutter_riverpod, as the state layer.
- `WidgetNotifier.reloadNotes()`, so a change to `notes.json` can be applied without the directory watcher.
- `TestHarness` in `test/helpers/`, so tests build a container rather than a controller.
- `channelMethodNames` scans joined text and all four dispatch idioms; it had been missing five real methods.
- `platform_guard_test`: every argument key Dart sends is read by the runner, and the set of methods bypassing `_fire`/`_invoke` is computed rather than counted in prose.
- `storage_guard_test`: only the two notifiers write `notes.json`, and every widget-side write asks the runner first.
- `provider_guard_test`: a third provider file over the 200-line cap is a red build; the two recorded breaches cannot widen or go stale.
- `SourceTree.relativePath` and `dartFilesUnderRelative`: repo-relative keys with forward slashes, so a guard cannot match nothing and report a clean scan.
- `test/first_launch_test.dart`: the first launch, checked the way the app reaches it.
- `tool/verify/verify_release.ps1`: drives a release build through first launch against a throw-away profile in `%TEMP%`, and checks yours is unchanged.
- `WIN_NOTES_DATA_DIR`: points the app at a different data directory. For verification runs only.
- `storage_location_guard_test` and `test/storage_location_test.dart`: the notes folder setting, which is now the folder the files actually go to.
- `SettingsNotifier.moveTo`: copies your notes to a folder you choose. Nothing is moved or deleted, and a folder that already has notes is left alone.
- Lints: `unawaited_futures`, `cancel_subscriptions`, `close_sinks`,
  `parameter_assignments`, `avoid_catching_errors`, `use_string_buffers`,
  `prefer_final_locals`, `require_trailing_commas`, `avoid_positional_boolean_parameters`.
- Lints: `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, `prefer_const_declarations`, `avoid_unnecessary_containers`, `sized_box_for_whitespace`, `use_key_in_widget_constructors`.

### Added

- `agents_guide_test`: fails when AGENTS.md drifts from the tree — an undocumented guard, a cited guard that is gone, a §0 rule with nothing enforcing it, a hand-kept test count, or a runbook path that moved.
- AGENTS.md §6: prerequisites, the test loops, the gate subsets, the scenario probe, and what none of it covers.

### Changed

- `no_set_state_test` also rejects `StreamBuilder`, `FutureBuilder` and a hand-rolled `InheritedWidget` as ways around §0.7. All three are at zero.
- Settings: `Editor text size` and `Preview text size` sliders, 11–24px, saved and applied to the source and the rendered preview.
- Ctrl+wheel over the editor resizes the pane under the pointer. Not yet verified — see `docs/widget_pattern.md` §3.21.
- The Markdown switch is a labelled `Preview` pill, and the narrow-layout switch reads `Show preview`.
- `AGENTS.md` §3.1 names `flutter_rules_guard_test`; architecture count is 147 and the suite is 473.
- The provider cap is 300 lines code-only; only `notes_controller.dart` (333) is over, split separately.
- The release packaging passes `--obfuscate --split-debug-info` and checks the symbols exist.
- Ten positional `bool` parameters are now named, across the notes, settings and widget notifiers and `ShellChannel`.
- The three controllers are Riverpod `AsyncNotifier`s with immutable state, replacing `ChangeNotifier`s.
- `main()` builds one `ProviderScope`, so `EditorApp` and `WidgetApp` take no parameters.

### Added

- `:tada:`-style emoji shortcodes render as the character, and `> [!NOTE]` and its four siblings render as a labelled callout; both were already in the parser but out of its default set.

- The preview builds only the Markdown blocks on screen, so a long note scrolls as fast as a short one.
- A Skin setting, beside Colour: it picks a card's corners, row spacing, how the open note is marked, and what separates rows.
- Four skins ship - Sharp, Soft, Outline, Solid - and the first choice is no skin at all.
- Ctrl+wheel font resizing is coalesced: a burst of notches resizes once instead of once per notch.
- The preview pane no longer re-renders the whole document on every keystroke: a keystroke in a long note drops from 64-169 ms to 15-44 ms.
- Ctrl+wheel font resizing is coalesced: a burst of notches resizes once instead of once per notch.
- The preview settles after a sentence rather than a fraction of a second, so typing no longer triggers a full document re-render on every pause.
### Fixed

- The widget's saved position was written on every drag and never restored; it now comes back where you left it, clamped to a screen that still exists.
- A first launch showed the widget over an empty library; the runner's deferred boot-time show no longer undoes the decision to hide it.
- A table with more columns than the pane could show was squeezed into unreadable slivers; it now scrolls sideways and each column keeps a legible width.
- `crash.log`: uncaught Dart errors and native faults are appended to `%APPDATA%\WinNotes`, because a release build launched at login has nowhere to print.
- `win_notes.exe --diagnose <path>` writes one snapshot of the profile, monitors, window position and autostart entry, then exits.
- A draggable divider between the source and the preview, bounded at each end, with double-click to reset.
- The note list collapses to a handle on the edge, and the toolbar carries the same toggle.
- `ISSUE_REPORTING.md` now says how to collect that evidence before filing an issue.
- A list item lost everything after its first bold, italic, link or code run; `- **(x)** words` rendered as `(x)` alone.
- A paragraph holding only an image rendered as nothing; `alt` is an attribute, so the blank check now looks for the image itself.
- `<br>` printed itself on screen instead of breaking the line.
- A footnote printed its number twice, as `11.1.`, from the list marker and the reference.
- An HTML comment was shown on screen; it is now invisible, as a comment should be.
- `platform_guard_test` read zero argument keys once the maps became `<String, dynamic>{...}`; the scanner now tolerates an explicit type argument.
- Four `package:riverpod/src/` imports went, by dropping the `ProviderFamily` and `Override` annotations that needed them.
- The "an empty library shows no widget" check counted one window per process, so it could not fail; it now enumerates by window class and reports a real bug.
- `docs_test` checked a doc citation only when it had no `/` in it, so the five paths added to the docs index were never verified.
- A test's wait must outlast the retry ladders it is waiting on; `notes_repository_test.dart` waited 6s where the code can legitimately retry for 5.75s.
- `first_launch_test.dart` and `palette_test.dart` now wait for the debounced write through `test/helpers/file_io.dart` instead of sleeping 700 ms or reading unguarded.
- `EditorScreen` is `editor_view/`, `ShellMissingApp` is `shell_missing_app/`, `UndoToastBody` is `undo_toast_body/`, `EmptyState` is `notes`'s own; the folder and file are named after the widget.
- Each note-list row carries `ValueKey(note.id)`, so a note that moves when you edit it keeps its own element state.
- Two `FocusNode`s created inline on a focus path are gone; the caret is dropped instead, so nothing is allocated that nothing can dispose.
- **The installer and the Windows 11 Apps list now show the project logo.** The installer drew Inno Setup's own icon, and the app was blank in Settings > Apps.
- **A first launch no longer creates its first note only when you type.** Opening the app on a fresh profile and closing it again without typing left nothing behind, and every launch gave the note a new id.
- The widget window was never configured on launch; the call read state that did not exist yet and returned early.
- A refused drag showed no hint, and the hotkey dialog kept showing the combination it opened with; both read a `ValueNotifier` nothing was listening to.
- `NotesState.copyWith` could not clear `selectedId`, so deselecting or deleting the last note kept the old value.
- `WidgetSurface.build` watches the theme, palette and settings providers for what it draws.
- `Note` is immutable with `copyWith` and value equality; the editor screen, list pane and editor pane watch state slices.
- Settings groups watch field slices; the editor preview renders from a debounced source.
- `CorruptNotesScreen` is a plain `StatefulWidget` with one `Consumer` around the Quit button.
- `_CheckPainter` reuses one `Paint` and `Path` across `paint()` calls instead of allocating per frame.
- Constant `RegExp`s in `widget_note_card.dart` and `storage_transfer.dart` are now `static final` fields.

## 1.2.0

### Added

- Each row in the notes list renders its title's inline formatting and its preview as Markdown, falling back to plain text for a note that is not marked down.
- A per-note switch beside the title renders the body as Markdown: a source field and a preview in the editor, the same walk compressed onto the widget card.

### Fixed

- Temporary-directory cleanup retries for about five seconds instead of one, so a held file handle no longer fails the suite about one run in six.
- The editor cannot be dragged below 520 × 360; the floor is set with `WM_GETMINMAXINFO` and scaled for the window's DPI.
- The widget leaves the topmost band for as long as the editor is foreground, and returns to it when the editor stops.

## 1.1.0

### Added

- Add a note from the widget: a circle in the bottom-right corner that becomes a text field in the same spot, closing on Enter, Escape or the cross.
- The widget can be typed into. `WS_EX_NOACTIVATE` is dropped for as long as the composer is open, and put back with the keyboard afterwards.
- Escape closes the composer, so the field can be dismissed from the keyboard.
- Nine colour schemes in Settings, each changing the accent and the surfaces built around it in both windows.
- 37 architecture guards in `test/architecture/`, run by `flutter test`: `layer_test`, `storage_guard_test`, `widget_guard_test`, `docs_test` and `dependency_guard_test`.
- `AGENTS.md` and three pattern docs, each documenting one seam and ending with a table naming the tests that pin its rules.
- `AGENTS.md` records the known divergences, the one known bug as unrooted, and which guard enforces what.
- A whitespace-only note body is pinned as normalising to empty through the backup round trip.
- `notes.json.bak`, written before every atomic replace, keeping one write behind.
- "Restore the previous version", offered first on the problem screen and non-consuming.
- Mark a note as done from the app, the widget's cards or the editor's list, with `Ctrl+D`; finished state is a `completedAt` timestamp in `notes.json`.
- Downloadable releases: every tagged version publishes a portable ZIP and a per-user `setup.exe`.
- The installer asks for no administrator rights, installing into `%LOCALAPPDATA%\Programs\WinNotes`.
- A structured bug report form, and `ISSUE_REPORTING.md`.
- `CONTRIBUTING.md`, covering build setup, the two design rules most mistakes break, and cutting a release.
- Lock the widget in place, off by default, with the widget saying so rather than ignoring a drag.
- A dedicated Widget settings group, holding "Keep the widget above other windows".

### Changed

- A note written in the widget's composer becomes a title and a body, landing at the top of the list without stealing the editor's selection.
- A note with a title and no body no longer says "No text yet".
- The widget cannot be dragged or resized while the composer is open.
- Pattern doc tables carry the rule number, checked by set rather than by counting rows.
- Four rules that had no test now have one: the `.bak` holds the previous content, `loadFrom` keeps readable notes, the widget hides when no note has text, and an export puts a whole file on disk.
- `docs/widget_pattern.md` §3.4 is no longer "manual only"; §3.13, the runner's size clamp, genuinely remains manual.
- The problem screen leads with whatever is most likely to recover the notes, and offers nothing that would do nothing.
- Marking a task done does not count as editing it, so notes do not jump to the top of the list.
- The widget surface can write `notes.json`, but only when there is no editor window to own it.
- The widget is draggable by default again; the position lock had shipped on.
- The grab band for resizing is wider than it looks, because the rounded clip removes the literal corner pixels.
- `pubspec.yaml` is the single source of truth for the version, and the release workflow fails if the tag disagrees with it.

### Fixed

- `readableOn` picked the wrong ink for mid-luminance colours; both contrasts are now computed and the higher one wins.
- The plain-text export is now atomic, going through `AtomicJsonFile.writeTextAtomically` instead of `File(path).writeAsString` from the UI layer.
- The watcher is confirmed to be on the directory rather than the file, which had been holding a handle that blocked the other isolate's atomic rename.
- Antivirus can no longer stop the app from starting; reads now walk a retry ladder of about two and a half seconds.
- A file that is merely held open is no longer reported as damaged, and offers **Try again** instead.
- Starting fresh is a button behind a confirmation, rather than a sentence telling you to rename a file in Explorer.
- Starting fresh keeps the damaged file, renamed with the time on the end rather than deleted.
- The widget now flushes `notes.json` on the way out, not just its own state.
- The widget can be dragged and resized at all: it is `HTCLIENT` throughout, with the drag and the resize recognised in Dart and handed to the runner.
- Cards are still tappable; Windows delivers a message to one target per pixel, so answering `HTCAPTION` over the body would have broken everything else on those pixels.
- Settings opens; `showDialog` from `EditorApp` had no Navigator above its State's context.
- Scrolling and dragging no longer fight; the widget decides by scroll extent rather than by which notification arrived first.
- A first drag on a fresh install works, because the widget asks the runner where the window actually is.
- The widget cannot be dragged off the screen or shrunk out of reach; a resize is clamped to a floor.
- A locked widget now says so, and only after someone has actually tried to drag.
- The widget can be dragged out of the box again; the position lock is now opt-in.
- The test suite no longer leaves a temporary directory behind; controllers are drained before it is removed.
- The tray menu no longer advertises `Ctrl+Alt+S`, which was never registered with Windows.
- A failed write no longer disables saving for the rest of the session; it keeps its value queued and retries with backoff.
- Editing a note always moves it to the top of the list; timestamps now step past the current newest.
- Test flakiness from two tests asserting on the exact millisecond a write landed, and on clock-dependent ordering.

## 1.0.0

First release. Windows 11 Pro, Flutter, no third-party runtime dependencies.

### Added

- **Notes.** Title and body, nothing else. Most-recently-edited ordering with a stable tie-break, and search across both filtering as you type.
- **Widget.** Frameless, layered, always-on-top window with no taskbar button, acrylic where Windows provides it, never taking focus when clicked, remembering its monitor and position.
- **Editor.** Two panes, or one at a time on a narrow window. Plain text, no toolbar, no save button, search with `Ctrl+F`.
- **Delete with undo.** Confirmation first, then a six-second undo that puts the note back in its original position.
- **Storage.** One `notes.json`, written whole and atomically, debounced by 250ms with a ceiling so continuous typing still reaches disk.
- **Refusal to overwrite unreadable notes**, producing a screen offering a restore rather than starting with an empty list.
- **Plain-text export and import**, readable without this app.
- **Autostart** through one per-user `Run` key entry, with a delay that applies to autostart only.
- **Global hotkey**, `Ctrl+Alt+N` by default, with collision detection reported in Settings.
- **Tray icon** matching the taskbar theme; Quit is the only exit and it confirms first.
- **Single instance.** A second launch raises the existing surfaces instead of stacking a duplicate.
- **Per-monitor recovery** when the monitor holding the widget is unplugged.
- **Settings** in four flat groups: appearance, startup, hotkey, storage.
- **Light, dark and system themes**, following Windows by default, with reduced motion respected.
- **Logo**, generated from SVG masters with every `.ico` frame verified.
- The native host owns the windows, tray, hotkey, registry entry and acrylic directly against Win32, rather than through plugins.
- The two Flutter surfaces share state through files with one writer per file, which removes cross-isolate merge logic.