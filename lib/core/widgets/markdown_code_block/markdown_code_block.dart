import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_nodes/markdown_nodes.dart';
import '../markdown_style/markdown_style.dart';

/// A fenced or indented code block, clamped to the density's line budget.
class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({
    super.key,
    required this.node,
    required this.style,
  });

  final md.Element node;
  final MarkdownStyle style;

  @override
  Widget build(BuildContext context) {
    // The fence's language arrives as a class on the inner <code>, e.g.
    // `class="language-dart"`. Shown when there is room, because it is often
    // the only clue about what a snippet is.
    final String language = MarkdownNodes.languageOf(node);
    final List<String> lines = node.textContent.trimRight().split('\n');
    final List<String> shown = lines.take(style.metrics.maxCodeLines).toList();
    final int hidden = lines.length - shown.length;

    final Text code = Text.rich(
      TextSpan(
        text: shown.join('\n'),
        style: style.base.copyWith(
          fontFamily: 'Consolas',
          fontFamilyFallback: const <String>['monospace'],
          fontSize: style.metrics.body - 1,
          height: 1.4,
        ),
      ),
    );

    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: style.metrics.paragraphGap / 2),
      padding: EdgeInsets.all(style.metrics.codePadding),
      decoration: BoxDecoration(
        color: style.muted.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (language.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                language,
                style: TextStyle(
                  fontSize: style.metrics.body - 3,
                  color: style.muted,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          code,
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+$hidden more lines',
                style: TextStyle(
                  fontSize: style.metrics.body - 3,
                  color: style.muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
