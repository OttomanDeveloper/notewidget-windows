import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_block_list/markdown_block_list.dart';
import '../markdown_style/markdown_style.dart';

/// A GitHub alert: `> [!NOTE]` and its four siblings. Adds to a quote one
/// thing — the parser's `<p class="markdown-alert-title">` drawn as a label.
class MarkdownAlert extends StatelessWidget {
  const MarkdownAlert({
    super.key,
    required this.node,
    required this.style,
    required this.depth,
    this.maxLines,
    this.selectable = false,
  });

  final md.Element node;
  final MarkdownStyle style;
  final int depth;
  final int? maxLines;
  final bool selectable;

  /// The type from `markdown-alert-<type>`, or null when the class is absent.
  String? get kind {
    final String cls = node.attributes['class'] ?? '';
    final int at = cls.indexOf('markdown-alert-');
    if (at < 0) return null;
    return cls.substring(at + 'markdown-alert-'.length);
  }

  /// The title element, if the parser put one first.
  md.Element? get _title {
    for (final md.Node child in node.children ?? const <md.Node>[]) {
      if (child is md.Element &&
          (child.attributes['class'] ?? '').contains('markdown-alert-title')) {
        return child;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final md.Element? title = _title;
    final List<md.Node> body = <md.Node>[
      for (final md.Node child in node.children ?? const <md.Node>[])
        if (!identical(child, title)) child,
    ];

    return Container(
      margin: EdgeInsets.symmetric(vertical: style.metrics.paragraphGap / 2),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: style.accent, width: 3),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: style.base.copyWith(color: style.base.color),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (title != null)
              Padding(
                padding: EdgeInsets.only(bottom: style.metrics.paragraphGap / 2),
                child: MarkdownBlockList(
                  nodes: <md.Node>[title],
                  style: style,
                  depth: depth,
                  maxLines: maxLines,
                  selectable: selectable,
                ),
              ),
            MarkdownBlockList(
              nodes: body,
              style: style,
              depth: depth,
              maxLines: maxLines,
              selectable: selectable,
            ),
          ],
        ),
      ),
    );
  }
}
