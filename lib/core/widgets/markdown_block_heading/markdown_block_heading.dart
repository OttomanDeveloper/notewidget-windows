import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_inline_text/markdown_inline_text.dart';
import '../markdown_style/markdown_style.dart';

/// A heading, sized by level with a floor from the metrics, so `h6` never reads
/// smaller than the body around it.
class MarkdownBlockHeading extends StatelessWidget {
  const MarkdownBlockHeading({
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
    final level = int.tryParse(node.tag.substring(1)) ?? 1;
    final step = 1 - ((level - 1) * 0.11).clamp(0.0, 1.0);
    final size = (style.metrics.body * style.metrics.headingScale * step)
        .clamp(style.metrics.body * style.metrics.minHeadingScale, 40.0)
        .toDouble();

    return Padding(
      padding: EdgeInsets.only(top: style.metrics.paragraphGap),
      child: MarkdownInlineText(
        node: node,
        style: style.withBase(style.base.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w700,
          // Tight: a heading with loose leading reads as a paragraph in a
          // slightly larger font.
          height: 1.2,
        )),
        maxLines: maxLines,
        selectable: selectable,
      ),
    );
  }
}
