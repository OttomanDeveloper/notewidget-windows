import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_block/markdown_block.dart';
import '../markdown_inline_line/markdown_inline_line.dart';
import '../markdown_nodes/markdown_nodes.dart';
import '../markdown_style/markdown_style.dart';

/// One list item: the gutter marker and the item's own content.
///
/// The checkbox the parser produced for a task item is dropped here: the
/// glyph in the gutter already says so, and the element renders as nothing.
///
/// Text nodes are kept as well as elements, and they come first. A task item
/// arrives as `[<input>, Text('open')]` with no paragraph element at all, so
/// a version that looked only at child elements rendered the box and dropped
/// the words next to it.
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
    final task = MarkdownNodes.taskOf(item);

    final children = (item.children ?? const <md.Node>[])
        .where((child) => !(child is md.Element && child.tag == 'input'))
        .toList();

    final leading = <md.Node>[];
    final blocks = <md.Element>[];
    for (final child in children) {
      if (child is md.Element) {
        blocks.add(child);
      } else if (blocks.isEmpty) {
        leading.add(child);
      }
    }

    final parts = <Widget>[];
    if (leading.isNotEmpty) {
      parts.add(MarkdownInlineLine(
        nodes: leading,
        style: style,
        maxLines: maxLines,
        selectable: selectable,
      ));
    }
    for (final block in blocks) {
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
        children: [
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
