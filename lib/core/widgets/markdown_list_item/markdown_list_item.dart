import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_block/markdown_block.dart';
import '../markdown_inline_line/markdown_inline_line.dart';
import '../markdown_nodes/markdown_nodes.dart';
import '../markdown_style/markdown_style.dart';

/// One list item: gutter marker plus content. The parser's checkbox is dropped
/// (the glyph says it); bare text nodes are kept first, or task words go missing.
class MarkdownListItem extends StatelessWidget {
  const MarkdownListItem({
    super.key,
    required this.item,
    required this.marker,
    required this.depth,
    required this.style,
    this.maxLines,
    this.selectable = false,
  });

  final md.Element item;
  final String marker;
  final int depth;
  final MarkdownStyle style;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    // Checked before the marker, so a task list shows a box rather than a
    // bullet with a box in it.
    final String? task = MarkdownNodes.taskOf(item);

    final List<md.Node> children = (item.children ?? const <md.Node>[])
        .where((md.Node child) => !(child is md.Element && child.tag == 'input'))
        .toList();

    final List<md.Node> leading = <md.Node>[];
    final List<md.Element> blocks = <md.Element>[];
    for (final md.Node child in children) {
      if (child is md.Element) {
        blocks.add(child);
      } else if (blocks.isEmpty) {
        leading.add(child);
      }
    }

    final List<Widget> parts = <Widget>[];
    if (leading.isNotEmpty) {
      parts.add(MarkdownInlineLine(
        nodes: leading,
        style: style,
        maxLines: maxLines,
        selectable: selectable,
      ));
    }
    for (final md.Element block in blocks) {
      parts.add(MarkdownBlock(
        node: block,
        style: style,
        depth: depth + 1,
        maxLines: maxLines,
        selectable: selectable,
      ));
    }

    final Widget body;
    if (parts.isEmpty) {
      body = const SizedBox.shrink();
    } else if (parts.length == 1) {
      body = parts.single;
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: parts,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2, top: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: style.metrics.markerWidth,
            child: Text(
              task ?? marker,
              style: style.base.copyWith(
                color: task == null ? style.muted : style.accent,
                fontWeight:
                    task == null ? FontWeight.normal : FontWeight.w700,
                height: style.metrics.lineHeight,
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
