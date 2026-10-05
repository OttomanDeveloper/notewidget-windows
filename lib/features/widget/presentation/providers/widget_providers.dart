import 'package:riverpod/riverpod.dart';

import '../../../../../core/utils/app_providers.dart';
import '../../../../../core/utils/atomic_json_file.dart';
import '../../../notes/domain/note.dart';
import '../../data/widget_state_repository.dart';
import './widget_controller.dart';

/// `widget_state.json`. Written only by the widget surface.
final widgetStateRepositoryProvider =
    Provider<IWidgetStateRepository>((ref) {
  return WidgetStateRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).widgetStateFile),
  );
});

/// Notes in display order, derived rather than rebuilt per build.
///
/// Refires only when the notes list or the selection changes: geometry, scroll
/// and visibility changes leave the cards alone.
final widgetDisplayNotesProvider = Provider<List<Note>>((ref) {
  final notes =
      ref.watch(widgetProvider.select((v) => v.value?.notes)) ?? const [];
  final selectedId =
      ref.watch(widgetProvider.select((v) => v.value?.selectedId));
  return displayNotesIn(notes, selectedId);
});

/// One widget note by id, so a card rebuilds only when its own content changed.
final widgetNoteByIdProvider = Provider.family<Note?, String>((ref, id) {
  final notes = ref.watch(widgetProvider.select((v) => v.value?.notes));
  if (notes == null) return null;
  for (final note in notes) {
    if (note.id == id) return note;
  }
  return null;
});
