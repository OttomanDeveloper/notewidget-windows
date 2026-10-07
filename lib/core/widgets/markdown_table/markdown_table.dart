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

  /// Narrowest a column may be squeezed to before the table scrolls sideways.
  /// Roughly ten characters at body size, which is where a cell stops being
  /// readable and starts breaking `+91 98765 43210` into a column of digits.
  static const double minCellWidth = 84;

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
      // `LayoutBuilder`, not `MediaQuery.sizeOf`: in a side-by-side editor the
      // preview is half the window, and the screen width would promise room
      // this table does not have.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = rows.first.length;
          // Too many columns for the pane: each takes a natural width and the
          // table scrolls sideways. Only the cell wrapper differs, since
          // `Expanded` needs a bounded width and a scroll view does not.
          final bool scrolls = columns * minCellWidth > constraints.maxWidth;
          // A header rule drawn as a border rather than a `Divider`: inside a
          // scroll view a Divider is unbounded and cannot lay out.
          final BoxDecoration headerRule = BoxDecoration(
            border: Border(
              bottom: BorderSide(color: style.muted.withValues(alpha: 0.3), width: 1),
            ),
          );

          final List<Widget> lines = <Widget>[];
          for (final (int i, List<md.Element> row) in rows.indexed) {
            final MarkdownStyle rowStyle = i == 0
                ? style.withBase(style.base.copyWith(fontWeight: FontWeight.w600))
                : style;
            final List<Widget> cells = <Widget>[];
            for (final md.Element cell in row) {
              final Widget text = MarkdownInlineText(
                node: cell,
                style: rowStyle,
                maxLines: maxLines,
                selectable: selectable,
              );
              final Widget padded =
                  Padding(padding: const EdgeInsets.only(right: 10), child: text);
              cells.add(scrolls
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: minCellWidth),
                      child: padded,
                    )
                  : Expanded(child: padded));
            }
            final Widget line = Row(
              mainAxisSize: scrolls ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: cells,
            );
            lines.add(Padding(
              padding: EdgeInsets.only(bottom: i == 0 ? 5 : 3),
              child: i == 0 ? DecoratedBox(decoration: headerRule, child: line) : line,
            ));
          }

          final Widget table = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: lines,
          );
          return scrolls
              ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)
              : table;
        },
      ),
    );
  }
}
