import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_list_item/markdown_list_item.dart';
import '../markdown_nodes/markdown_nodes.dart';
import '../markdown_style/markdown_style.dart';

/// An ordered or unordered list, with task boxes where the parser found them.
class MarkdownList extends StatelessWidget {
  const MarkdownList({
    super.key,
    required this.node,
    required this.style,
    required this.depth,
    required this.ordered,
    this.maxLines,
    this.selectable = false,
  });

  final md.Element node;
  final MarkdownStyle style;
  final int depth;
  final bool ordered;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final items = (node.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .where((child) => child.tag == 'li')
        .toList();

    if (items.isEmpty) return const SizedBox.shrink();

    var index = 1;

    return Padding(
      padding: EdgeInsets.only(bottom: style.metrics.paragraphGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            MarkdownListItem(
              item: item,
              marker: ordered
                  ? '${index++}.'
                  : MarkdownNodes.bulletAt(depth),
              depth: depth,
              style: style,
              maxLines: maxLines,
              selectable: selectable,
            ),
        ],
      ),
    );
  }
}
