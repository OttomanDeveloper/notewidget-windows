import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/app_providers.dart';
import '../../../../../core/widgets/confirm_dialog/confirm_dialog.dart';
import '../../../domain/note.dart';
import '../../../domain/repositories.dart';
import '../../widgets/detail_card/detail_card.dart';

/// Shown instead of the editor when notes.json cannot be read. Refuses to start
/// rather than replacing the file, with four ways out: backup, retry, chosen
/// backup, fresh start keeping the damaged file.
class CorruptNotesScreen extends StatefulWidget {
  const CorruptNotesScreen({
    super.key,
    required this.error,
    required this.onRestore,
    required this.onReveal,
    required this.onRestoreBackup,
    required this.onRetry,
    required this.onStartFresh,
    required this.hasBackup,
  });

  final CorruptDataFileError error;
  final Future<List<Note>?> Function() onRestore;
  final VoidCallback onReveal;
  final Future<RecoveryOutcome> Function() onRestoreBackup;
  final Future<void> Function() onRetry;
  final Future<({RecoveryOutcome outcome, String? keptAt})> Function() onStartFresh;
  final bool hasBackup;

  @override
  State<CorruptNotesScreen> createState() => _CorruptNotesScreenState();
}

class _CorruptNotesScreenState extends State<CorruptNotesScreen> {
    /// Whether a recovery action runs, and what it last said. Two fields: `_busy`
    /// disables buttons, `_message` is read after. A `ValueNotifier`, not a provider:
    /// true for one button press, asked by nobody else (`AGENTS.md` §0.7).
  final ValueNotifier<bool> _busy = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _message = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _busy.dispose();
    _message.dispose();
    super.dispose();
  }

    /// Runs a recovery action with buttons disabled and message cleared. `_busy`
    /// is set before the first `await` and cleared in `finally`, so nothing sticks.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy.value) return;
    _busy.value = true;
    _message.value = null;
    try {
      await action();
    } finally {
      _busy.value = false;
    }
  }

  Future<void> _restoreBackup() => _run(() async {
        final outcome = await widget.onRestoreBackup();
        if (!mounted) return;
        _message.value = switch (outcome) {
          RecoveryOutcome.restoredBackup =>
            'Restored the previous version of your notes.',
          RecoveryOutcome.nothingToRecover =>
            'There is no earlier version to go back to.',
          RecoveryOutcome.startedFresh => null,
          RecoveryOutcome.fileIsHeld =>
            'Something else is holding the file. Try again in a moment.',
        };
      });

  Future<void> _startFresh() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Start fresh?',
      message: 'The file that cannot be read will be kept, renamed with today\'s '
          'time on the end, so nothing is thrown away. WinNotes then starts a new '
          'empty notes file beside it.',
      confirmLabel: 'Keep it and start fresh',
      cancelLabel: 'Go back',
    );
    if (!confirmed || !mounted) return;

    await _run(() async {
      final result = await widget.onStartFresh();
      if (!mounted) return;
      _message.value = switch (result.outcome) {
        RecoveryOutcome.startedFresh => result.keptAt == null
            ? 'The unreadable file was already gone. Starting a new one.'
            : 'The unreadable file was kept as '
                '"${result.keptAt!.split('\\').last}".',
        RecoveryOutcome.fileIsHeld =>
          'Something else is holding the file, so it could not be moved aside. '
              'Try again in a moment.',
        RecoveryOutcome.restoredBackup => null,
        RecoveryOutcome.nothingToRecover => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transient = widget.error.transient;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      transient ? Icons.hourglass_top_rounded : Icons.warning_amber_rounded,
                      color: transient ? theme.colorScheme.tertiary : theme.colorScheme.error,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        transient
                            ? 'Something is holding your notes file'
                            : 'Your notes file could not be read',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  transient
                      ? 'WinNotes has not changed anything on disk. This is usually '
                          'antivirus, a backup tool or a sync app looking at the file '
                          'at this moment - your notes are almost certainly fine and '
                          'will open as soon as it lets go.'
                      : 'WinNotes has not changed anything on disk. It stopped rather '
                          'than start with an empty list, because notes that were '
                          'never read are worse than notes that take a moment longer '
                          'to open.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                DetailCard(error: widget.error),
                ValueListenableBuilder<String?>(
                  valueListenable: _message,
                  builder: (context, message, _) => message == null
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            Text(
                              message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                      // First: the only route asking nothing of the person. Hidden, not
                      // disabled: a greyed-out button asks "of what?" with no good answer.
                    if (widget.hasBackup)
                      FilledButton.icon(
                        onPressed: _busy.value ? null : _restoreBackup,
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('Restore the previous version'),
                      ),
                    if (transient)
                      FilledButton.icon(
                        onPressed: _busy.value ? null : () => _run(widget.onRetry),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Try again'),
                      ),
                    if (!widget.hasBackup && !transient)
                      FilledButton.icon(
                        onPressed: _busy.value
                            ? null
                            : () => _run(() async {
                                  final restored = await widget.onRestore();
                                  if (restored != null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('Restored ${restored.length} notes.')),
                                    );
                                  }
                                }),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Restore from a backup'),
                      ),
                    if (widget.hasBackup)
                      OutlinedButton.icon(
                        onPressed: _busy.value
                            ? null
                            : () => _run(() async {
                                  final restored = await widget.onRestore();
                                  if (restored != null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('Restored ${restored.length} notes.')),
                                    );
                                  }
                                }),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Restore from a backup'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy.value ? null : widget.onReveal,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Open the folder'),
                    ),
                    TextButton(
                      onPressed: _busy.value ? null : _startFresh,
                      child: const Text('Start fresh instead'),
                    ),
                    Consumer(
                      builder: (context, ref, _) => TextButton(
                        onPressed: _busy.value
                            ? null
                            : () => ref.read(shellProvider).quit(),
                        child: const Text('Quit'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Nothing here deletes anything. Starting fresh keeps the file that '
                  'could not be read, renamed with the time on the end, in the same '
                  'folder.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
