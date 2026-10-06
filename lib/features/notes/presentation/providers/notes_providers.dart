import 'package:riverpod/riverpod.dart';


import '../../../../../core/utils/app_providers.dart';
import '../../../../../core/utils/atomic_json_file.dart';
import '../../domain/note.dart';
import '../../domain/repositories.dart';
import '../../data/notes_repository.dart';
import '../../data/selection_repository.dart';
import './notes_controller.dart';

/// `notes.json`. Written only by the editor surface.
final Provider<INotesRepository> notesRepositoryProvider = Provider<INotesRepository>((Ref ref) {
  return NotesRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).notesFile),
  );
});

/// `selection.json`. The one file both surfaces write - it is a single value, and a
/// file is cheaper than a channel round trip.
final Provider<ISelectionRepository> selectionRepositoryProvider = Provider<ISelectionRepository>((Ref ref) {
  return SelectionRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).selectionFile),
  );
});

/// One note by id, for single-card widgets. A `.family`, so the lookup lives in
/// one place; value equality rebuilds dependents only on content change.
final noteByIdProvider = Provider.family<Note?, String>((Ref ref, String id) {
  final List<Note>? notes = ref.watch(notesProvider.select((AsyncValue<NotesState> v) => v.value?.notes));
  if (notes == null) return null;
  for (final Note note in notes) {
    if (note.id == id) return note;
  }
  return null;
});

/// The note the editor is showing, derived rather than re-scanned per build.
final Provider<Note?> selectedNoteProvider = Provider<Note?>((Ref ref) {
  return ref.watch(notesProvider.select((AsyncValue<NotesState> v) => v.value?.selectedNote));
});

/// The note the widget renders large, derived rather than re-scanned per build.
final Provider<Note?> focusedNoteProvider = Provider<Note?>((Ref ref) {
  return ref.watch(notesProvider.select((AsyncValue<NotesState> v) => v.value?.focusedNote));
});

/// The filtered list, derived rather than rebuilt per build.
final Provider<List<Note>> visibleNotesProvider = Provider<List<Note>>((Ref ref) {
  return ref.watch(notesProvider.select((AsyncValue<NotesState> v) => v.value?.visible)) ??
      const <Note>[];
});

/// What the recovery screen shows about a file, derived so widgets never call
/// the file system directly (`flutter_architecture_pattern.md` §4).
final fileDescriptionProvider =
    Provider.family<FileDescription?, String>((Ref ref, String path) {
  return NotesRepository.describeFile(path);
});
