import 'dart:io';

import './note.dart';

/// Result of loading the notes document.
sealed class NotesLoadResult {
  const NotesLoadResult();
}

class NotesLoaded extends NotesLoadResult {
  const NotesLoaded(this.notes);
  final List<Note> notes;
}

/// The file exists but could not be read. Carries the path so the UI can offer
/// it as an import target for hand restoration.
class NotesCorrupt extends NotesLoadResult {
  const NotesCorrupt(this.error);
  final CorruptDataFileError error;
}

/// What the recovery screen shows about a file it could not read.
typedef FileDescription = ({int bytes, DateTime changed});

/// What a corrupt file looks like above the `dart:io` line, so the UI never
/// imports it directly. Built once, in `data/`, from the caught error.
class CorruptDataFileError {
  const CorruptDataFileError(this.path, this.reason, {this.transient = false});
  final String path;
  final String reason;

    /// Whether the file may simply be held open right now. Carried, not derived:
    /// it decides what the screen says and offers.
  final bool transient;
}

/// What happened when someone tried to get past an unreadable file. Returned,
/// not thrown: every outcome has something to say, and the screen's advice differs
/// per outcome.
enum RecoveryOutcome {
  /// No rolling backup existed, so there was nothing to restore from.
  nothingToRecover,

  /// The rolling backup was read and put back.
  restoredBackup,

  /// The unreadable file was moved aside and a fresh one created.
  startedFresh,

  /// Something else is holding the file, so it could not be moved.
  fileIsHeld,
}

/// Owns `notes.json`. The interface the providers depend on; the file in
/// `data/` is the only implementation.
abstract interface class INotesRepository {
  Future<NotesLoadResult> load();
  void save(List<Note> notes);
  Future<void> saveNow(List<Note> notes);
  void watch(void Function() onChanged);
  void unblock();
  String? get backupPath;
  Future<int?> restoreBackup();
  Future<String?> setAsideAndStartFresh();
  Future<NotesLoadResult> loadFrom(File file);
  Future<void> flush();
  Future<void> dispose();
  String get path;
}

/// Which note is focused. The interface the providers depend on.
abstract interface class ISelectionRepository {
  String? get cached;
  String? readSelection();
  void setSelection(String? noteId);
  void watch(void Function() onChanged);
  Future<void> flush();
  Future<void> dispose();
}

/// Plain-text backup in both directions. The interface is thin on purpose:
/// this is a pure function object with no state, and the only implementation
/// lives beside it in `data/`.
abstract interface class IBackupService {
  String export(List<Note> notes);
  Future<String> exportTo(String path, List<Note> notes);
  Future<List<Note>?> readFrom(String path);
  List<Note> import(String text);
}
