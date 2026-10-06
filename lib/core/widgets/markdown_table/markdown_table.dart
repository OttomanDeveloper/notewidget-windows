import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_inline_text/markdown_inline_text.dart';
import '../markdown_style/markdown_style.dart';

/// A table: a real grid in the editor.
///
/// See [MarkdownTableText] for the card rendering of the same content.
class MarkdownTable extends StatelessWidget {
  const MarkdownTable({
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
      // Rows live one level down (`thead`/`tbody`), not as direct children: looking
      // only there finds no rows, which reads as "no table support" instead of a bug.
    final List<List<md.Element>> rows = <List<md.Element>>[];
    void collect(md.Element parent) {
      for (final md.Node child in parent.children ?? const <md.Node>[]) {
        if (child is! md.Element) continue;
        if (child.tag == 'tr') {
          rows.add((child.children ?? const <md.Node>[])
              .whereType<md.Element>()
              .where((md.Element cell) => cell.tag == 'th' || cell.tag == 'td')
              .toList());
        } else {
          collect(child);
        }
      }
    }

    collect(node);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(vertical: style.metrics.paragraphGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (int index, List<md.Element> row) in rows.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: index == 0 ? 5 : 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final md.Element cell in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: MarkdownInlineText(
                          node: cell,
                          style: index == 0
                              ? style.withBase(style.base.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ))
                              : style,
                          maxLines: maxLines,
                          selectable: selectable,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Divider(
            height: 1,
            thickness: 1,
            color: style.muted.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}
