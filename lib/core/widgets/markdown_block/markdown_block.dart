import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_block_heading/markdown_block_heading.dart';
import '../markdown_block_list/markdown_block_list.dart';
import '../markdown_block_paragraph/markdown_block_paragraph.dart';
import '../markdown_code_block/markdown_code_block.dart';
import '../markdown_density/markdown_density.dart';
import '../markdown_list/markdown_list.dart';
import '../markdown_nodes/markdown_nodes.dart';
import '../markdown_quote/markdown_quote.dart';
import '../markdown_style/markdown_style.dart';
import '../markdown_table/markdown_table.dart';
import '../markdown_table_text/markdown_table_text.dart';

/// One block node, dispatched by tag.
/// The switch lives here alone (empty nodes render nothing); recursion closes
/// over this widget's parameters, so nothing below takes builders.
class MarkdownBlock extends StatelessWidget {
  const MarkdownBlock({
    super.key,
    required this.node,
    required this.style,
    this.depth = 0,
    this.maxLines,
    this.selectable = false,
  });

  final md.Node node;
  final MarkdownStyle style;
  final int depth;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final textNode = node;
    if (textNode is md.Text) {
      if (textNode.text.trim().isEmpty) return const SizedBox.shrink();
      return MarkdownBlockParagraph(
        node: textNode,
        style: style,
        maxLines: maxLines,
        selectable: selectable,
      );
    }
    final element = node;
    if (element is! md.Element) return const SizedBox.shrink();

    switch (element.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return MarkdownBlockHeading(
          node: element,
          style: style,
          maxLines: maxLines,
          selectable: selectable,
        );

      case 'p':
        return MarkdownBlockParagraph(
          node: element,
          style: style,
          maxLines: maxLines,
          selectable: selectable,
        );

      case 'hr':
        return Padding(
          padding: EdgeInsets.symmetric(vertical: style.metrics.blockGap / 2),
          child: Divider(
            height: 1,
            thickness: 1,
            color: style.muted.withValues(alpha: 0.35),
          ),
        );

      case 'pre':
        return MarkdownCodeBlock(node: element, style: style);

      case 'blockquote':
        return MarkdownQuote(
          node: element,
          style: style,
          depth: depth,
          maxLines: maxLines,
          selectable: selectable,
        );

      case 'ul':
      case 'ol':
        return MarkdownList(
          node: element,
          style: style,
          depth: depth,
          ordered: element.tag == 'ol',
          maxLines: maxLines,
          selectable: selectable,
        );

      case 'table':
        // Grids do not fit cards: structure is dropped, but cells keep a `|`
        // separator, since `textContent` concatenates them with nothing.
        if (style.density == MarkdownDensity.widget) {
          return MarkdownTableText(
            node: element,
            style: style,
            maxLines: maxLines,
            selectable: selectable,
          );
        }
        return MarkdownTable(
          node: element,
          style: style,
          maxLines: maxLines,
          selectable: selectable,
        );

      default:
        // Unknown block: keep the text rather than dropping the note on the floor.
        if (MarkdownNodes.isContainer(element)) {
          return MarkdownBlockList(
            nodes: MarkdownNodes.childBlocks(element),
            style: style,
            depth: depth,
            maxLines: maxLines,
            selectable: selectable,
          );
        }
        final text = element.textContent.trim();
        if (text.isEmpty) return const SizedBox.shrink();
        return MarkdownBlockParagraph(
          node: element,
          style: style,
          maxLines: maxLines,
          selectable: selectable,
        );
    }
  }
}
