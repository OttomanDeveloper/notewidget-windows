import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_inline_text/markdown_inline_text.dart';
import '../markdown_style/markdown_style.dart';

/// A paragraph, or nothing for a blank one.
class MarkdownBlockParagraph extends StatelessWidget {
  const MarkdownBlockParagraph({
    super.key,
    required this.node,
    required this.style,
    this.maxLines,
    this.selectable = false,
  });

  final md.Node node;
  final MarkdownStyle style;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (node.textContent.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: style.metrics.paragraphGap),
      child: MarkdownInlineText(
        node: node,
        style: style,
        maxLines: maxLines,
        selectable: selectable,
      ),
    );
  }
}
