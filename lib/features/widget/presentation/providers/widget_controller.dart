import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';
import 'package:win_notes/features/settings/domain/settings.dart';

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

/// Everything the widget surface owns, in its own isolate from the same files the editor writes.
/// One writer per file, so no lost updates [`docs/isolate_pattern.md` §2].
class WidgetSurfaceState {
  const WidgetSurfaceState({
    this.notes = const <Note>[],
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

  /// Whether dragging is refused; read by the surface to explain a locked drag.
  /// A field so a caller cannot forget settings and silently render unlocked.
  final bool positionLocked;

  /// The note rendered large; prefers the most recent open note, see [NotesState.focusedNote].
  Note? get focusedNote => focusedNoteIn(notes, selectedId);

  /// Notes in display order: most recent first, with the focused note pulled to the
  /// top so it reads as the card the widget is about.
  List<Note> get displayNotes => displayNotesIn(notes, selectedId);

  bool get hasAnyNoteWithText =>
      notes.any((Note n) => n.title.trim().isNotEmpty || n.body.trim().isNotEmpty);

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

/// The widget surface's state; never writes notes.json while an editor is open.
/// [toggleCompleted] and [addNote] ask the runner who owns the file, since the editor buffers keystrokes.
/// Decision is now made once, and readiness is the returned `AsyncValue`.
class WidgetNotifier extends AsyncNotifier<WidgetSurfaceState> {
  late final ShellChannel _shell;
  late final INotesRepository _notesRepo;
  late final IWidgetStateRepository _widgetRepo;
  late final ISelectionRepository _selectionRepo;

  final NoteIdFactory _ids = NoteIdFactory();
  Timer? _geometrySaveTimer;

  /// Set in [build] when the chosen folder could not be reached. Every note write
  /// checks it, because this surface is the writer when no editor is running and
  /// would otherwise put notes in the default folder.
  bool _storageMissing = false;

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

    final WidgetWindowState window = await _widgetRepo.load();
    final String? selectedId = _selectionRepo.readSelection();

    // A chosen folder that could not be reached: this surface would read and
    // write the default folder. It shows nothing rather than the wrong library,
    // and the editor is where the folder is reported (`storage_pattern.md` §3.0a).
    if (ref.read(appPathsProvider).unreachableDirectory != null) {
      _storageMissing = true;
      final WidgetSurfaceState hidden = WidgetSurfaceState(
        notes: const <Note>[],
        selectedId: null,
        window: window,
        visible: false,
        positionLocked: _positionLocked,
      );
      await _applyWindowConfiguration(hidden);
      return hidden;
    }

    final List<Note> notes = await _readNotes();

    WidgetSurfaceState next = WidgetSurfaceState(
      notes: notes,
      selectedId: selectedId,
      window: window,
      visible: false,
      positionLocked: _positionLocked,
    );

    // A saved position is restored by *telling the runner* to move there, not
    // by reading its bounds back. No read-back after it: `widget.setGeometry`
    // only queues the move. `docs/widget_pattern.md` §3.22 has the rest.
    if (window.left != null && window.top != null) {
      await _shell.setWidgetGeometry(NativeBounds(
        left: window.left!,
        top: window.top!,
        width: window.width ?? 0,
        height: window.height ?? 0,
      ));
    } else {
      // A first run has no saved geometry and nothing to drag from, so the
      // runner's own placement is the only position there is.
      final NativeBounds? live = await _shell.widgetBounds();
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
    }

    // An empty widget is never shown, since there would be nothing to look at.
    final bool shouldShow = next.hasAnyNoteWithText;
    final WidgetSurfaceState ready = next.copyWith(visible: shouldShow);

    // Applies palette/opacity to the runner, narrowed to four window fields.
    ref.listen(
      settingsProvider.select(
        (AsyncValue<SettingsState> v) => (
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
    final NotesLoadResult result = await _notesRepo.load();
    return switch (result) {
      NotesLoaded(:final List<Note> notes) => NotesRepository.sorted(notes),
      // A widget with nothing to show is not an error worth interrupting the
      // desktop for; the editor is where the file problem gets reported.
      NotesCorrupt() => const <Note>[],
    };
  }

  /// Applies the saved geometry to the runner once the window exists.
  Future<void> restoreGeometry() async {
    final WidgetWindowState window = state.requireValue.window;
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
    final LaunchInfo launch = ref.read(launchInfoProvider);
    final WinNotesSettings? settings = ref.read(settingsProvider).value?.settings;
    final int delay = settings?.autoStartDelayMs ?? 0;
    if (!launch.isAutostartLaunch || delay <= 0) return;
    await Future<void>.delayed(Duration(milliseconds: delay));
  }

  /// Re-reads `notes.json` and republishes visibility; public because tests cannot rely on the watcher.
  Future<void> reloadNotes() async {
    final WidgetSurfaceState? current = state.value;
    if (current == null) return;
    final List<Note> notes = await _readNotes();
    final bool shouldShow = notes.any(
      (Note n) => n.title.trim().isNotEmpty || n.body.trim().isNotEmpty,
    );
    state = AsyncData<WidgetSurfaceState>(current.copyWith(notes: notes, visible: shouldShow));
    if (shouldShow != current.visible) {
      await _applyWindowConfiguration();
    }
  }

  Future<void> _onNotesChangedExternally() => reloadNotes();
  void _onSelectionChangedExternally() {
    final WidgetSurfaceState? current = state.value;
    final String? next = _selectionRepo.cached;
    if (current == null || next == current.selectedId) return;
    state = AsyncData<WidgetSurfaceState>(current.copyWith(selectedId: next));
  }

  /// Tells the runner what the window looks like; [from] exists because `build` configures before `state` exists.
  Future<void> _applyWindowConfiguration([WidgetSurfaceState? from]) async {
    final WidgetSurfaceState? current = from ?? state.value;
    final WinNotesSettings? settings = ref.read(settingsProvider).value?.settings;
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
    if (_storageMissing) return;
    final WidgetSurfaceState current = _require();
    final WidgetWindowState window = current.window.copyWith(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
    );
    state = AsyncData<WidgetSurfaceState>(current.copyWith(window: window));
    // Dragging emits a WM_MOVE per pixel; only the last position is worth writing,
    // so persistence is coalesced rather than throttled in the runner.
    _geometrySaveTimer?.cancel();
    _geometrySaveTimer = Timer(const Duration(milliseconds: 250), () {
      _widgetRepo.save(state.requireValue.window);
    });
  }

  void rememberScroll(double offset) {
    if (_storageMissing) return;
    final WidgetSurfaceState current = _require();
    if ((offset - current.window.scrollOffset).abs() < 0.5) return;
    final WidgetWindowState window = current.window.copyWith(scrollOffset: offset);
    state = AsyncData<WidgetSurfaceState>(current.copyWith(window: window));
    // Writes the whole state including the note selection, so a tap that changes
    // the selection and a scroll that changes the offset can queue on top of each
    // other. The debounced writer collapses them.
    _widgetRepo.save(window);
  }

  /// Focusing a card from the widget is a normal thing to want, and the editor picks
  /// the change up through the same file.
  void focusNote(String id) {
    final WidgetSurfaceState current = _require();
    if (current.selectedId == id || _storageMissing) return;
    state = AsyncData<WidgetSurfaceState>(current.copyWith(selectedId: id));
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

    if (_storageMissing) return;
    final WidgetSurfaceState current = _require();
    final int index = current.notes.indexWhere((Note n) => n.id == id);
    if (index < 0) return;
    final Note note = current.notes[index];
    // No timestamp bump, exactly as in the editor: ticking a list must not reorder
    // it.
    final Note updated = note.isCompleted
        ? note.copyWith(clearCompletedAt: true)
        : note.copyWith(completedAt: DateTime.now());
    final List<Note> notes = <Note>[...current.notes]..[index] = updated;
    state = AsyncData<WidgetSurfaceState>(current.copyWith(notes: notes));
    _notesRepo.save(state.requireValue.notes);
  }

  /// Adds a composer note; same writer rule as [toggleCompleted], without stealing editor selection.
  Future<bool> addNote({required String title, required String body}) async {
    if (title.trim().isEmpty && body.trim().isEmpty) return false;
    if (_storageMissing) return false;

    if (await _shell.isEditorRunning()) {
      await _shell.requestCreateNote(title: title, body: body);
      return true;
    }

    final WidgetSurfaceState current = _require();
    final DateTime now = DateTime.now();
    final Note note = Note(
      // The same factory the editor uses, rather than something invented here: ids
      // only have to be unique within one profile folder, and this is the code that
      // already guarantees that.
      id: _ids.next(),
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    state = AsyncData<WidgetSurfaceState>(
      current.copyWith(notes: NotesRepository.sorted(<Note>[...current.notes, note])),
    );
    _notesRepo.save(state.requireValue.notes);
    return true;
  }

  Future<void> setWidgetVisible({required bool visible}) async {
    state = AsyncData<WidgetSurfaceState>(_require().copyWith(visible: visible));
    await _applyWindowConfiguration();
  }

  void setWidgetVisibleFromPlatform({required bool visible}) {
    final WidgetSurfaceState current = _require();
    if (visible == current.visible) return;
    state = AsyncData<WidgetSurfaceState>(current.copyWith(visible: visible));
  }

  /// Starts the runner-side move loop; Dart lacks the screen-space cursor to compute it.
  Future<void> beginMove(Offset anchor) => _shell.beginWidgetMove(anchor);

  /// Starts the runner-side resize loop for [edge]. Same reasoning as [beginMove],
  /// and the runner also clamps the result to a size the widget can still be found
  /// and read at.
  Future<void> beginResize(ResizeEdge edge, Offset anchor) =>
      _shell.beginWidgetResize(edge, anchor);

  /// Lets the widget hold the keyboard while a note is written in it.
  Future<void> setComposeMode({required bool active}) =>
      _shell.setWidgetComposeMode(active: active);

  /// Pushes queued writes to disk before exit, including notes.json toggles.
  /// Called by the surface, not `onDispose`, which cannot await [`AGENTS.md` §4.7].
  Future<void> flush() async {
    await _notesRepo.flush();
    await _widgetRepo.flush();
    await _selectionRepo.flush();
  }

  WidgetSurfaceState _require() => state.requireValue;
}

/// The widget surface's provider, declared here so `providers.dart` need not import this.
final AsyncNotifierProvider<WidgetNotifier, WidgetSurfaceState> widgetProvider =
    AsyncNotifierProvider<WidgetNotifier, WidgetSurfaceState>(WidgetNotifier.new);