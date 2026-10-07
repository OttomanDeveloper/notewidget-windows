import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_alert/markdown_alert.dart';
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
    final md.Node textNode = node;
    if (textNode is md.Text) {
      if (MarkdownNodes.isBlank(textNode)) return const SizedBox.shrink();
      return MarkdownBlockParagraph(
        node: textNode,
        style: style,
        maxLines: maxLines,
        selectable: selectable,
      );
    }
    final md.Node element = node;
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

      case 'div':
        // Only the alert `<div>` reaches here; a raw `<div>` is literal text
        // because `encodeHtml: false`, so this cannot catch anything else.
        if ((element.attributes['class'] ?? '').contains('markdown-alert')) {
          return MarkdownAlert(
            node: element,
            style: style,
            depth: depth,
            maxLines: maxLines,
            selectable: selectable,
          );
        }
        return MarkdownBlockList(
          nodes: MarkdownNodes.childBlocks(element),
          style: style,
          depth: depth,
          maxLines: maxLines,
          selectable: selectable,
        );

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

      case 'section':
        // The footnote block. Rendering its `<ol>` as a list printed the number
        // twice - as the glyph and again from the `<sup>` reference - so the
        // `<ol>` is skipped. See widget_pattern.md §3.15.
        return MarkdownBlockList(
          nodes: _footnoteItems(element),
          style: style,
          depth: depth,
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
        // `isBlank`, not `textContent`: an image-only block is not blank. See
        // `MarkdownNodes.isBlank` and widget_pattern.md §3.15.
        if (MarkdownNodes.isBlank(element)) return const SizedBox.shrink();
        return MarkdownBlockParagraph(
          node: element,
          style: style,
          maxLines: maxLines,
          selectable: selectable,
        );
    }
  }

  /// The `<li>` items inside a footnote `<section>`'s `<ol>`. The `<ol>` carries
  /// the parser's numbering and the `<li>` wraps the footnote in a `<p>`; a
  /// section with no `<ol>` falls back to its own children.
  static List<md.Node> _footnoteItems(md.Element section) {
    final List<md.Node> children = section.children ?? const <md.Node>[];
    final md.Element? ordered = children
        .whereType<md.Element>()
        .cast<md.Element?>()
        .firstWhere((md.Element? e) => e?.tag == 'ol', orElse: () => null);
    return ordered?.children ?? children;
  }
}
