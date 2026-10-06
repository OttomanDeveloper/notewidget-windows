import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_inline_text/markdown_inline_text.dart';
import '../markdown_style/markdown_style.dart';

/// A table flattened to one line per row, `|`-separated. Same content, no grid:
/// `textContent` concatenates cells with nothing, and less than the note said is
/// the one failure this file does not have.
class MarkdownTableText extends StatelessWidget {
  const MarkdownTableText({
    super.key,
    required this.node,
    required this.style,
    this.maxLines,
    this.selectable = false,
  });

  final md.Element node;
  final MarkdownStyle style;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];

    void collect(md.Element parent) {
      for (final child in parent.children ?? const <md.Node>[]) {
        if (child is! md.Element) continue;
        if (child.tag == 'tr') {
          final cells = (child.children ?? const <md.Node>[])
              .whereType<md.Element>()
              .where((cell) => cell.tag == 'th' || cell.tag == 'td')
              .map((cell) => cell.textContent.trim())
              .where((cell) => cell.isNotEmpty)
              .toList();
          if (cells.isNotEmpty) lines.add(cells.join(' | '));
        } else {
          collect(child);
        }
      }
    }

    collect(node);
    if (lines.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: style.metrics.paragraphGap),
      child: MarkdownInlineText(
        node: md.Element.text('p', lines.join('\n')),
        style: style,
        maxLines: maxLines,
        selectable: selectable,
      ),
    );
  }
}
