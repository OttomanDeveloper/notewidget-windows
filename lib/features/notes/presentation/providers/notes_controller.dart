import 'dart:async';

import 'package:riverpod/riverpod.dart';

import '../../domain/note.dart';
import '../../domain/repositories.dart';
import '../../data/notes_repository.dart';
import '../../../../core/utils/app_providers.dart';
import './notes_providers.dart';

import 'notes_state.dart';

export 'notes_state.dart';

/// The editor surface's notes. The only writer of notes.json. Corruption is a
/// state with a recovery screen, not an `AsyncError`; loading flags come from
/// the surrounding `AsyncValue`.
class NotesNotifier extends AsyncNotifier<NotesState> {
  static const Duration undoWindow = Duration(seconds: 6);

  late final INotesRepository _repository;
  final NoteIdFactory _factory = NoteIdFactory();
  Timer? _undoTimer;

  /// Whether a rolling backup of the previous good file exists.
  ///
  /// On the notifier (asks the repository) so notes changes don't re-read disk.
  bool get hasBackup => _repository.backupPath != null;

  @override
  Future<NotesState> build() async {
    _repository = ref.watch(notesRepositoryProvider);

    // Only the widget surface watches notes.json; the editor is its writer and
    // re-reading its own debounced write would fight the debounce.
    if (ref.watch(isWidgetSurfaceProvider)) {
      _repository.watch(_onExternalChange);
    }

    ref.onDispose(() => _undoTimer?.cancel());

    final NotesState loaded = _apply(await _repository.load());
    // First launch opens with a note already focused, so typing is the very first
    // thing that happens.
    if (loaded.corrupt == null) {
      NotesState next = loaded;
      if (next.notes.isEmpty) {
        next = _insert(next, _blankNote(next.notes));

        // ...and it is written, which `_insert` does not do: an in-memory-only
        // note gets a fresh id next launch, orphaning the widget's selection,
        // and a launch closed without typing would leave no file at all.
        _repository.save(next.notes);
      }
      next = next.copyWith(selectedId: _selectionOrNewest(next));
      return next.withVisible();
    }
    return loaded;
  }

  /// Re-reads notes.json and replaces the state. Separate from `build`:
  /// invalidating would lose the undo timer and re-run startup per keystroke.
  Future<void> reload() async {
    state = AsyncData(_apply(await _repository.load()));
  }
  /// Where the selection lands after a load or deletion: resolved to the newest
  /// note or null, so the editor never shows nothing at all.
  String? _selectionOrNewest(NotesState s) {
    if (s.selectedId != null && s.selectedNote != null) return s.selectedId;
    return s.notes.isEmpty ? null : s.notes.first.id;
  }

  /// The restore path is the one place a write is allowed while the file is
  /// unreadable, and only because a caller has deliberately chosen a file to
  /// replace one the app refused to touch on its own.
  void _unblock() => _repository.unblock();

  /// Whether the widget's own copy of the notes is usable. Never true on the
  /// editor surface, which does not read notes.json through this provider.
  bool get hasAnyNoteWithText =>
      (state.value?.notes ?? const <Note>[])
          .any((Note n) => n.title.trim().isNotEmpty || n.body.trim().isNotEmpty);

  /// Whether notes.json is currently unreadable. The import path needs this:
  /// a hand-chosen backup is the one thing allowed to replace a refused file.
  bool get hasReadOnlyFile => state.value?.isReadOnly ?? false;

  NotesState _require() => state.requireValue;

  /// Applies a read result. The corrupt case already carries the domain error,
  /// so nothing above this layer meets the file system face to face.
  NotesState _apply(NotesLoadResult result) {
    return switch (result) {
      NotesLoaded(:final List<Note> notes) =>
        // A fresh state, so `selectedId` is null: any selection from the previous
        // load died with that object and cannot point at a note id that is gone.
        NotesState(notes: NotesRepository.sorted(notes)),
      NotesCorrupt(:final CorruptDataFileError error) => NotesState(corrupt: error),
    };
  }

  /// Re-reads after the other surface changed the file.
  void _onExternalChange() {
    unawaited(reload());
  }

  /// Tries the read again. For locks outlasting the startup wait: a button
  /// instead of "quit and try again".
  Future<void> retryLoad() async {
    await reload();
  }

  /// Puts the rolling backup back, if there is one. Offered first: it needs
  /// nothing from the person, and atomic writes mean it is very likely intact.
  Future<RecoveryOutcome> restoreBackup() async {
    if (_require().corrupt == null) return RecoveryOutcome.restoredBackup;
    final int? recovered = await _repository.restoreBackup();
    if (recovered == null) return RecoveryOutcome.nothingToRecover;
    await retryLoad();
    return RecoveryOutcome.restoredBackup;
  }

