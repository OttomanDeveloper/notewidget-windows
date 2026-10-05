import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';

import '../../../notes/domain/note.dart';
import '../../../notes/domain/repositories.dart';
import '../../../notes/data/notes_repository.dart';
import '../../../notes/presentation/providers/notes_providers.dart';
import '../../data/widget_state_repository.dart';
import '../../domain/repositories.dart';
import './widget_providers.dart';
import '../../../../core/platform/shell_channel.dart';
import '../../../../core/utils/app_providers.dart';
import '../../../settings/presentation/providers/settings_controller.dart';

/// Everything the widget surface owns.
///
/// The widget runs in its own isolate and has its own copy of this, read from the
/// same files the editor writes. That is not a shortcut around shared memory: it is
/// the reason there is exactly one writer per file and therefore no lost updates,
/// ever. `docs/isolate_pattern.md` §2.
class WidgetSurfaceState {
  const WidgetSurfaceState({
    this.notes = const [],
    this.selectedId,
    this.window = WidgetWindowState.empty,
    this.visible = true,
    this.positionLocked = false,
  });

  final List<Note> notes;
  final String? selectedId;
  final WidgetWindowState window;

  /// Whether the runner has been told to show the window.
  final bool visible;

  /// Whether dragging is currently refused.
  ///
  /// Read by the surface so it can tell someone who drags a locked widget why
  /// nothing happened, instead of leaving them to wonder. A field rather than a
  /// `ref.read(settingsProvider)` at the point of use, because three widgets ask
  /// and a caller that forgot to read settings would silently render an unlocked
  /// widget.
  final bool positionLocked;

  /// The note rendered large. Everything else in the widget is a compact card.
  ///
  /// Prefers the most recent note that is still open, so ticking off the task in
  /// the big card reveals the next one instead of leaving a line through the
  /// middle of the thing you look at most. See [NotesState.focusedNote] for the
  /// same rule and the reasoning.
  Note? get focusedNote => focusedNoteIn(notes, selectedId);

  /// Notes in display order: most recent first, with the focused note pulled to the
  /// top so it reads as the card the widget is about.
  List<Note> get displayNotes => displayNotesIn(notes, selectedId);

  bool get hasAnyNoteWithText =>
      notes.any((n) => n.title.trim().isNotEmpty || n.body.trim().isNotEmpty);

  WidgetSurfaceState copyWith({
    List<Note>? notes,
    String? selectedId,
    WidgetWindowState? window,
    bool? visible,
    bool? positionLocked,
  }) {
    return WidgetSurfaceState(
      notes: notes ?? this.notes,
      selectedId: selectedId ?? this.selectedId,
      window: window ?? this.window,
      visible: visible ?? this.visible,
      positionLocked: positionLocked ?? this.positionLocked,
    );
  }
}

/// The widget surface's state. Never writes notes.json while an editor is open.
///
/// Was `WidgetController extends ChangeNotifier` until 2026-10-05.
///
/// The `isEditorRunning` check in [toggleCompleted] and [addNote] is the whole
/// reason this surface is careful about writing at all: notes.json has one writer,
/// normally the editor, and the editor holds keystrokes in memory for a quarter of
/// a second before they reach disk. A toggle written from here inside that window
/// would overwrite them and silently lose whatever was typed. So the runner is
/// asked who owns the file, and the answer decides.
///
/// That logic is unchanged by the rewrite. What changed is that the decision is made
/// in one place instead of two, and that `_ready` is no longer a separate field a
/// widget has to remember to check - it is the `AsyncValue` this returns.
class WidgetNotifier extends AsyncNotifier<WidgetSurfaceState> {
  late final ShellChannel _shell;
  late final INotesRepository _notesRepo;
  late final IWidgetStateRepository _widgetRepo;
  late final ISelectionRepository _selectionRepo;

  final NoteIdFactory _ids = NoteIdFactory();
  Timer? _geometrySaveTimer;

