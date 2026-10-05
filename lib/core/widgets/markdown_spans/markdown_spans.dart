import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_style/markdown_style.dart';

/// Inline spans for a node, ignoring block structure entirely.
///
/// Pure functions: every span builder takes the style explicitly, so rendering
/// the same node twice cannot leak state from the first pass into the second.
class MarkdownSpans {
  const MarkdownSpans._();

  static List<InlineSpan> of(md.Node node, MarkdownStyle style) {
    if (node is md.Text) {
      if (node.text.isEmpty) return const [];
      // The style is attached here rather than left to the enclosing span.
      // Leaving it off means the run inherits from the block, which is the
      // *body* style - so `**bold**` inside a heading rendered at body size and
      // body weight. The two cases that actually need a style are handled in
      // the switch below; this one handles every leaf.
      return [TextSpan(text: node.text, style: style.base)];
    }
    if (node is! md.Element) return const [];

    final children = node.children ?? const <md.Node>[];

    switch (node.tag) {
      // `strong`, `em` and `del` only. Not `b`, `i`, `s` or `strike`: the
      // parser emits the long forms for Markdown emphasis, and raw `<b>` in a
      // note arrives as literal text rather than as an element, so a case for
      // those tags would be a rule nothing can reach.
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
