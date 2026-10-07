import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../../../domain/text_sizes.dart';
import '../../../../../core/widgets/completion_toggle/completion_toggle.dart';
import '../../../../../core/widgets/markdown_text/markdown_text.dart';

class PreviewPane extends StatefulWidget {
  const PreviewPane({
    super.key,
    required this.note,
    required this.previewSource,
    this.fontSize = 0,
  });

  final Note note;
  final ValueNotifier<String> previewSource;

  /// The user's chosen size, or 0 for "as designed". Handed to the renderer
  /// rather than wrapped in a style, so its gaps and headings scale with it.
  final int fontSize;

  @override
  State<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<PreviewPane> {
  /// Owned here so the [Scrollbar] and the [SingleChildScrollView] share one
  /// controller; on [PrimaryScrollController] the first wheel scroll throws.
  /// State is the disposal shell only; no setState.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Rebuilt from the debounced source, not from the field: typing updates the
    // preview a few times a second instead of once per character.
    return ValueListenableBuilder<String>(
      valueListenable: widget.previewSource,
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
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 0, 6, 12),
            child: DefaultTextStyle(
              style:
                  markCompleted(const TextStyle(), completed: widget.note.isCompleted) ??
                  const TextStyle(),
              child: MarkdownText(
                source: source,
                color: theme.colorScheme.onSurface,
                accent: theme.colorScheme.primary,
                mutedColor: theme.colorScheme.onSurfaceVariant,
                selectable: true,
                fontSize: TextSizes.preview(widget.fontSize),
              ),
            ),
          ),
        );
      },
    );
  }
}