  /// Moves the unreadable file aside and starts over, keeping the old one. A
  /// refusal with no way out is a trap; the damaged file is kept, timestamped.
  Future<({RecoveryOutcome outcome, String? keptAt})> startFresh() async {
    final NotesState current = _require();
    final String? keptAt = await _repository.setAsideAndStartFresh();
    if (current.corrupt != null && keptAt == null) {
      final bool stillThere = _repository.backupPath != null;
      return (
        outcome: RecoveryOutcome.fileIsHeld,
        keptAt: stillThere ? _repository.path : null,
      );
    }

    _undoTimer?.cancel();
    // Creates a valid, empty document, so the next thing that happens is not
    // another refusal.
    final Note blank = _blankNote(const <Note>[]);
    final NotesState next = NotesState(
      notes: NotesRepository.sorted(<Note>[blank]),
      selectedId: blank.id,
    );
    state = AsyncData(next.withVisible());
    _repository.save(next.notes);
    return (outcome: RecoveryOutcome.startedFresh, keptAt: keptAt);
  }

  void setQuery(String value) {
    final NotesState current = _require();
    if (current.query == value) return;
    state = AsyncData(current.copyWith(query: value).withVisible());
  }

  void select(String? id) {
    final NotesState current = _require();
    if (current.selectedId == id) return;
    // `clearSelectedId`, not `selectedId: null` - see `NotesState.copyWith`.
    state = AsyncData(
      current.copyWith(selectedId: id, clearSelectedId: id == null),
    );
  }