  @override
  Future<WidgetSurfaceState> build() async {
    _shell = ref.watch(shellProvider);
    _notesRepo = ref.watch(notesRepositoryProvider);
    _widgetRepo = ref.watch(widgetStateRepositoryProvider);
    _selectionRepo = ref.watch(selectionRepositoryProvider);

    // Always watched here: the widget surface has no other way to learn that the
    // editor changed something. `build` runs once per container, so this cannot
    // stack up.
    _selectionRepo.watch(_onSelectionChangedExternally);
    _notesRepo.watch(_onNotesChangedExternally);
    ref.onDispose(() => _geometrySaveTimer?.cancel());

    final window = await _widgetRepo.load();
    final selectedId = _selectionRepo.readSelection();
    final notes = await _readNotes();

    var next = WidgetSurfaceState(
      notes: notes,
      selectedId: selectedId,
      window: window,
      visible: false,
      positionLocked: _positionLocked,
    );

    // Ask the runner where the window really is. A first run has no saved
    // geometry, and without this the widget's idea of its own position stays empty
    // - so the first drag of a new install would have nothing to move relative to
    // and would silently do nothing.
    final live = await _shell.widgetBounds();
    if (live != null) {
      next = next.copyWith(
        window: window.copyWith(
          left: live.left,
          top: live.top,
          width: live.width,
          height: live.height,
        ),
      );
    }

    // An empty widget is never shown, since there would be nothing to look at.
    final shouldShow = next.hasAnyNoteWithText;
    final ready = next.copyWith(visible: shouldShow);

    // Settings can change the palette and the opacity the runner needs, and this
    // notifier is the only thing that talks to it about them. Narrowed to the
    // four window fields, so a hotkey or storage change does not reconfigure
    // the window.
    ref.listen(
      settingsProvider.select(
        (v) => (
          v.value?.settings.alwaysOnTop,
          v.value?.settings.widgetOpacity,
          v.value?.settings.acrylicEnabled,
          v.value?.settings.widgetPositionLocked,
        ),
      ),
      (_, _) => unawaited(_applyWindowConfiguration()),
    );

    await _applyWindowConfiguration(ready);
    return ready;
  }

  bool get _positionLocked =>
      ref.read(settingsProvider).value?.settings.widgetPositionLocked ??
      false;

  Future<List<Note>> _readNotes() async {
    final result = await _notesRepo.load();
    return switch (result) {
      NotesLoaded(:final notes) => NotesRepository.sorted(notes),
      // A widget with nothing to show is not an error worth interrupting the
      // desktop for; the editor is where the file problem gets reported.
      NotesCorrupt() => const [],
    };
  }

  /// Applies the saved geometry to the runner once the window exists.
  Future<void> restoreGeometry() async {
    final window = state.requireValue.window;
    if (!window.hasGeometry) return;
    await _shell.setWidgetGeometry(NativeBounds(
      left: window.left!,
      top: window.top!,
      width: window.width!,
      height: window.height!,
    ));
  }

  /// Applies the autostart delay, which only ever applies to the autostart launch.
  /// Launching by hand shows the widget immediately.
  Future<void> applyStartupDelay() async {
    final launch = ref.read(launchInfoProvider);
    final settings = ref.read(settingsProvider).value?.settings;
    final delay = settings?.autoStartDelayMs ?? 0;
    if (!launch.isAutostartLaunch || delay <= 0) return;
    await Future<void>.delayed(Duration(milliseconds: delay));
  }

