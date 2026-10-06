import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_style/markdown_style.dart';

/// Inline spans for a node, ignoring block structure entirely.
/// Pure functions taking the style explicitly, so one pass cannot leak into
/// the next.
class MarkdownSpans {
  const MarkdownSpans._();

  static List<InlineSpan> of(md.Node node, MarkdownStyle style) {
    if (node is md.Text) {
      if (node.text.isEmpty) return const [];
      // Attached here so `**` inside a heading keeps heading size: inheriting
      // would render it at body size, and this arm handles every leaf.
      return [TextSpan(text: node.text, style: style.base)];
    }
    if (node is! md.Element) return const [];

    final children = node.children ?? const <md.Node>[];

    switch (node.tag) {
      // `strong`/`em`/`del` only: raw `<b>` arrives as literal text, so other
      // tags would be rules nothing can reach.
      case 'strong':
        return wrap(children, style,
            style.base.copyWith(fontWeight: FontWeight.w700));

      case 'em':
        return wrap(children, style,
            style.base.copyWith(fontStyle: FontStyle.italic));

      case 'del':
        return wrap(children, style,
            style.base.copyWith(decoration: TextDecoration.lineThrough));

      case 'code':
        return [
          TextSpan(
            text: node.textContent,
            style: style.base.copyWith(
              fontFamily: 'Consolas',
              fontFamilyFallback: const ['monospace'],
              fontSize: (style.base.fontSize ?? 13) - 1,
              color: style.accent,
            ),
          ),
        ];

      case 'a':
        // Styled, not clickable. See the class comment: the app does not touch
        // the internet, and the href is still in the source.
        return [
          TextSpan(
            text: node.textContent,
            style: style.base.copyWith(
              color: style.accent,
              decoration: TextDecoration.underline,
              decorationColor: style.accent.withValues(alpha: 0.5),
            ),
          ),
        ];

      case 'img':
        // Alt text. The alternatives are a broken image or a network fetch, and
        // this app has no network code.
        return [
          TextSpan(
            text: node.attributes['alt'] ?? '',
            style: style.base.copyWith(
              color: style.muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ];

      case 'br':
        return const [TextSpan(text: '\n')];

      default:
        if (children.isEmpty) {
          final text = node.textContent;
          return text.isEmpty ? const [] : [TextSpan(text: text)];
        }
        return wrap(children, style, null);
    }
  }

  static List<InlineSpan> wrap(
    List<md.Node> children,
    MarkdownStyle style,
    TextStyle? override,
  ) {
    final effective = override == null ? style : style.withBase(override);
    final spans = <InlineSpan>[];
    for (final child in children) {
      spans.addAll(of(child, effective));
    }
    return spans;
  }
}
