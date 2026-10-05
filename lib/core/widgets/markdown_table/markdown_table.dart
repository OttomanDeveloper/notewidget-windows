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
    // The rows are one level down, inside `thead` and `tbody`, not children of
    // the table. Looking only at direct children finds no rows at all and
    // renders nothing - which reads as "the parser does not do tables" rather
    // than as a bug in here.
    final rows = <List<md.Element>>[];
    void collect(md.Element parent) {
      for (final child in parent.children ?? const <md.Node>[]) {
        if (child is! md.Element) continue;
        if (child.tag == 'tr') {
          rows.add((child.children ?? const <md.Node>[])
              .whereType<md.Element>()
              .where((cell) => cell.tag == 'th' || cell.tag == 'td')
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
        children: [
          for (final (index, row) in rows.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: index == 0 ? 5 : 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final cell in row)
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