  /// Re-reads `notes.json` and republishes whether the widget should be visible.
  ///
  /// This is what the directory watcher calls, and it is public because the watcher is
  /// not the only way the file can change. The widget surface has no other way to
  /// learn that the editor wrote something, and a test cannot rely on the watcher at
  /// all - `AtomicJsonFile` watches with real timers that `flutter_test`'s fake clock
  /// never advances, so under a widget test the callback simply never fires and the
  /// surface sits on stale notes looking like it works.
  ///
  /// So the same operation is available on demand rather than existing only as the
  /// body of a listener that CI cannot reach.
  Future<void> reloadNotes() async {
    final current = state.value;
    if (current == null) return;
    final notes = await _readNotes();
    final shouldShow = notes.any(
      (n) => n.title.trim().isNotEmpty || n.body.trim().isNotEmpty,
    );
    state = AsyncData(current.copyWith(notes: notes, visible: shouldShow));
    if (shouldShow != current.visible) {
      await _applyWindowConfiguration();
    }
  }

  Future<void> _onNotesChangedExternally() => reloadNotes();
  void _onSelectionChangedExternally() {
    final current = state.value;
    final next = _selectionRepo.cached;
    if (current == null || next == current.selectedId) return;
    state = AsyncData(current.copyWith(selectedId: next));
  }

  /// Tells the runner what this window should look like.
  ///
  /// [from] is the state to describe. It exists because `build` has to configure the
  /// window *before* `state` exists - and the first version of this notifier had no
  /// parameter, so it read `state.value`, found null, returned early, and the window
  /// was never configured at all on launch. Nothing threw. `widget_integration_test`
  /// found it by asserting that the runner had been told anything.
  ///
  /// So `build` passes the state it is about to return, and every other caller - a
  /// visibility change, a settings change, a re-read - passes nothing and gets the
  /// published state.
  Future<void> _applyWindowConfiguration([WidgetSurfaceState? from]) async {
    final current = from ?? state.value;
    final settings = ref.read(settingsProvider).value?.settings;
    if (current == null || settings == null) return;
    await _shell.configureWidget(
      alwaysOnTop: settings.alwaysOnTop,
      opacity: settings.widgetOpacity,
      // The runner downgrades this itself when the build cannot do acrylic, so
      // asking for it unconditionally keeps the fallback in one place.
      acrylic: settings.acrylicEnabled,
      rounded: true,
      positionLocked: settings.widgetPositionLocked,
      visible: current.visible && settings.widgetOpacity > 0,
    );
  }

  /// Called when the native side reports the widget was moved or resized.
  void onGeometryChanged(NativeBounds bounds) {
    final current = _require();
    final window = current.window.copyWith(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
    );
    state = AsyncData(current.copyWith(window: window));
    // Dragging emits a WM_MOVE per pixel; only the last position is worth writing,
    // so persistence is coalesced rather than throttled in the runner.
    _geometrySaveTimer?.cancel();
    _geometrySaveTimer = Timer(const Duration(milliseconds: 250), () {
      _widgetRepo.save(state.requireValue.window);
    });
  }

  void rememberScroll(double offset) {
    final current = _require();
    if ((offset - current.window.scrollOffset).abs() < 0.5) return;
    final window = current.window.copyWith(scrollOffset: offset);
    state = AsyncData(current.copyWith(window: window));
    // Writes the whole state including the note selection, so a tap that changes
    // the selection and a scroll that changes the offset can queue on top of each
    // other. The debounced writer collapses them.
    _widgetRepo.save(window);
  }

  /// Focusing a card from the widget is a normal thing to want, and the editor picks
  /// the change up through the same file.
  void focusNote(String id) {
    final current = _require();
    if (current.selectedId == id) return;
    state = AsyncData(current.copyWith(selectedId: id));
    _selectionRepo.setSelection(id);
  }

  /// Marks a note finished or unfinished, from the widget.
  ///
  /// See the class doc for why this asks the runner rather than writing.
  Future<void> toggleCompleted(String id) async {
    if (await _shell.isEditorRunning()) {
      await _shell.requestToggleCompleted(id);
      return;
    }

    final current = _require();
    final index = current.notes.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final note = current.notes[index];
    // No timestamp bump, exactly as in the editor: ticking a list must not reorder
    // it.
    final updated = note.isCompleted
        ? note.copyWith(clearCompletedAt: true)
        : note.copyWith(completedAt: DateTime.now());
    final notes = [...current.notes]..[index] = updated;
    state = AsyncData(current.copyWith(notes: notes));
    _notesRepo.save(state.requireValue.notes);
  }

