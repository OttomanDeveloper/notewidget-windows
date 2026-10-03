import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/note.dart';
import '../data/notes_repository.dart';

/// A note that was just deleted and can still be brought back.
class PendingUndo {
  const PendingUndo(this.note, this.index);

  final Note note;

  /// Where it was in the most-recently-edited order, so undo puts it back in
  /// place rather than at the top of the list.
  final int index;
}

/// Editing state for the notes.
///
/// Only the editor surface creates one. The widget surface reads notes.json
/// directly and never runs this, which is what keeps a single writer.
class NotesController extends ChangeNotifier {
  NotesController({
    required NotesRepository repository,
    bool watchExternal = false,
  }) : _repository = repository,
       _watchExternal = watchExternal {
    _factory = NoteIdFactory();
    if (_watchExternal) repository.watch(_onExternalChange);
  }

  final NotesRepository _repository;
  final bool _watchExternal;
  late final NoteIdFactory _factory;

  List<Note> _notes = const [];
  List<Note> _visible = const [];
  String _query = '';
  String? _selectedId;
  CorruptDataFileError? _corrupt;
  PendingUndo? _pendingUndo;
  Timer? _undoTimer;
  bool _loaded = false;

  /// Set while the notes file could not be read. Every mutation is refused
  /// while this is non-null, which is the mechanism behind "refuses to start
  /// rather than replacing it with an empty one".
  CorruptDataFileError? get corrupt => _corrupt;

  bool get isLoaded => _loaded;
  String get query => _query;

  /// Every note, newest first.
  List<Note> get notes => _notes;

  /// The notes matching the current search, newest first.
  List<Note> get visibleNotes => _visible;

  String? get selectedId => _selectedId;

  /// The note the editor is showing, or the most recent one when nothing is
  /// picked.
  Note? get selectedNote {
    if (_selectedId != null) {
      for (final note in _notes) {
        if (note.id == _selectedId) return note;
      }
    }
    return _notes.isEmpty ? null : _notes.first;
  }

  /// The note the widget should render large. Falls back to the most recent
  /// note so the focused card is never missing while notes exist.
  Note? get focusedNote => selectedNote;

  PendingUndo? get pendingUndo => _pendingUndo;

  Future<void> load() async {
    final result = await _repository.load();
    switch (result) {
      case NotesLoaded(:final notes):
        _corrupt = null;
        _notes = NotesRepository.sorted(notes);
        _recomputeVisible();
        // A selection that points at a note which no longer exists would leave
        // the editor showing nothing at all.
        if (_selectedId != null && selectedNote == null) {
          _selectedId = _notes.isEmpty ? null : _notes.first.id;
        }
      case NotesCorrupt(:final error):
        // Mapped to the UI-facing type here so nothing above this layer has to
        // know that reading a file can throw from dart:io.
        _corrupt = CorruptDataFileError(error.path, error.reason);
        _notes = const [];
        _visible = const [];
    }
    _loaded = true;
    notifyListeners();
  }

  /// Re-reads after the other surface changed the file.
  void _onExternalChange() {
    unawaited(load());
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _recomputeVisible();
    notifyListeners();
  }

  void _recomputeVisible() {
    if (_query.trim().isEmpty) {
      _visible = _notes;
    } else {
      _visible = _notes.where((n) => n.contains(_query)).toList();
    }
  }

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// True while the notes file could not be read.
  ///
  /// Checked by every mutating method, not only by the write path. The UI puts
  /// up a blocking screen in this state, so nothing should be able to reach
  /// here; the guard is what makes that true rather than merely likely, because
  /// an in-memory note added behind a refused write would still be lost.
  bool get isReadOnly => _corrupt != null;

  /// Creates a note and returns it, already selected, so typing can start
  /// immediately.
  ///
  /// Returns null while the file is unreadable: the note would have nowhere to
  /// go, and a note that exists on screen but not on disk is worse than no note.
  Note? createNote() {
    if (_corrupt != null) return null;
    final now = _nextStamp();
    final note = Note(
      id: _factory.next(),
      title: '',
      body: '',
      createdAt: now,
      updatedAt: now,
    );
    _notes = NotesRepository.sorted([..._notes, note]);
    _selectedId = note.id;
    _recomputeVisible();
    _persist();
    notifyListeners();
    return note;
  }

