import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_block/markdown_block.dart';
import '../markdown_nodes/markdown_nodes.dart';
import '../markdown_style/markdown_style.dart';

/// A run of blocks with the gaps between them.
class MarkdownBlockList extends StatelessWidget {
  const MarkdownBlockList({
    super.key,
    required this.nodes,
    required this.style,
    this.depth = 0,
    this.maxLines,
    this.selectable = false,
  });

  final List<md.Node> nodes;
  final MarkdownStyle style;
  final int depth;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final List<Widget> blocks = <Widget>[];
    bool previousWasLoose = false;

    for (final md.Node node in nodes) {
      final MarkdownBlock block = MarkdownBlock(
        node: node,
        style: style,
        depth: depth,
        maxLines: maxLines,
        selectable: selectable,
      );
      // Consecutive loose blocks sit tighter than separated ones, which is what
      // makes a list or a quote read as one thing rather than a stack.
      final double gap = previousWasLoose ? 0.0 : style.metrics.blockGap;
      if (gap > 0 && blocks.isNotEmpty) blocks.add(SizedBox(height: gap));
      blocks.add(block);
      previousWasLoose = MarkdownNodes.isLoose(node);
    }

    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }
}
