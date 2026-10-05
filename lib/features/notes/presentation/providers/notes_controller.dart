import 'dart:async';

import 'package:riverpod/riverpod.dart';

import '../../domain/note.dart';
import '../../domain/repositories.dart';
import '../../data/notes_repository.dart';
import '../../../../core/utils/app_providers.dart';
import './notes_providers.dart';

import 'notes_state.dart';

export 'notes_state.dart';

/// The editor surface's notes. The only writer of notes.json.
///
/// Was `NotesController extends ChangeNotifier` until 2026-10-05, with the state
/// spread across eleven mutable fields and a bare `notifyListeners()` at the end of
/// most methods. Every one of those fields is now in [NotesState], which is what
/// makes a rebuild attributable: a listener can tell which part changed instead of
/// having to assume all of it did.
///
/// The corrupt-file path is deliberately **not** an `AsyncError`. A file that
/// cannot be read is a state this app recovers from rather than an exception it
/// propagates - there is a whole recovery screen for it - so modelling it as a
/// thrown error would mean every reader had to know it is special. `isLoading` and
/// `isRefreshing` come from the `AsyncValue` around it instead, which is where the
/// 250ms-debounce watcher re-reads show up.
class NotesNotifier extends AsyncNotifier<NotesState> {
  static const Duration undoWindow = Duration(seconds: 6);

  late final INotesRepository _repository;
  final NoteIdFactory _factory = NoteIdFactory();
  Timer? _undoTimer;

  /// Whether a rolling backup of the previous good file exists.
  ///
  /// A getter on the notifier rather than on the state because it asks the
  /// repository, and putting it in the value would mean every notes change also
  /// re-read a path from disk.
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

