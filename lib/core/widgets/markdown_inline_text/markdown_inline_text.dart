import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_rich_text/markdown_rich_text.dart';
import '../markdown_spans/markdown_spans.dart';
import '../markdown_style/markdown_style.dart';

/// One element's inline content as a run of styled text.
class MarkdownInlineText extends StatelessWidget {
  const MarkdownInlineText({
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
    final spans = MarkdownSpans.of(node, style);
    if (spans.isEmpty) return const SizedBox.shrink();
    return MarkdownRichText(
      span: TextSpan(style: style.base, children: spans),
      maxLines: maxLines,
      selectable: selectable,
    );
  }
}
