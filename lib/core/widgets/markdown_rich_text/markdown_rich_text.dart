import 'package:flutter/material.dart';

/// Text with the clip-or-ellipsis contract and editor-only selection: cards are
/// drag handles first, so selecting on drag would misfire every gesture.
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
