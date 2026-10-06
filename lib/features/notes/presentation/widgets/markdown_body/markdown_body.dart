import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/note.dart';
import '../narrow_preview_button/narrow_preview_button.dart';
import '../preview_pane/preview_pane.dart';
import '../source_field/source_field.dart';
import '../text_size_wheel_listener/text_size_wheel_listener.dart';

/// The Markdown body: source left, render right. Below [previewThreshold] the
/// preview becomes a switch rather than two cramped columns. Ctrl+wheel resizes
/// the pane under the pointer. See widget_pattern.md §3.21.
class MarkdownBody extends StatelessWidget {
  const MarkdownBody({
    super.key,
    required this.note,
    required this.field,
    required this.focusNode,
    required this.previewSource,
    required this.showsPreview,
    required this.onChanged,
    this.editorFontSize = 0,
    this.previewFontSize = 0,
    this.onEditorFontStep,
    this.onPreviewFontStep,
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

  final int editorFontSize;
  final int previewFontSize;

  /// One step per wheel notch, positive is larger. Null disables the gesture,
  /// which is what the widget surface and the list rows want.
  final ValueChanged<int>? onEditorFontStep;
  final ValueChanged<int>? onPreviewFontStep;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= previewThreshold;

        if (!wide) {
            // One builder over the whole narrow column: an earlier version left the
            // button outside while it still read the flag, so tapping "Preview" switched
            // the pane and left the label stale (`markdown_test` caught it).
          return ValueListenableBuilder<bool>(
            valueListenable: showsPreview,
            builder: (BuildContext context, bool shows, _) => TextSizeWheelListener(
              narrowShowsPreview: shows,
              onEditorStep: onEditorFontStep,
              onPreviewStep: onPreviewFontStep,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // One or the other, not both: at this width two panes of prose
                  // side by side are two unreadable columns.
                  Expanded(
                    child: shows
                        ? PreviewPane(
                            note: note,
                            previewSource: previewSource,
                            fontSize: previewFontSize,
                          )
                        : SourceField(
                            field: field,
                            focusNode: focusNode,
                            note: note,
                            onChanged: onChanged,
                            fontSize: editorFontSize,
                          ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      const SizedBox(width: 2),
                      NarrowPreviewButton(
                        showsPreview: shows,
                        onToggle: () => showsPreview.value = !shows,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        // Two equal panes either side of a 1px divider, so the divider's position
        // is half the width. Measured from the pointer rather than guessed.
        return TextSizeWheelListener(
          onEditorStep: onEditorFontStep,
          onPreviewStep: onPreviewFontStep,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: SourceField(
                  field: field,
                  focusNode: focusNode,
                  note: note,
                  onChanged: onChanged,
                  fontSize: editorFontSize,
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
                child: PreviewPane(
                  note: note,
                  previewSource: previewSource,
                  fontSize: previewFontSize,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
