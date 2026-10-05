import 'package:riverpod/riverpod.dart';

import '../../../../../core/utils/app_providers.dart';
import '../../../../../core/utils/atomic_json_file.dart';
import '../../domain/note.dart';
import '../../domain/repositories.dart';
import '../../data/notes_repository.dart';
import '../../data/selection_repository.dart';
import './notes_controller.dart';

/// `notes.json`. Written only by the editor surface.
final notesRepositoryProvider = Provider<INotesRepository>((ref) {
  return NotesRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).notesFile),
  );
});

/// `selection.json`. The one file both surfaces write - it is a single value, and a
/// file is cheaper than a channel round trip.
final selectionRepositoryProvider = Provider<ISelectionRepository>((ref) {
  return SelectionRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).selectionFile),
  );
});

/// One note by id, for widgets that draw a single card or row.
///
/// A `.family` rather than a scan at each call site, so the lookup rule lives in
/// one place. Notes carry value equality, so dependents rebuild only when the
/// note's content actually changed rather than on every list edit.
final noteByIdProvider = Provider.family<Note?, String>((ref, id) {
  final notes = ref.watch(notesProvider.select((v) => v.value?.notes));
  if (notes == null) return null;
  for (final note in notes) {
    if (note.id == id) return note;
  }
  return null;
});

/// The note the editor is showing, derived rather than re-scanned per build.
final selectedNoteProvider = Provider<Note?>((ref) {
  return ref.watch(notesProvider.select((v) => v.value?.selectedNote));
});

/// The note the widget renders large, derived rather than re-scanned per build.
final focusedNoteProvider = Provider<Note?>((ref) {
  return ref.watch(notesProvider.select((v) => v.value?.focusedNote));
});

/// The filtered list, derived rather than rebuilt per build.
final visibleNotesProvider = Provider<List<Note>>((ref) {
  return ref.watch(notesProvider.select((v) => v.value?.visible)) ??
      const [];
});

/// What the recovery screen shows about a file, derived so widgets never call
/// the file system directly (`flutter_architecture_pattern.md` §4).
final fileDescriptionProvider =
    Provider.family<FileDescription?, String>((ref, path) {
  return NotesRepository.describeFile(path);
});
