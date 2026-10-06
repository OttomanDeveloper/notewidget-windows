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

    /// The note the widget renders large: newest open note (explicit selection
    /// wins); most recent when all are finished, so the card never goes missing.
  Note? get focusedNote {
    if (selectedId != null) return selectedNote;
    for (final note in notes) {
      if (!note.isCompleted) return note;
    }
    return notes.isEmpty ? null : notes.first;
  }

    /// True while the notes file could not be read. Checked by every mutator,
    /// so no in-memory note is added behind a refused write and then lost.
  bool get isReadOnly => corrupt != null;

    /// Copies this state, overriding what is given. The `clear*` flags exist
    /// because `null` means "leave it alone" to `??`.
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

    /// Recomputes [visible] from [query] and [notes]. Here, not per mutator:
    /// edits must reapply it too, or visible notes go missing.
  NotesState withVisible() {
    if (query.trim().isEmpty) {
      return copyWith(visible: notes);
    }
    return copyWith(visible: notes.where((n) => n.contains(query)).toList());
  }
}
