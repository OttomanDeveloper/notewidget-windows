import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win_notes/core/platform/shell_channel.dart';
import 'package:win_notes/core/utils/app_paths.dart';

import '../../../../../core/utils/app_providers.dart';
import '../../../domain/note.dart';
import '../../../data/notes_repository.dart';
import '../../providers/notes_controller.dart';
import '../../../../settings/presentation/screens/settings_dialog/settings_dialog.dart';
import '../editor_view/editor_view.dart';

/// The editor surface below the `MaterialApp`. Own widget so pushed dialogs get
/// a context with a `Navigator` ancestor.
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

/// Opens the settings dialog with the context below the `MaterialApp`, where
/// `showDialog` has somewhere to go (no `GlobalKey` needed).
Future<void> openSettings(BuildContext context, WidgetRef ref) async {
  final AppPaths paths = ref.read(appPathsProvider);
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => SettingsDialog(
      defaultDataDirectory: paths.defaultStorageDirectory,
    ),
  );
}

/// Writes a plain-text backup of every note somewhere the person chose.
Future<void> exportNotes(BuildContext context, WidgetRef ref) async {
    // Captured before the first await: no ScaffoldMessenger exists above this
    // MaterialApp (so `of(context)` throws), and a post-await context may be gone.
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  final ShellChannel shell = ref.read(shellProvider);
  final NotesState? notes = ref.read(notesProvider).value;

  final String stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
  final String? path = await shell.saveFile(suggestedName: 'winnotes-backup-$stamp.txt');
  if (path == null || !context.mounted) return;
  await const BackupService().exportTo(path, notes?.notes ?? const <Note>[]);
  messenger?.showSnackBar(
    SnackBar(content: Text('Exported ${notes?.notes.length ?? 0} notes.')),
  );
}

/// Reads a plain-text backup back in, with a confirmation before it merges.
Future<List<Note>?> importNotes(BuildContext context, WidgetRef ref) async {
  final ShellChannel shell = ref.read(shellProvider);
  final NotesNotifier notes = ref.read(notesProvider.notifier);

  final String? path = await shell.pickFile();
  if (path == null) return null;

  final List<Note>? incoming = await const BackupService().readFrom(path);
  if (incoming == null) return null;

  if (notes.hasReadOnlyFile()) {
    // A hand-chosen backup is the one thing allowed to replace a file the app
    // refused to touch on its own.
    notes.unblockForRestore();
    notes.replaceAll(incoming);
  } else {
    // Guarded on `context.mounted` rather than left bare: the dialog is an await,
    // and this widget can be torn down inside it.
    if (!context.mounted) return incoming;
    final bool merge = await _confirmMerge(context, incoming.length);
    if (merge) {
      notes.merge(incoming);
    }
  }
  return incoming;
}

Future<bool> _confirmMerge(BuildContext context, int count) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text('Add $count notes?'),
      content: const Text(
        'The imported notes are added alongside the ones you already have. '
        'Nothing existing is replaced.',
      ),
      actions: <Widget>[
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
