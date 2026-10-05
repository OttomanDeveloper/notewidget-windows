import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../../../../../core/widgets/completion_toggle/completion_toggle.dart';

class EditorBackBar extends StatelessWidget {
  const EditorBackBar({
    super.key,
    required this.note,
    required this.onToggleCompleted,
    required this.onDelete,
    required this.onBack,
  });

  final Note? note;
  final VoidCallback onToggleCompleted;
  final VoidCallback onDelete;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to notes',
            onPressed: onBack,
          ),
          const Spacer(),
          // The narrow layout has no room for the toggle beside the title, so it
          // lives in the bar instead. Marking a task done has to work the same
          // way in both arrangements, and this is the only place it fits here.
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CompletionToggle(
                completed: note!.isCompleted,
                onToggle: onToggleCompleted,
                diameter: 20,
                hitTarget: 36,
                filled: true,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete note',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
