import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../../../domain/text_sizes.dart';
import '../../../../../core/widgets/completion_toggle/completion_toggle.dart';
import '../../../../../core/widgets/markdown_block_list/markdown_block_list.dart';
import '../../../../../core/widgets/markdown_density/markdown_density.dart';
import '../../../../../core/widgets/markdown_metrics/markdown_metrics.dart';
import '../../../../../core/widgets/markdown_style/markdown_style.dart';
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
  /// Owned here so the [Scrollbar] and the list share one controller; on
  /// [PrimaryScrollController] the first wheel scroll throws.
  /// State is the disposal shell only; no setState.
  final ScrollController _scroll = ScrollController();

  /// The last composed subtree and what it was composed from. Flutter skips a
  /// subtree whose widget is the identical instance, so handing the same one
  /// back makes a parent rebuild a no-op for the document (§3.27).
  Widget? _composed;
  String _composedSource = '';
  int _composedFontSize = -1;
  bool _composedCompleted = false;
  ThemeData? _composedTheme;

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
        final Widget? cached = _composed;
        if (cached != null &&
            source == _composedSource &&
            widget.fontSize == _composedFontSize &&
            widget.note.isCompleted == _composedCompleted &&
            identical(theme, _composedTheme)) {
          return cached;
        }
        _composedSource = source;
        _composedFontSize = widget.fontSize;
        _composedCompleted = widget.note.isCompleted;
        _composedTheme = theme;

        if (source.trim().isEmpty) {
          return _composed = Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              'Nothing to preview yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }

        // The metrics `MarkdownText` derives for itself, so this pane and a widget
        // card render one document the same way. Spelled out rather than shared
        // because the shape differs: one Column of blocks, or one visible slot.
        MarkdownMetrics metrics = MarkdownMetrics.of(MarkdownDensity.editor);
        final double size = TextSizes.preview(widget.fontSize);
        if (size != metrics.body) metrics = metrics.scaledTo(size);

        final MarkdownStyle style = MarkdownStyle(
          base: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: metrics.body,
            height: metrics.lineHeight,
          ),
          accent: theme.colorScheme.primary,
          muted: theme.colorScheme.onSurfaceVariant,
          metrics: metrics,
          density: MarkdownDensity.editor,
        );
        final List<MarkdownBlockSlot> slots =
            MarkdownBlockList.slotsOf(MarkdownText.nodesOf(source), style);

        // Blocks are built lazily, one per visible slot, so the cost tracks the
        // viewport rather than the note's length; and a `SelectionArea`, not
        // per-block selectable text, which stops selection crossing a block.
        return _composed = Scrollbar(
          controller: _scroll,
          child: SelectionArea(
            child: DefaultTextStyle.merge(
              style: markCompleted(const TextStyle(), completed: widget.note.isCompleted) ??
                  const TextStyle(),
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 0, 6, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final MarkdownBlockSlot s in slots)
                      s.build(style, selectable: false),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}