  /// Adds a note written in the widget's own composer.
  ///
  /// The same writer question as [toggleCompleted], and the same answer. The note
  /// lands at the top of the list, because it is the most recent thing in it, but
  /// it does not become the focused card - that is the editor's selection to make,
  /// and taking it from here would move the editor's cursor every time someone added
  /// a note from the desktop.
  Future<bool> addNote({required String title, required String body}) async {
    if (title.trim().isEmpty && body.trim().isEmpty) return false;

    if (await _shell.isEditorRunning()) {
      await _shell.requestCreateNote(title: title, body: body);
      return true;
    }

    final current = _require();
    final now = DateTime.now();
    final note = Note(
      // The same factory the editor uses, rather than something invented here: ids
      // only have to be unique within one profile folder, and this is the code that
      // already guarantees that.
      id: _ids.next(),
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    state = AsyncData(
      current.copyWith(notes: NotesRepository.sorted([...current.notes, note])),
    );
    _notesRepo.save(state.requireValue.notes);
    return true;
  }

  Future<void> setWidgetVisible({required bool visible}) async {
    state = AsyncData(_require().copyWith(visible: visible));
    await _applyWindowConfiguration();
  }

  void setWidgetVisibleFromPlatform({required bool visible}) {
    final current = _require();
    if (visible == current.visible) return;
    state = AsyncData(current.copyWith(visible: visible));
  }

  /// Starts the runner-side move loop, which tracks the cursor in screen space
  /// until the button comes up.
  ///
  /// The drag cannot be computed on this side of the channel. Flutter reports
  /// pointer positions relative to the view, so as soon as the window follows the
  /// cursor the reported delta shrinks; adding it to the start position lands the
  /// widget at a little over 40% of the distance asked for, and the error is not a
  /// mistake that can be corrected, it is missing information.
  Future<void> beginMove(Offset anchor) => _shell.beginWidgetMove(anchor);

  /// Starts the runner-side resize loop for [edge]. Same reasoning as [beginMove],
  /// and the runner also clamps the result to a size the widget can still be found
  /// and read at.
  Future<void> beginResize(ResizeEdge edge, Offset anchor) =>
      _shell.beginWidgetResize(edge, anchor);

  /// Lets the widget hold the keyboard while a note is written in it.
  Future<void> setComposeMode({required bool active}) =>
      _shell.setWidgetComposeMode(active: active);

  /// Pushes everything this surface has queued to disk before the process goes away.
  ///
  /// Includes notes.json, not just the widget's own state and the selection. This
  /// surface writes notes.json whenever it marks a task finished and there is no
  /// editor to do it, and that write goes through the same debounced queue as
  /// everything else - so quitting inside the debounce window would lose the
  /// toggle. It is a small thing to lose, and an invisible one: the tick would come
  /// back on screen undone.
  ///
  /// Called by the surface rather than from `onDispose`, because `onDispose` is
  /// synchronous and cannot await. See `AGENTS.md` §4.7 - this hazard predates the
  /// provider work and is not fixed by it.
  Future<void> flush() async {
    await _notesRepo.flush();
    await _widgetRepo.flush();
    await _selectionRepo.flush();
  }

  WidgetSurfaceState _require() => state.requireValue;
}

/// The widget surface's provider.
///
/// Declared here rather than collected in `providers.dart`, so that file does not
/// have to import this one to list it - see the note at the top of `providers.dart`.
final widgetProvider =
    AsyncNotifierProvider<WidgetNotifier, WidgetSurfaceState>(WidgetNotifier.new);