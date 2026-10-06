import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../narrow_preview_button/narrow_preview_button.dart';
import '../preview_pane/preview_pane.dart';
import '../source_field/source_field.dart';

/// The Markdown body: source left, render right. Below [previewThreshold] the
/// preview becomes a switch: a narrow window cannot show both, and asking beats
/// guessing or silently showing neither.
class MarkdownBody extends StatelessWidget {
  const MarkdownBody({
    super.key,
    required this.note,
    required this.field,
    required this.focusNode,
    required this.previewSource,
    required this.showsPreview,
    required this.onChanged,
  });

    /// Width below which the editor shows source or preview, not both. Chosen
    /// against the useful minimum, not a round number: at 1000px the side-by-side
    /// layout is still the normal one.
  static const double previewThreshold = 460;

  final Note note;
  final TextEditingController field;
  final FocusNode focusNode;
  final ValueNotifier<String> previewSource;

  /// Whether the narrow layout shows the preview. Owned by the pane's State;
  /// read here through a listener, never bare.
  final ValueNotifier<bool> showsPreview;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= previewThreshold;

        if (!wide) {
            // One builder over the whole narrow column: an earlier version left the
            // button outside while it still read the flag, so tapping "Preview" switched
            // the pane and left the label stale (`markdown_test` caught it).
          return ValueListenableBuilder<bool>(
            valueListenable: showsPreview,
            builder: (context, shows, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // One or the other, not both: at this width two panes of prose
                // side by side are two unreadable columns.
                Expanded(
                  child: shows
                      ? PreviewPane(note: note, previewSource: previewSource)
                      : SourceField(
                          field: field,
                          focusNode: focusNode,
                          note: note,
                          onChanged: onChanged,
                        ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 2),
                    NarrowPreviewButton(
                      showsPreview: shows,
                      onToggle: () => showsPreview.value = !shows,
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SourceField(
                field: field,
                focusNode: focusNode,
                note: note,
                onChanged: onChanged,
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              indent: 2,
              endIndent: 2,
              color: theme.dividerColor,
            ),
            Expanded(
              child: PreviewPane(note: note, previewSource: previewSource),
            ),
          ],
        );
      },
    );
  }
}
