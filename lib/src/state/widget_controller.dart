import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../data/note.dart';
import '../data/notes_repository.dart';
import '../data/settings_repository.dart';
import '../platform/shell_channel.dart';
import 'settings_controller.dart';

/// Everything the widget surface owns.
///
/// The widget runs in its own isolate and has its own copy of the state, read
/// from the same files the editor writes. That is not a shortcut around shared
/// memory: it is the reason there is exactly one writer per file and therefore
/// no lost updates, ever.
class WidgetController extends ChangeNotifier {
  WidgetController({
    required ShellChannel shell,
    required SettingsController settings,
    required NotesRepository notesRepo,
    required WidgetStateRepository widgetRepo,
    required SelectionRepository selectionRepo,
    required this.isAutostartLaunch,
    required this.animationsEnabled,
    required this.acrylicSupported,
    required this.isSystemDark,
    bool watchExternal = true,
  })  : _shell = shell,
        _settings = settings,
        _notesRepo = notesRepo,
        _widgetRepo = widgetRepo,
        _selectionRepo = selectionRepo {
    // Always true in the app: the widget surface has no other way to learn that
    // the editor changed something. Tests turn it off because the directory
    // watchers use real timers that flutter_test's fake clock never advances.
    if (watchExternal) {
      _selectionRepo.watch(_onSelectionChangedExternally);
      _notesRepo.watch(_onNotesChangedExternally);
    }
    settings.addListener(_onSettingsChanged);
  }

  final ShellChannel _shell;
  final SettingsController _settings;
  final NotesRepository _notesRepo;
  final WidgetStateRepository _widgetRepo;
  final SelectionRepository _selectionRepo;

  final bool isAutostartLaunch;
  final bool animationsEnabled;
  final bool acrylicSupported;
  final bool isSystemDark;

  List<Note> _notes = const [];
  String? _selectedId;
  WidgetWindowState _state = WidgetWindowState.empty;
  bool _widgetVisible = true;
  bool _ready = false;
  Timer? _geometrySaveTimer;

  List<Note> get notes => _notes;
  bool get isReady => _ready;
  bool get widgetVisible => _widgetVisible;
  WidgetWindowState get state => _state;

  /// Whether dragging the widget is currently refused.
  ///
  /// Read by the surface so it can tell someone who drags a locked widget why
  /// nothing happened, instead of leaving them to wonder.
  bool get positionLocked => _settings.settings.widgetPositionLocked;

  /// The note rendered large. Everything else in the widget is a compact card.
  ///
  /// Prefers the most recent note that is still open, so ticking off the task in
  /// the big card reveals the next one instead of leaving a line through the
  /// middle of the thing you look at most. See [NotesController.focusedNote] for
  /// the same rule and the reasoning.
  Note? get focusedNote {
    if (_selectedId != null) {
      for (final note in _notes) {
        if (note.id == _selectedId) return note;
      }
    }
    for (final note in _notes) {
      if (!note.isCompleted) return note;
    }
    return _notes.isEmpty ? null : _notes.first;
  }

  /// Notes in display order: most recent first, with the focused note pulled to
  /// the top so it reads as the card the widget is about.
  List<Note> get displayNotes {
    final focused = focusedNote;
    if (focused == null) return const [];
    final rest = _notes.where((n) => n.id != focused.id).toList();
    return [focused, ...rest];
  }

  bool get hasAnyNoteWithText =>
      _notes.any((n) => n.title.trim().isNotEmpty || n.body.trim().isNotEmpty);

  Future<void> load() async {
    _state = await _widgetRepo.load();
    _selectedId = _selectionRepo.readSelection();
    await _reloadNotes();

    // Ask the runner where the window really is. A first run has no saved
    // geometry, and without this the widget's idea of its own position stays
    // empty - so the first drag of a new install would have nothing to move
    // relative to and would silently do nothing.
    final live = await _shell.widgetBounds();
    if (live != null) {
      _state = _state.copyWith(
        left: live.left,
        top: live.top,
        width: live.width,
        height: live.height,
      );
    }

    // An empty widget is never shown, since there would be nothing to look at.
    _widgetVisible = hasAnyNoteWithText;
    _ready = true;
    notifyListeners();

    await _applyWindowConfiguration(visible: _widgetVisible);
  }

  Future<void> _reloadNotes() async {
    final result = await _notesRepo.load();
    _notes = switch (result) {
      NotesLoaded(:final notes) => NotesRepository.sorted(notes),
      // A widget with nothing to show is not an error worth interrupting the
      // desktop for; the editor is where the file problem gets reported.
      NotesCorrupt() => const [],
    };
  }

  void _onNotesChangedExternally() {
    unawaited(_reloadNotes().then((_) {
      final shouldShow = hasAnyNoteWithText;
      notifyListeners();
      if (shouldShow != _widgetVisible) {
        _widgetVisible = shouldShow;
        unawaited(_applyWindowConfiguration(visible: shouldShow));
      }
    }));
  }

  void _onSelectionChangedExternally() {
    final next = _selectionRepo.cached;
    if (next == _selectedId) return;
    _selectedId = next;
    notifyListeners();
  }

  void _onSettingsChanged() {
    unawaited(_applyWindowConfiguration(visible: _widgetVisible));
  }

  Future<void> _applyWindowConfiguration({required bool visible}) async {
    final settings = _settings.settings;
    await _shell.configureWidget(
      alwaysOnTop: settings.alwaysOnTop,
      opacity: settings.widgetOpacity,
      // The runner downgrades this itself when the build cannot do acrylic, so
      // asking for it unconditionally keeps the fallback in one place.
      acrylic: settings.acrylicEnabled,
      rounded: true,
      positionLocked: settings.widgetPositionLocked,
      visible: visible && settings.widgetOpacity > 0,
    );
  }

