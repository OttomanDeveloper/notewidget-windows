import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_rich_text/markdown_rich_text.dart';
import '../markdown_spans/markdown_spans.dart';
import '../markdown_style/markdown_style.dart';

/// A single line of inline formatting across [nodes], for titles.
class MarkdownInlineLine extends StatelessWidget {
  const MarkdownInlineLine({
    super.key,
    required this.nodes,
    required this.style,
    this.maxLines,
    this.selectable = false,
  });

  final List<md.Node> nodes;
  final MarkdownStyle style;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      spans.addAll(MarkdownSpans.of(node, style));
    }
    if (spans.isEmpty) {
      return Text('', style: style.base, maxLines: maxLines);
    }
    return MarkdownRichText(
      span: TextSpan(style: style.base, children: spans),
      maxLines: maxLines,
      selectable: selectable,
    );
  }
}