  /// A new, empty note. Takes existing notes rather than reading `state`: `build`
  /// calls this while `state` is still `AsyncLoading`, which threw and retried silently.
  Note _blankNote(List<Note> existing) {
    final DateTime now = _nextStampFor(existing);
    return Note(
      id: _factory.next(),
      title: '',
      body: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Creates a note and returns it, already selected, so typing can start
  /// immediately. Null while unreadable: a note on screen but not on disk is worse.
  Note? createNote() {
    final NotesState current = _require();
    if (current.corrupt != null) return null;
    final Note note = _blankNote(current.notes);
    NotesState next = _insert(current, note);
    next = next.copyWith(selectedId: note.id);
    state = AsyncData(next.withVisible());
    _repository.save(next.notes);
    return note;
  }

  NotesState _insert(NotesState s, Note note) {
    return s.copyWith(notes: NotesRepository.sorted(<Note>[...s.notes, note]));
  }

  /// A timestamp guaranteed to sort newer than every note held. Steps one
  /// millisecond past the newest, so "just touched is on top" is invariant.
  DateTime _nextStampFor(List<Note> existing) {
    final DateTime? newest = existing.isEmpty ? null : existing.first.updatedAt;
    final DateTime now = DateTime.now();
    if (newest == null || now.isAfter(newest)) return now;
    return newest.add(const Duration(milliseconds: 1));
  }

  /// Adds a note with text already in it, without changing the selection.
  /// For widget-written notes; unlike [createNote], taking no selection.
  void addNote({required String title, required String body}) {
    final NotesState current = _require();
    if (current.corrupt != null) return;
    if (title.trim().isEmpty && body.trim().isEmpty) return;

    final DateTime now = _nextStampFor(current.notes);
    final Note note = Note(
      id: _factory.next(),
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    final NotesState next = _insert(current, note);
    state = AsyncData(next.withVisible());
    _repository.save(next.notes);
  }

  void updateNote(String id, {String? title, String? body}) {
    final NotesState current = _require();
    if (current.corrupt != null) return;
    final int index = current.notes.indexWhere((Note n) => n.id == id);
    if (index < 0) return;
    final Note note = current.notes[index];
    final String nextTitle = title ?? note.title;
    final String nextBody = body ?? note.body;
    if (nextTitle == note.title && nextBody == note.body) return;

    final Note updated = note.copyWith(
      title: nextTitle,
      body: nextBody,
      updatedAt: _nextStampFor(current.notes),
    );
    final List<Note> notes = <Note>[...current.notes]..[index] = updated;
    final NotesState next = current.copyWith(
      notes: NotesRepository.sorted(notes),
    );
    // The search filter depends on the text, so it has to be reapplied.
    state = AsyncData(next.withVisible());
    _repository.save(next.notes);
  }

  /// Flips a note between finished and unfinished. Never touches [Note.updatedAt]:
  /// finishing is a state change, not an edit, so the list never reshuffles.
  void toggleCompleted(String id) {
    final NotesState current = _require();
    if (current.corrupt != null) return;
    final int index = current.notes.indexWhere((Note n) => n.id == id);
    if (index < 0) return;
    final Note note = current.notes[index];
    final Note updated = note.isCompleted
        ? note.copyWith(clearCompletedAt: true)
        : note.copyWith(completedAt: DateTime.now());
    // A new list identity: `AnimatedBuilder` compares by identity, so reusing
    // the same list would rebuild nothing and the strike-through would not appear.
    final List<Note> notes = <Note>[...current.notes]..[index] = updated;
    state = AsyncData(current.copyWith(notes: notes));
    _repository.save(state.requireValue.notes);
  }

  /// Turns Markdown rendering on or off for one note. Presentation only: the
  /// source is never rewritten. Bumps `updatedAt`, unlike [toggleCompleted].
  void setMarkdown(String id, {required bool enabled}) {
    final NotesState current = _require();
    if (current.corrupt != null) return;
    final int index = current.notes.indexWhere((Note n) => n.id == id);
    if (index < 0) return;
    final Note note = current.notes[index];
    if (note.markdown == enabled) return;
    final Note updated = note.copyWith(
      markdown: enabled,
      updatedAt: DateTime.now(),
    );
    final List<Note> notes = <Note>[...current.notes]..[index] = updated;
    final NotesState next = current.copyWith(notes: notes);
    state = AsyncData(next.withVisible());
    _repository.save(state.requireValue.notes);
  }

  /// Deletes a note and holds it for undo.
  ///
  /// The caller confirms first; this is the removal.
  void deleteNote(String id) {
    final NotesState current = _require();
    if (current.corrupt != null) return;
    final int index = current.notes.indexWhere((Note n) => n.id == id);
    if (index < 0) return;

    final Note removed = current.notes[index];
    final List<Note> remaining = <Note>[...current.notes]..removeAt(index);

    // Replacing the pending undo rather than queueing it: undo applies to the most
    // recent action, and holding two would make the toast ambiguous.
    _undoTimer?.cancel();
    final PendingUndo pending = PendingUndo(removed, index);
    _undoTimer = Timer(undoWindow, clearPendingUndo);

    NotesState next = current.copyWith(notes: remaining, pendingUndo: pending);
    if (current.selectedId == id) {
      final String? replacement = remaining.isEmpty ? null : remaining.first.id;
      next = next.copyWith(
        selectedId: replacement,
        clearSelectedId: replacement == null,
      );
    }
    state = AsyncData(next.withVisible());
    _repository.save(state.requireValue.notes);
  }

  /// Brings the last deleted note back where it was.
  bool undoDelete() {
    final NotesState current = _require();
    if (current.corrupt != null) return false;
    final PendingUndo? pending = current.pendingUndo;
    if (pending == null) return false;

    _undoTimer?.cancel();
    _undoTimer = null;

    final Note restored = pending.note.copy();
    // Restoring the timestamp keeps it in its original place in the
    // most-recently-edited order, which is the whole point of undo.
    final List<Note> notes = <Note>[...current.notes];
    notes.insert(pending.index.clamp(0, notes.length), restored);

    final NotesState next = current.copyWith(
      notes: NotesRepository.sorted(notes),
      selectedId: restored.id,
      clearPendingUndo: true,
    );
    state = AsyncData(next.withVisible());
    _repository.save(state.requireValue.notes);
    return true;
  }

  void clearPendingUndo() {
    final NotesState? current = state.value;
    if (current == null || current.pendingUndo == null) return;
    _undoTimer?.cancel();
    _undoTimer = null;
    state = AsyncData(current.copyWith(clearPendingUndo: true));
  }

  /// Replaces every note, used by import.
  void replaceAll(List<Note> incoming) {
    final List<Note> notes = NotesRepository.sorted(incoming);
    final NotesState next = NotesState(
      notes: notes,
      selectedId: notes.isEmpty ? null : notes.first.id,
    );
    state = AsyncData(next.withVisible());
    _repository.save(notes);
  }

  /// Adds notes alongside the existing ones, used by a restore from backup.
  void merge(List<Note> incoming) {
    final NotesState current = _require();
    if (incoming.isEmpty) return;
    final List<Note> notes = NotesRepository.sorted(<Note>[...current.notes, ...incoming]);
    final NotesState next = current.copyWith(
      notes: notes,
      selectedId: incoming.first.id,
    );
    state = AsyncData(next.withVisible());
    _repository.save(state.requireValue.notes);
  }

  /// Creates one empty note if there are none. For post-load cases; `build`
  /// does its own because `state` does not exist yet there.
  void ensureAtLeastOneNote() {
    if (_require().notes.isNotEmpty) return;
    createNote();
  }

  /// Lets a hand-chosen backup clear the block on an unreadable file.
  void unblockForRestore() => _unblock();

  /// Pushes anything queued to disk. Called when the app is quitting.
  Future<void> flush() => _repository.flush();
}

/// The editor surface's notes provider. The only writer of notes.json, declared
/// here so importing notes state never drags in every provider.
final AsyncNotifierProvider<NotesNotifier, NotesState> notesProvider =
    AsyncNotifierProvider<NotesNotifier, NotesState>(NotesNotifier.new);