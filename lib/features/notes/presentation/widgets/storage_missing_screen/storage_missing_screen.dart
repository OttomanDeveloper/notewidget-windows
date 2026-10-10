import 'package:flutter/material.dart';

/// Shown instead of the editor when the chosen folder cannot be reached, rather
/// than writing the notes somewhere nobody chose. `storage_pattern.md` §3.0a.
class StorageMissingScreen extends StatelessWidget {
  const StorageMissingScreen({
    super.key,
    required this.directory,
    required this.onOpenSettings,
  });

  /// The folder that was chosen and could not be opened.
  final String directory;

  /// Opens Settings, where the Storage row chooses a folder.
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Your notes are not here', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                Text(
                  'WinNotes is set to keep its notes in this folder:',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  directory,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'It cannot be opened. It may be on a drive that is not '
                  'connected, or Windows may not let this app reach it.\n\n'
                  'Your notes are still in that folder - nothing has been '
                  'written here and nothing has been deleted. Reconnect the '
                  'drive and restart WinNotes, or choose a different folder.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Change the notes folder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}