    final loaded = _apply(await _repository.load());
    // First launch opens with a note already focused, so typing is the very first
    // thing that happens.
    if (loaded.corrupt == null) {
      var next = loaded;
      if (next.notes.isEmpty) {
        next = _insert(next, _blankNote(next.notes));

        // ...and it is written, which `_insert` does not do. Two reasons this has to
        // be explicit rather than a side effect of inserting:
        //
        // A note that exists only in memory is not a note. It is not on disk, so the
        // next launch mints a fresh one with a new id, and the widget's selection -
        // which refers to a note by id - points at something that no longer exists.
        // It also means the very first keystroke is the thing that creates the file,
        // so a first launch that is closed without typing leaves nothing behind at
        // all, which is the same as having never launched.
        //
        // `ensureAtLeastOneNote` is `createNote`, and `createNote` does save - so the
        // same missing line is not needed there, which is why this is not a call to
        // it. `build` runs before `state` exists, which is the constraint the comment
        // on that method is about.
        _repository.save(next.notes);
      }
      next = next.copyWith(selectedId: _selectionOrNewest(next));
      return next.withVisible();
    }
    return loaded;
  }

  /// Re-reads notes.json and replaces the state with the result.
  ///
  /// Separate from `build` because three things re-read the file: the explicit
  /// retry button, the widget surface's directory watcher, and recovery. Going
  /// through `invalidate` for the watcher would tear the notifier down and rebuild
  /// it, which loses the undo timer and re-runs the whole startup ladder for a
  /// keystroke that arrived in another isolate.
  Future<void> reload() async {
    state = AsyncData(_apply(await _repository.load()));
  }
  /// Where the selection should be after a load or a deletion.
  ///
  /// A selection pointing at a note which no longer exists would leave the editor
  /// showing nothing at all, so it is resolved to the newest note or to null.
  String? _selectionOrNewest(NotesState s) {
    if (s.selectedId != null && s.selectedNote != null) return s.selectedId;
    return s.notes.isEmpty ? null : s.notes.first.id;
  }

  /// The restore path is the one place a write is allowed while the file is
  /// unreadable, and only because a caller has deliberately chosen a file to
  /// replace one the app refused to touch on its own.
  void _unblock() => _repository.unblock();

  /// Whether the widget's own copy of the notes is usable. Never true on the editor
  /// surface, which does not read notes.json through this provider at all.
  bool get hasAnyNoteWithText =>
      (state.value?.notes ?? const [])
          .any((n) => n.title.trim().isNotEmpty || n.body.trim().isNotEmpty);

  /// Whether notes.json is currently unreadable, which the import path needs: a
  /// hand-chosen backup is the one thing allowed to replace a file the app refused
  /// to touch on its own, and that has to be asked before the import rather than
  /// decided inside it.
  bool get hasReadOnlyFile => state.value?.isReadOnly ?? false;

  NotesState _require() => state.requireValue;

  /// Applies a read result. The corrupt case already carries the domain error,
  /// so nothing above this layer meets the file system face to face.
  NotesState _apply(NotesLoadResult result) {
    return switch (result) {
      NotesLoaded(:final notes) =>
        // A fresh state, so `selectedId` is null: any selection from the previous
        // load died with that object and cannot point at a note id that is gone.
        NotesState(notes: NotesRepository.sorted(notes)),
      NotesCorrupt(:final error) => NotesState(corrupt: error),
    };
  }

  /// Re-reads after the other surface changed the file.
  void _onExternalChange() {
    unawaited(reload());
  }

  /// Tries the read again, for someone who was told the file could not be opened.
  ///
  /// The startup ladder already waited a couple of seconds before giving up, so
  /// this exists for the locks that last longer than that - a backup tool walking
  /// a whole folder, a sync client deciding what to do with the file. It is the
  /// difference between "quit and try again" and pressing one button.
  Future<void> retryLoad() async {
    await reload();
  }

  /// Puts the rolling backup back, if there is one.
  ///
  /// Offered ahead of anything the person has to go and find, because it is the
  /// only route that needs nothing from them: not a backup they remembered to
  /// make, not a file they have to locate. Since writes are atomic, this file was
  /// written by this app and is very likely intact.
  Future<RecoveryOutcome> restoreBackup() async {
    if (_require().corrupt == null) return RecoveryOutcome.restoredBackup;
    final recovered = await _repository.restoreBackup();
    if (recovered == null) return RecoveryOutcome.nothingToRecover;
    await retryLoad();
    return RecoveryOutcome.restoredBackup;
  }

  /// Moves the unreadable file aside and starts over, keeping the old one.
  ///
  /// The escape hatch that has to exist. Refusing to start is the right call when
  /// a file might hold somebody's notes, but a refusal with no way out is not a
  /// safety feature - it is a trap, and the person in it is already stressed. This
  /// keeps the damaged file rather than deleting it, because it may still be
  /// readable by someone better at JSON, and losing the only copy of a damaged file
  /// to make a button feel tidier is exactly backwards.
  Future<({RecoveryOutcome outcome, String? keptAt})> startFresh() async {
    final current = _require();
    final keptAt = await _repository.setAsideAndStartFresh();
    if (current.corrupt != null && keptAt == null) {
      final stillThere = _repository.backupPath != null;
      return (
        outcome: RecoveryOutcome.fileIsHeld,
        keptAt: stillThere ? _repository.path : null,
      );
    }

    _undoTimer?.cancel();
    // Creates a valid, empty document, so the next thing that happens is not
    // another refusal.
    final blank = _blankNote(const []);
    final next = NotesState(
      notes: NotesRepository.sorted([blank]),
      selectedId: blank.id,
    );
    state = AsyncData(next.withVisible());
    _repository.save(next.notes);
    return (outcome: RecoveryOutcome.startedFresh, keptAt: keptAt);
  }

  void setQuery(String value) {
    final current = _require();
    if (current.query == value) return;
    state = AsyncData(current.copyWith(query: value).withVisible());
  }

  void select(String? id) {
    final current = _require();
    if (current.selectedId == id) return;
    // `clearSelectedId`, not `selectedId: null` - see `NotesState.copyWith`.
    state = AsyncData(
      current.copyWith(selectedId: id, clearSelectedId: id == null),
    );
  }

  /// A new, empty note.
  ///
  /// Takes the existing notes rather than reading `state`, and that is not a style
  /// choice. `_nextStamp` used to read `state.requireValue`, and `build` calls this
  /// on a first launch - at which point `state` is still `AsyncLoading` with no
  /// value. It threw, Riverpod treated the throw as a failed build and rebuilt, it
  /// threw again, and the provider sat in `isLoading` forever with no error anywhere.
  ///
  /// A silent infinite retry is the worst shape a bug can take: `isLoading` is true,
  /// so a test asserting "still loading" passes, and the editor shows a blank window
  /// rather than anything that looks like a fault.
  Note _blankNote(List<Note> existing) {
    final now = _nextStampFor(existing);
    return Note(
      id: _factory.next(),
      title: '',
      body: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Creates a note and returns it, already selected, so typing can start
  /// immediately.
  ///
  /// Returns null while the file is unreadable: the note would have nowhere to go,
  /// and a note that exists on screen but not on disk is worse than no note.
  Note? createNote() {
    final current = _require();
    if (current.corrupt != null) return null;
    final note = _blankNote(current.notes);
    var next = _insert(current, note);
    next = next.copyWith(selectedId: note.id);
    state = AsyncData(next.withVisible());
    _repository.save(next.notes);
    return note;
  }

  NotesState _insert(NotesState s, Note note) {
    return s.copyWith(notes: NotesRepository.sorted([...s.notes, note]));
  }

  /// A timestamp guaranteed to sort newer than every note already held.
  ///
  /// The clock is only millisecond-resolution and the ordering tie-breaks by id,
  /// which is random. Without this, editing a note in the same millisecond another
  /// note was last touched would leave the edited note second instead of first - a
  /// coin flip on a promise the whole UI makes, and the reason the widget might
  /// not show the note you are looking at as its large card.
  /// Stepping one millisecond past the current newest makes "the note you just
  /// touched is on top" an invariant instead of a probability.
  DateTime _nextStampFor(List<Note> existing) {
    final newest = existing.isEmpty ? null : existing.first.updatedAt;
    final now = DateTime.now();
    if (newest == null || now.isAfter(newest)) return now;
    return newest.add(const Duration(milliseconds: 1));
  }

  /// Adds a note with text already in it, without changing the selection.
  ///
  /// Used for a note written in the widget. It deliberately does *not* select what
  /// it makes: the person is looking at the widget, not the editor, and moving the
  /// editor's cursor out from under them would be a worse surprise than the note
  /// appearing quietly at the top of the list. It also does not go through
  /// [createNote], which exists to hand back a note you are about to type into,
  /// and whose whole point is taking the selection.
  void addNote({required String title, required String body}) {
    final current = _require();
    if (current.corrupt != null) return;
    if (title.trim().isEmpty && body.trim().isEmpty) return;

    final now = _nextStampFor(current.notes);
    final note = Note(
      id: _factory.next(),
      title: title,
      body: body,
      createdAt: now,
      updatedAt: now,
    );
    final next = _insert(current, note);
    state = AsyncData(next.withVisible());
    _repository.save(next.notes);
  }

  void updateNote(String id, {String? title, String? body}) {
    final current = _require();
    if (current.corrupt != null) return;
    final index = current.notes.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final note = current.notes[index];
    final nextTitle = title ?? note.title;
    final nextBody = body ?? note.body;
    if (nextTitle == note.title && nextBody == note.body) return;

    final updated = note.copyWith(
      title: nextTitle,
      body: nextBody,
      updatedAt: _nextStampFor(current.notes),
    );
    final notes = [...current.notes]..[index] = updated;
    final next = current.copyWith(
      notes: NotesRepository.sorted(notes),
    );
    // The search filter depends on the text, so it has to be reapplied.
    state = AsyncData(next.withVisible());
    _repository.save(next.notes);
  }

  /// Flips a note between finished and unfinished.
  ///
  /// Deliberately does not touch [Note.updatedAt], and that is the whole design of
  /// the method rather than an oversight. Notes sort by most recently edited, so
  /// bumping the timestamp would send the note to the top of the list every single
  /// time it is ticked off - which turns working through a list into a shuffle, and
  /// makes the note you just finished the first thing you see again. Finishing
  /// something is a change of state, not an edit.
  ///
  /// No re-sort follows from that, so the list does not move under the pointer.
  void toggleCompleted(String id) {
    final current = _require();
    if (current.corrupt != null) return;
    final index = current.notes.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final note = current.notes[index];
    final updated = note.isCompleted
        ? note.copyWith(clearCompletedAt: true)
        : note.copyWith(completedAt: DateTime.now());
    // A new list identity: `AnimatedBuilder` compares by identity, so reusing
    // the same list would rebuild nothing and the strike-through would not appear.
    final notes = [...current.notes]..[index] = updated;
    state = AsyncData(current.copyWith(notes: notes));
    _repository.save(state.requireValue.notes);
  }

  /// Turns Markdown rendering on or off for one note.
  ///
  /// The one property of a note that is not part of its text, which is why it is
  /// not just a field the UI writes: it decides how the stored source is
  /// *presented*, so turning it off must not touch the source. Someone who writes
  /// Markdown, decides they did not want it, and turns it back on later has to get
  /// their asterisks and their hashes back exactly as they typed them.
  ///
  /// Bumps `updatedAt`, unlike [toggleCompleted]. That one deliberately does not,
  /// because finishing a task is not an edit and a list that reshuffles every time
  /// you tick something is unusable. Switching a note into Markdown *is* an edit -
  /// it changes how the note reads - so it earns its place at the top of the list
  /// like any other change.
  void setMarkdown(String id, {required bool enabled}) {
    final current = _require();
    if (current.corrupt != null) return;
    final index = current.notes.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final note = current.notes[index];
    if (note.markdown == enabled) return;
    final updated = note.copyWith(
      markdown: enabled,
      updatedAt: DateTime.now(),
    );
    final notes = [...current.notes]..[index] = updated;
    final next = current.copyWith(notes: notes);
    state = AsyncData(next.withVisible());
    _repository.save(state.requireValue.notes);
  }

  /// Deletes a note and holds it for undo.
  ///
  /// The caller is responsible for having asked for confirmation first; this
  /// method is the actual removal.
  void deleteNote(String id) {
    final current = _require();
    if (current.corrupt != null) return;
    final index = current.notes.indexWhere((n) => n.id == id);
    if (index < 0) return;

    final removed = current.notes[index];
    final remaining = [...current.notes]..removeAt(index);

    // Replacing the pending undo rather than queueing it: undo applies to the most
    // recent action, and holding two would make the toast ambiguous.
    _undoTimer?.cancel();
    final pending = PendingUndo(removed, index);
    _undoTimer = Timer(undoWindow, clearPendingUndo);

    var next = current.copyWith(notes: remaining, pendingUndo: pending);
    if (current.selectedId == id) {
      final replacement = remaining.isEmpty ? null : remaining.first.id;
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
    final current = _require();
    if (current.corrupt != null) return false;
    final pending = current.pendingUndo;
    if (pending == null) return false;

    _undoTimer?.cancel();
    _undoTimer = null;

    final restored = pending.note.copy();
    // Restoring the timestamp keeps it in its original place in the
    // most-recently-edited order, which is the whole point of undo.
    final notes = [...current.notes];
    notes.insert(pending.index.clamp(0, notes.length), restored);

    final next = current.copyWith(
      notes: NotesRepository.sorted(notes),
      selectedId: restored.id,
      clearPendingUndo: true,
    );
    state = AsyncData(next.withVisible());
    _repository.save(state.requireValue.notes);
    return true;
  }

  void clearPendingUndo() {
    final current = state.value;
    if (current == null || current.pendingUndo == null) return;
    _undoTimer?.cancel();
    _undoTimer = null;
    state = AsyncData(current.copyWith(clearPendingUndo: true));
  }

  /// Replaces every note, used by import.
  void replaceAll(List<Note> incoming) {
    final notes = NotesRepository.sorted(incoming);
    final next = NotesState(
      notes: notes,
      selectedId: notes.isEmpty ? null : notes.first.id,
    );
    state = AsyncData(next.withVisible());
    _repository.save(notes);
  }

  /// Adds notes alongside the existing ones, used by a restore from backup.
  void merge(List<Note> incoming) {
    final current = _require();
    if (incoming.isEmpty) return;
    final notes = NotesRepository.sorted([...current.notes, ...incoming]);
    final next = current.copyWith(
      notes: notes,
      selectedId: incoming.first.id,
    );
    state = AsyncData(next.withVisible());
    _repository.save(state.requireValue.notes);
  }

  /// Creates one empty note if there are none at all.
  ///
  /// `build` does this itself for the first launch, and cannot call this: it runs
  /// before `state` exists, which is why the code that needs an empty note to exist
  /// takes the note list explicitly. This is the same operation for the cases that
  /// happen *after* the first load - a restore that produced an empty library, or a
  /// test setting one up.
  void ensureAtLeastOneNote() {
    if (_require().notes.isNotEmpty) return;
    createNote();
  }

  /// Lets a hand-chosen backup clear the block on an unreadable file.
  void unblockForRestore() => _unblock();

  /// Pushes anything queued to disk. Called when the app is quitting.
  Future<void> flush() => _repository.flush();
}

/// The editor surface's notes provider. The only writer of notes.json.
///
/// Declared here rather than in the shared graph, so that file does not have
/// to import this one to list it - and so importing notes state never drags in
/// every provider. Recovery lives in `notes_recovery.dart`, same library.
final notesProvider =
    AsyncNotifierProvider<NotesNotifier, NotesState>(NotesNotifier.new);