  /// A timestamp guaranteed to sort newer than every note already held.
  ///
  /// The clock is only millisecond-resolution and the ordering tie-breaks by
  /// id, which is random. Without this, editing a note in the same millisecond
  /// another note was last touched would leave the edited note second instead of
  /// first - a coin flip on a promise the whole UI makes, and the reason the
  /// widget might not show the note you are looking at as its large card.
  /// Stepping one millisecond past the current newest makes "the note you just
  /// touched is on top" an invariant instead of a probability.
  DateTime _nextStamp() {
    final newest = _notes.isEmpty ? null : _notes.first.updatedAt;
    final now = DateTime.now();
    if (newest == null || now.isAfter(newest)) return now;
    return newest.add(const Duration(milliseconds: 1));
  }

  /// Creates one empty note if there are none at all, which is what makes the
  /// first launch open with the cursor already in a note.
  void ensureAtLeastOneNote() {
    if (_notes.isNotEmpty) return;
    createNote();
  }

  void updateNote(String id, {String? title, String? body}) {
    if (_corrupt != null) return;
    final index = _notes.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final note = _notes[index];
    final nextTitle = title ?? note.title;
    final nextBody = body ?? note.body;
    if (nextTitle == note.title && nextBody == note.body) return;

    note.title = nextTitle;
    note.body = nextBody;
    note.updatedAt = _nextStamp();
    _notes = NotesRepository.sorted(_notes);
    // The search filter depends on the text, so it has to be reapplied.
    _recomputeVisible();
    _persist();
    notifyListeners();
  }

  /// Deletes a note and holds it for undo.
  ///
  /// The caller is responsible for having asked for confirmation first; this
  /// method is the actual removal.
  void deleteNote(String id) {
    if (_corrupt != null) return;
    final index = _notes.indexWhere((n) => n.id == id);
    if (index < 0) return;

    final removed = _notes[index];
    _notes = [..._notes]..removeAt(index);
    _recomputeVisible();

    // Replacing the pending undo rather than queueing it: undo applies to the
    // most recent action, and holding two would make the toast ambiguous.
    _pendingUndo = PendingUndo(removed, index);
    _undoTimer?.cancel();
    _undoTimer = Timer(NotesController.undoWindow, () {
      _pendingUndo = null;
      notifyListeners();
    });

    if (_selectedId == id) {
      _selectedId = _notes.isEmpty ? null : _notes.first.id;
    }
    _persist();
    notifyListeners();
  }

  static const Duration undoWindow = Duration(seconds: 6);

  /// Brings the last deleted note back where it was.
  bool undoDelete() {
    if (_corrupt != null) return false;
    final pending = _pendingUndo;
    if (pending == null) return false;

    _undoTimer?.cancel();
    _undoTimer = null;
    _pendingUndo = null;

    final restored = pending.note.copy();
    // Restoring the timestamp keeps it in its original place in the
    // most-recently-edited order, which is the whole point of undo.
    final next = [..._notes];
    final target = pending.index.clamp(0, next.length);
    next.insert(target, restored);
    _notes = NotesRepository.sorted(next);
    _selectedId = restored.id;
    _recomputeVisible();
    _persist();
    notifyListeners();
    return true;
  }

  void clearPendingUndo() {
    if (_pendingUndo == null) return;
    _undoTimer?.cancel();
    _undoTimer = null;
    _pendingUndo = null;
    notifyListeners();
  }

  /// Replaces every note, used by import.
  void replaceAll(List<Note> incoming) {
    // The one mutation allowed while the file is unreadable: a restore is how a
    // person deliberately replaces a file the app refused to touch on its own.
    // The caller has already lifted the block via NotesRepository.unblock().
    _notes = NotesRepository.sorted(incoming);
    _selectedId = _notes.isEmpty ? null : _notes.first.id;
    _recomputeVisible();
    _persist();
    notifyListeners();
  }

  /// Adds notes alongside the existing ones, used by a restore from backup.
  void merge(List<Note> incoming) {
    if (incoming.isEmpty) return;
    _notes = NotesRepository.sorted([..._notes, ...incoming]);
    _selectedId = incoming.first.id;
    _recomputeVisible();
    _persist();
    notifyListeners();
  }

  void _persist() {
    if (_corrupt != null) return;
    _repository.save(_notes);
  }

  /// Pushes anything queued to disk. Called when the app is quitting.
  Future<void> flush() => _repository.flush();

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }
}

/// Local mirror of CorruptDataFile, so the UI does not have to import dart:io.
class CorruptDataFileError {
  const CorruptDataFileError(this.path, this.reason);
  final String path;
  final String reason;
}