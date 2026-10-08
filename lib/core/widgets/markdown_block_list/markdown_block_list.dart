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
    final List<Widget> blocks = slotsOf(nodes, style)
        .map((MarkdownBlockSlot slot) =>
            slot.build(style, selectable: selectable, depth: depth, maxLines: maxLines))
        .toList();

    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  /// The block/gap pairs a run of nodes produces, without building a widget.
/// Both the eager list and the preview's lazy `ListView.builder` read this,
/// so the gap rule cannot drift between them.
  static List<MarkdownBlockSlot> slotsOf(
    List<md.Node> nodes,
    MarkdownStyle style,
  ) {
    final List<MarkdownBlockSlot> slots = <MarkdownBlockSlot>[];
    bool previousWasLoose = false;

    for (final md.Node node in nodes) {
      // Consecutive loose blocks sit tighter than separated ones, which is what
      // makes a list or a quote read as one thing rather than a stack.
      final double gap = previousWasLoose ? 0.0 : style.metrics.blockGap;
      if (gap > 0 && slots.isNotEmpty) {
        slots.add(MarkdownBlockSlot.gap(gap));
      }
      slots.add(MarkdownBlockSlot.node(node));
      previousWasLoose = MarkdownNodes.isLoose(node);
    }
    return slots;
  }
}

/// One entry in a rendered run of blocks: either a block, or the gap before it.
class MarkdownBlockSlot {
  const MarkdownBlockSlot._({this.node, this.gap});

  /// A gap of [gap] logical pixels, carrying no content.
  const MarkdownBlockSlot.gap(double gap)
      : this._(gap: gap, node: null);

  /// A block built from [node].
  const MarkdownBlockSlot.node(md.Node node)
      : this._(node: node, gap: null);

  /// Null for a gap slot.
  final md.Node? node;

  /// Null for a block slot.
  final double? gap;

  bool get isGap => node == null;

  Widget build(
    MarkdownStyle style, {
    required bool selectable,
    int depth = 0,
    int? maxLines,
  }) {
    final md.Node? content = node;
    if (content == null) return SizedBox(height: gap);
    return MarkdownBlock(
      node: content,
      style: style,
      depth: depth,
      maxLines: maxLines,
      selectable: selectable,
    );
  }
}
