import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../../../../../core/widgets/completion_toggle/completion_toggle.dart';
import '../../../../../core/widgets/markdown_text/markdown_text.dart';

class PreviewPane extends StatelessWidget {
  const PreviewPane({
    super.key,
    required this.note,
    required this.previewSource,
  });

  final Note note;
  final ValueNotifier<String> previewSource;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Rebuilt from the debounced source, not from the field: typing updates the
    // preview a few times a second instead of once per character.
    return ValueListenableBuilder<String>(
      valueListenable: previewSource,
      builder: (BuildContext context, String source, _) {
        if (source.trim().isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              'Nothing to preview yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }

        // Its own scroll view because the pane does not scroll: the source field
        // beside it expands to fill, and a preview that cannot reach the bottom of
        // its own note is not a preview.
        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 0, 6, 12),
            child: DefaultTextStyle(
              style: markCompleted(const TextStyle(), completed: note.isCompleted) ??
                  const TextStyle(),
              child: MarkdownText(
                source: source,
                color: theme.colorScheme.onSurface,
                accent: theme.colorScheme.primary,
                mutedColor: theme.colorScheme.onSurfaceVariant,
                selectable: true,
              ),
            ),
          ),
        );
      },
    );
  }
}
