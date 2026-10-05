import 'package:flutter/material.dart';

class EditorStatusBar extends StatelessWidget {
  const EditorStatusBar({
    super.key,
    required this.hasPendingUndo,
    required this.onUndo,
    required this.onDelete,
  });

  final bool hasPendingUndo;
  final VoidCallback onUndo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 10, 20, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.check, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Saved to this PC',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (hasPendingUndo)
            TextButton(
              onPressed: onUndo,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
              child: const Text('Undo delete'),
            ),
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
