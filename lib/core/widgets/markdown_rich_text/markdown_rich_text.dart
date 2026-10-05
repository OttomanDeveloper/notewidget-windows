import 'package:flutter/material.dart';

/// A span of text with the renderer's clipping contract.
///
/// With no line limit the clip is the point - a block taller than its box is
/// already being clipped by the caller. With one, ellipsis is the honest way
/// to say there is more. Selectable only ever on the editor side: a widget
/// card is a drag handle first, and a card that starts selecting text when
/// someone drags across it turns every drag into a misfire.
class MarkdownRichText extends StatelessWidget {
  const MarkdownRichText({
    super.key,
    required this.span,
    this.maxLines,
    this.selectable = false,
  });

  final InlineSpan span;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(
      span,
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
    if (!selectable) return text;
    return SelectionArea(child: text);
  }
}
