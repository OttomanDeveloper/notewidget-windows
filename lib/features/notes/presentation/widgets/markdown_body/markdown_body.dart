import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../narrow_preview_button/narrow_preview_button.dart';
import '../preview_pane/preview_pane.dart';
import '../source_field/source_field.dart';

/// The Markdown body: the source on the left, the rendered note on the right.
///
/// Below [previewThreshold] there is not room for two panes of prose, so the
/// preview becomes a switch rather than a column: someone editing a formatted
/// note in a narrow window needs to see the result, and needs to see the
/// source, and cannot have both at once. Asking is better than guessing, and
/// better than silently showing neither.
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

  /// Width below which the editor shows the source or the preview rather than
  /// both.
  ///
  /// Chosen against the editor's own minimum useful width rather than a round
  /// number: at 1000px the pane beside a 320px list is around 620, so the side-by-
  /// side layout is the normal one and this only bites on a deliberately narrow
  /// window.
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
          // One builder over the *whole* narrow column, not just the pane.
          //
          // The first version wrapped only the `Expanded`, leaving the button
          // outside it while the button still read the flag - a hidden
          // dependency with nothing to rebuild it. Tapping "Preview" switched
          // the pane and left the label reading "Preview", so the button
          // offered the same action twice and `markdown_test` caught it.
          //
          // The flag is then *passed* to the button rather than read there, so a
          // second reader cannot reintroduce the same shape: the only place the
          // flag is read is inside a listener.
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
