import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/settings_repository.dart';
import '../../../data/storage_transfer.dart';
import '../../../../../core/utils/app_providers.dart';
import '../../providers/settings_controller.dart';
import '../../providers/settings_providers.dart';
import '../settings_group/settings_group.dart';
import '../settings_row/settings_row.dart';
import '../settings_separator/settings_separator.dart';

class StorageSettingsGroup extends ConsumerWidget {
  const StorageSettingsGroup({super.key, required this.defaultDirectory});

  final String defaultDirectory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
          settingsProvider.select((v) => v.value?.settings),
        ) ??
        SettingsRepository.defaults;
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final active = ref.watch(storageDirectoryProvider(defaultDirectory));
    final isCustom = settings.storageDirectory.trim().isNotEmpty;

    return SettingsGroup(
      title: 'Storage',
      children: [
        SettingsRow(
          label: 'Notes file',
          description: active,
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                icon: const Icon(Icons.folder_open, size: 18),
                tooltip: 'Show the folder',
                onPressed: () => ref.read(shellProvider).revealPath(active),
              ),
              IconButton(
                icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                tooltip: 'Choose another folder',
                onPressed: () async {
                  final picked = await ref.read(shellProvider).pickFolder(start: active);
                  if (picked == null || !context.mounted) return;

                  // Confirmed before anything is written, because this is the one
                  // place in Settings where a click can touch somebody's notes. The
                  // wording is the decision: a copy, not a move, and a restart.
                  final agreed = await _confirmTransfer(context, picked);
                  if (agreed != true) return;

                  final outcome = await controller.moveTo(picked);
                  if (!context.mounted) return;
                  await _reportTransfer(context, outcome, from: active, to: picked);
                },
              ),
              if (isCustom)
                IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  tooltip: 'Back to the default folder',
                  onPressed: () async {
                    final destination = ref.read(appPathsProvider).defaultStorageDirectory;
                    final agreed = await _confirmTransfer(context, destination);
                    if (agreed != true) return;

                    final outcome = await controller.moveToDefault();
                    if (!context.mounted) return;
                    await _reportTransfer(context, outcome, from: active, to: destination);
                  },
                ),
            ],
          ),
        ),
        const SettingsSeparator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'One plain JSON file, written as a whole so a half-finished write '
            'cannot break it, and readable without this app. Back it up whenever '
            'you like; there is no account and nothing to sync.\n\n'
            'Changing the folder **copies** your notes there. Nothing is ever '
            'deleted or moved, so the old copies stay where they are until you '
            'remove them yourself.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Asks before copying: a copy (nothing deleted), the old location, and the
/// restart (`appPathsProvider` is per-process). Consent is per occasion, never
/// stored.
Future<bool?> _confirmTransfer(BuildContext context, String destination) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: const Text('Copy your notes here?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your notes will be copied to:', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            SelectableText(
              destination,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your existing notes are **not** moved or deleted — they stay in the '
              'folder they are in now, and you can remove them yourself once you '
              'have seen the copy.\n\n'
              'WinNotes needs restarting before it will use the new folder.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Copy and switch'),
          ),
        ],
      );
    },
  );
}

/// Says what happened, which is not always what was asked for. Six outcomes, six
/// sentences; declining a non-empty destination is protection, not failure, so it
/// reads as a decision with a way out.
Future<void> _reportTransfer(
  BuildContext context,
  StorageTransferOutcome outcome, {
  required String from,
  required String to,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final (String title, String detail, bool isProblem) = switch (outcome) {
    StorageTransferOutcome.done => (
        'Notes copied',
        'They are now in $to. Restart WinNotes to use that folder. Your old '
            'copies are still in $from — nothing was deleted.',
        false,
      ),
    StorageTransferOutcome.destinationNotEmpty => (
        'That folder already has notes',
        'Nothing was written and nothing was deleted. Open $to to look at them, '
            'or move them yourself, then try again.',
        true,
      ),
    StorageTransferOutcome.notUsable => (
        'That folder cannot be used',
        'WinNotes needs a folder on a drive, not a relative path. Nothing was '
            'changed.',
        true,
      ),
    StorageTransferOutcome.destinationUnreachable => (
        'That folder is not available',
        'It may be on a drive that is not connected, or Windows may not let this '
            'app write there. Nothing was changed.',
        true,
      ),
    StorageTransferOutcome.alreadyThere => (
        'Already there',
        'That is the folder your notes are in now. Nothing was changed.',
        false,
      ),
    StorageTransferOutcome.failed => (
        'The copy did not finish',
        'Your notes are untouched — nothing is ever deleted. The folder is still '
            'there to look at, so you can try again.',
        true,
      ),
  };

  messenger.showSnackBar(
    SnackBar(
      content: Text('$title\n$detail'),
      backgroundColor:
          isProblem ? Theme.of(context).colorScheme.errorContainer : null,
      duration: Duration(seconds: isProblem ? 10 : 7),
    ),
  );
}
