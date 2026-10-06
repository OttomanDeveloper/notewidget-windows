import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ctrl+wheel over the editor's Markdown body, resizing whichever pane the
/// pointer is over. A widget rather than a private build method so the hit-test
/// is testable and named. See widget_pattern.md §3.21.
class TextSizeWheelListener extends StatelessWidget {
  const TextSizeWheelListener({
    super.key,
    required this.child,
    required this.onEditorStep,
    required this.onPreviewStep,
    this.splitFraction = 0.5,
    this.narrowShowsPreview = false,
  });

  final Widget child;

  /// One step per notch, positive is larger. Either may be null, which turns
  /// that pane's side of the gesture off rather than the whole thing.
  final ValueChanged<int>? onEditorStep;
  final ValueChanged<int>? onPreviewStep;

  /// Where the divider sits, as a fraction of the width. The two panes are equal
  /// and either side of a 1px divider, so this is 0.5; it is a parameter only so
  /// the rule is written down once instead of being assumed.
  final double splitFraction;

  /// In the narrow layout there is one pane, not two, so the pointer's x says
  /// nothing and this flag is the whole answer.
  final bool narrowShowsPreview;

  @override
  Widget build(BuildContext context) {
    if (onEditorStep == null && onPreviewStep == null) return child;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double split = constraints.maxWidth * splitFraction;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (PointerSignalEvent event) {
            if (event is! PointerScrollEvent) return;
            if (!HardwareKeyboard.instance.isControlPressed) return;
            // Wheel up is negative, and up means bigger, which is what every
            // other application on this machine does with it.
            final int delta = event.scrollDelta.dy < 0 ? 1 : -1;
            final bool preview = narrowShowsPreview
                ? narrowShowsPreview
                : event.localPosition.dx >= split;
            if (preview) {
              onPreviewStep?.call(delta);
            } else {
              onEditorStep?.call(delta);
            }
          },
          child: child,
        );
      },
    );
  }
}