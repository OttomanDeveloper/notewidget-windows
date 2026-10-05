import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_block_list/markdown_block_list.dart';
import '../markdown_nodes/markdown_nodes.dart';
import '../markdown_style/markdown_style.dart';

/// A block quote, with its children rendered inside.
class MarkdownQuote extends StatelessWidget {
  const MarkdownQuote({
    super.key,
    required this.node,
    required this.style,
    required this.depth,
    this.maxLines,
    this.selectable = false,
  });

  final md.Element node;
  final MarkdownStyle style;
  final int depth;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: style.metrics.paragraphGap / 2),
      padding: EdgeInsets.only(left: style.metrics.quoteIndent),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: style.muted.withValues(alpha: 0.45),
            width: 3,
          ),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: style.base.copyWith(
          color: style.muted,
          fontStyle: FontStyle.italic,
        ),
        child: MarkdownBlockList(
          nodes: MarkdownNodes.childBlocks(node),
          style: style,
          depth: depth,
          maxLines: maxLines,
          selectable: selectable,
        ),
      ),
    );
  }
}
