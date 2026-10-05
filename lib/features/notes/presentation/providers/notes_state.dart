import '../../domain/note.dart';
import '../../domain/repositories.dart';

/// A note that was just deleted and can still be brought back.
class PendingUndo {
  const PendingUndo(this.note, this.index);

  final Note note;

  /// Where it was in the most-recently-edited order, so undo puts it back in
  /// place rather than at the top of the list.
  final int index;
}

/// Editing state for the notes.
class NotesState {
  const NotesState({
    this.notes = const [],
    this.visible = const [],
    this.query = '',
    this.selectedId,
    this.corrupt,
    this.pendingUndo,
  });

  /// Every note, newest first.
  final List<Note> notes;

  /// The notes matching [query], newest first.
  final List<Note> visible;

  final String query;
  final String? selectedId;

  /// Set while the notes file could not be read. Every mutation is refused while
  /// this is non-null, which is the mechanism behind "refuses to start rather than
  /// replacing it with an empty one".
  final CorruptDataFileError? corrupt;

  final PendingUndo? pendingUndo;

  /// The note the editor is showing, or the most recent one when nothing is
  /// picked.
  Note? get selectedNote {
    if (selectedId != null) {
      for (final note in notes) {
        if (note.id == selectedId) return note;
      }
    }
    return notes.isEmpty ? null : notes.first;
  }

  /// The note the widget should render large.
  ///
  /// Prefers the most recent note that is still open. A big card with a line
  /// through it is a poor thing to greet someone with every time they glance at
  /// the desktop, and ticking off the top task should reveal the next one rather
  /// than move a finished note into the position that says "this is what you are
  /// working on". An explicit selection still wins, because that is a deliberate
  /// choice rather than a default. When everything is finished, the most recent
  /// note is used, so the card is never missing while notes exist.
  Note? get focusedNote {
    if (selectedId != null) return selectedNote;
    for (final note in notes) {
      if (!note.isCompleted) return note;
    }
    return notes.isEmpty ? null : notes.first;
  }

  /// True while the notes file could not be read.
  ///
  /// Checked by every mutating method, not only by the write path. The UI puts up a
  /// blocking screen in this state, so nothing should be able to reach here; the
  /// guard is what makes that true rather than merely likely, because an in-memory
  /// note added behind a refused write would still be lost.
  bool get isReadOnly => corrupt != null;

  /// Copies this state, overriding what is given.
  ///
  /// The three `clear*` flags exist because `selectedId`, `corrupt` and `pendingUndo`
  /// are nullable and `null` already means "leave it alone" to `??`. Without them,
  /// `select(null)` silently kept the previous selection - the field was never cleared
  /// - and deleting the last note left the editor pointing at a note that was no longer
  /// there.
  ///
  /// That is the class of bug a nullable field in a `copyWith` always has, and it was
  /// found by `notes_controller_test` rather than by reading this, which is the
  /// argument for keeping those 45 tests rather than replacing them.
  NotesState copyWith({
    List<Note>? notes,
    List<Note>? visible,
    String? query,
    String? selectedId,
    bool clearSelectedId = false,
    CorruptDataFileError? corrupt,
    bool clearCorrupt = false,
    PendingUndo? pendingUndo,
    bool clearPendingUndo = false,
  }) {
    return NotesState(
      notes: notes ?? this.notes,
      visible: visible ?? this.visible,
      query: query ?? this.query,
      selectedId: clearSelectedId ? null : (selectedId ?? this.selectedId),
      corrupt: clearCorrupt ? null : (corrupt ?? this.corrupt),
      pendingUndo: clearPendingUndo ? null : (pendingUndo ?? this.pendingUndo),
    );
  }

  /// Recomputes [visible] from [query] and [notes].
  ///
  /// Done here rather than in each mutator because the filter depends on the text
  /// of every note, so it has to be reapplied after an edit and not only after a
  /// search - the two are easy to conflate and getting it wrong hides a note the
  /// person can see in the file.
  NotesState withVisible() {
    if (query.trim().isEmpty) {
      return copyWith(visible: notes);
    }
    return copyWith(visible: notes.where((n) => n.contains(query)).toList());
  }
}
