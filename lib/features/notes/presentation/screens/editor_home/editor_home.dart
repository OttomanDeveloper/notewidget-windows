import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/app_providers.dart';
import '../../../domain/note.dart';
import '../../../data/notes_repository.dart';
import '../../providers/notes_controller.dart';
import '../../../../settings/presentation/screens/settings_dialog/settings_dialog.dart';
import '../editor_screen/editor_screen.dart';

/// The editor surface below the `MaterialApp`.
///
/// Its own `ConsumerWidget` rather than a field of the scope, so that a dialog
/// pushed from here has a context with a `Navigator` ancestor. That is the whole of
/// what the old `GlobalKey` was working around.
class EditorHome extends ConsumerWidget {
  const EditorHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EditorView(
      onOpenSettings: () => openSettings(context, ref),
      exportNotes: () => exportNotes(context, ref),
      importNotes: () => importNotes(context, ref),
    );
  }
}

/// Opens the settings dialog.
///
/// `context` is the one below the `MaterialApp`, so `showDialog` has somewhere to
/// go. The old code needed a `GlobalKey<NavigatorState>` to get this; here it is
/// simply the caller's context.
Future<void> openSettings(BuildContext context, WidgetRef ref) async {
  final paths = ref.read(appPathsProvider);
  await showDialog<void>(
    context: context,
    builder: (context) => SettingsDialog(
      defaultDataDirectory: paths.defaultStorageDirectory,
    ),
  );
}

/// Writes a plain-text backup of every note somewhere the person chose.
Future<void> exportNotes(BuildContext context, WidgetRef ref) async {
  // Captured before the first await, and never looked up again afterwards.
  //
  // Two reasons, both learned the hard way: there is no ScaffoldMessenger above the
  // MaterialApp this returns, so ScaffoldMessenger.of(context) throws and the
  // "Exported N notes" confirmation is lost while the file still writes; and
  // reaching for a context after an await is unsafe because the widget behind it
  // may be gone.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final shell = ref.read(shellProvider);
  final notes = ref.read(notesProvider).value;

  final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
  final path = await shell.saveFile(suggestedName: 'winnotes-backup-$stamp.txt');
  if (path == null || !context.mounted) return;
  await const BackupService().exportTo(path, notes?.notes ?? const []);
  messenger?.showSnackBar(
    SnackBar(content: Text('Exported ${notes?.notes.length ?? 0} notes.')),
  );
}

/// Reads a plain-text backup back in, with a confirmation before it merges.
Future<List<Note>?> importNotes(BuildContext context, WidgetRef ref) async {
  final shell = ref.read(shellProvider);
  final notes = ref.read(notesProvider.notifier);

  final path = await shell.pickFile();
  if (path == null) return null;

  final incoming = await const BackupService().readFrom(path);
  if (incoming == null) return null;

  if (notes.hasReadOnlyFile) {
    // A hand-chosen backup is the one thing allowed to replace a file the app
    // refused to touch on its own.
    notes.unblockForRestore();
    notes.replaceAll(incoming);
  } else {
    // Guarded on `context.mounted` rather than left bare: the dialog is an await,
    // and this widget can be torn down inside it.
    if (!context.mounted) return incoming;
    final merge = await _confirmMerge(context, incoming.length);
    if (merge) {
      notes.merge(incoming);
    }
  }
  return incoming;
}

Future<bool> _confirmMerge(BuildContext context, int count) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Add $count notes?'),
      content: const Text(
        'The imported notes are added alongside the ones you already have. '
        'Nothing existing is replaced.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Add them'),
        ),
      ],
    ),
  );
  return result ?? false;
}