  /// Applies the autostart delay, which only ever applies to the autostart
  /// launch. Launching by hand shows the widget immediately.
  Future<void> applyStartupDelay() async {
    final delay = _settings.settings.autoStartDelayMs;
    if (!isAutostartLaunch || delay <= 0) return;
    await Future<void>.delayed(Duration(milliseconds: delay));
  }

  /// Called when the native side reports the widget was moved or resized.
  void onGeometryChanged(NativeBounds bounds) {
    _state = _state.copyWith(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
    );
    // Dragging emits a WM_MOVE per pixel; only the last position is worth
    // writing, so persistence is coalesced rather than throttled in the runner.
    _geometrySaveTimer?.cancel();
    _geometrySaveTimer = Timer(const Duration(milliseconds: 250), () {
      _widgetRepo.save(_state);
    });
    notifyListeners();
  }

  void rememberScroll(double offset) {
    if ((offset - _state.scrollOffset).abs() < 0.5) return;
    _state = _state.copyWith(scrollOffset: offset);
    // Writes the whole state including the note selection, so a tap that
    // changes the selection and a scroll that changes the offset can queue on
    // top of each other. The debounced writer collapses them.
    _widgetRepo.save(_state);
  }

  /// Focusing a card from the widget is a normal thing to want, and the editor
  /// picks the change up through the same file.
  void focusNote(String id) {
    if (_selectedId == id) return;
    _selectedId = id;
    _selectionRepo.setSelection(id);
    notifyListeners();
  }

  /// Marks a note finished or unfinished, from the widget.
  ///
  /// notes.json has exactly one writer, and normally that is the editor. This
  /// method does not simply write the file, because doing so would race it: the
  /// editor holds keystrokes in memory for a quarter of a second before they
  /// reach disk, so a toggle written from here in that window would overwrite
  /// them and silently lose whatever was typed.
  ///
  /// So the runner is asked who owns the file. With an editor open the request
  /// goes to the editor isolate, which toggles and persists like any other edit,
  /// and this surface learns about it through the same directory watcher it
  /// already uses. With no editor open there is nothing to lose - no other
  /// writer, no buffered edits - and this surface writes directly rather than
  /// refusing to work.
  ///
  /// The two branches cannot both write, because the decision is made from the
  /// runner's own view of whether an editor window exists at that moment.
  Future<void> toggleCompleted(String id) async {
    if (await _shell.isEditorRunning()) {
      await _shell.requestToggleCompleted(id);
      return;
    }

    final index = _notes.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final note = _notes[index];
    // No timestamp bump, exactly as in the editor: ticking a list must not
    // reorder it.
    note.completedAt = note.isCompleted ? null : DateTime.now();
    notifyListeners();
    _notesRepo.save(_notes);
  }

  Future<void> setWidgetVisible(bool visible) async {
    _widgetVisible = visible;
    notifyListeners();
    await _applyWindowConfiguration(visible: visible);
  }

  /// Applies the saved geometry to the runner once the window exists.
  Future<void> restoreGeometry() async {
    if (!_state.hasGeometry) return;
    await _shell.setWidgetGeometry(NativeBounds(
      left: _state.left!,
      top: _state.top!,
      width: _state.width!,
      height: _state.height!,
    ));
  }

  void setWidgetVisibleFromPlatform(bool visible) {
    if (visible == _widgetVisible) return;
    _widgetVisible = visible;
    notifyListeners();
  }

  /// Starts the runner-side move loop, which tracks the cursor in screen space
  /// until the button comes up.
  ///
  /// The drag cannot be computed on this side of the channel. Flutter reports
  /// pointer positions relative to the view, so as soon as the window follows
  /// the cursor the reported delta shrinks; adding it to the start position
  /// lands the widget at a little over 40% of the distance asked for, and the
  /// error is not a mistake that can be corrected, it is missing information.
  Future<void> beginMove(Offset anchor) => _shell.beginWidgetMove(anchor);

  /// Starts the runner-side resize loop for [edge]. Same reasoning as
  /// [beginMove], and the runner also clamps the result to a size the widget
  /// can still be found and read at.
  Future<void> beginResize(ResizeEdge edge, Offset anchor) =>
      _shell.beginWidgetResize(edge, anchor);

  /// Pushes everything this surface has queued to disk before the process goes
  /// away.
  ///
  /// Includes notes.json, not just the widget's own state and the selection.
  /// This surface writes notes.json whenever it marks a task finished and there
  /// is no editor to do it, and that write goes through the same debounced queue
  /// as everything else - so quitting inside the debounce window would lose the
  /// toggle. It is a small thing to lose, and an invisible one: the tick would
  /// come back on screen undone.
  Future<void> flush() async {
    await _notesRepo.flush();
    await _widgetRepo.flush();
  }

  bool _released = false;

  /// Tears down the file handles this controller owns.
  ///
  /// Async, and called explicitly from the surface rather than from [dispose],
  /// because flushing has to survive the object being collected: a write queued
  /// by the last scroll before a window closed still has to reach disk.
  ///
  /// Idempotent, so a surface can call it from its own teardown without having
  /// to know whether something else already did.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    _geometrySaveTimer?.cancel();
    _settings.removeListener(_onSettingsChanged);
    await _widgetRepo.dispose();
    await _selectionRepo.dispose();
    await _notesRepo.dispose();
  }

  @override
  void dispose() {
    _geometrySaveTimer?.cancel();
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}