import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../narrow_preview_button/narrow_preview_button.dart';
import '../pane_divider/pane_divider.dart';
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
    this.sourceFraction = 0.5,
    this.onSplit,
    this.onResetSplit,
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

  /// Share of this body given to the source, 0 to 1. 0.5 is the even split the
  /// two `Expanded`s gave before, and stays the default when [onSplit] is null.
  final double sourceFraction;

  /// Drag on the divider. Null leaves it a plain line, which is what the widget
  /// surface and the list rows get - they have no two panes to divide.
  final ValueChanged<double>? onSplit;

  /// Double-click on the divider.
  final VoidCallback? onResetSplit;

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

        // A draggable split rather than two equal halves: the source takes the
        // fraction, the preview the rest. The drag arrives as a delta and is
        // folded on - reading the body's left edge instead would need
        final double grab = onSplit == null ? 1.0 : 10.0;
        final double usable =
            (constraints.maxWidth - grab).clamp(1.0, double.infinity);
        final double sourceWidth = usable * sourceFraction.clamp(0.0, 1.0);

        return TextSizeWheelListener(
          onEditorStep: onEditorFontStep,
          onPreviewStep: onPreviewFontStep,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: sourceWidth,
                child: SourceField(
                  field: field,
                  focusNode: focusNode,
                  note: note,
                  onChanged: onChanged,
                  fontSize: editorFontSize,
                ),
              ),
              if (onSplit == null)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 2,
                  endIndent: 2,
                  color: theme.dividerColor,
                )
              else
                PaneDivider(
                  onDrag: (double dx) =>
                      onSplit!(sourceFraction + dx / usable),
                  onReset: onResetSplit,
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
