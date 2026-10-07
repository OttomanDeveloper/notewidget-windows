import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_style/markdown_style.dart';

/// Inline spans for a node, ignoring block structure entirely.
/// Pure functions taking the style explicitly, so one pass cannot leak into
/// the next.
class MarkdownSpans {
  const MarkdownSpans._();

  /// Markup for the reader and nothing for the author, so it is not drawn. Hoisted
  /// because [of] is a build path and §3.5 bans a RegExp built there.
  static final RegExp _comment = RegExp(r'<!--[\s\S]*?-->');

  static List<InlineSpan> of(md.Node node, MarkdownStyle style) {
    if (node is md.Text) {
      if (node.text.isEmpty) return const <InlineSpan>[];
      // Attached here so `**` inside a heading keeps heading size: inheriting
      // would render it at body size, and this arm handles every leaf.
      final String text = node.text.replaceAll(_comment, '');
      if (text.trim().isEmpty) return const <InlineSpan>[];
      if (text.contains('<br>')) return _withBreaks(text, style);
      return <InlineSpan>[TextSpan(text: text, style: style.base)];
    }
    if (node is! md.Element) return const <InlineSpan>[];

    final List<md.Node> children = node.children ?? const <md.Node>[];

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
        return <InlineSpan>[
          TextSpan(
            text: node.textContent,
            style: style.base.copyWith(
              fontFamily: 'Consolas',
              fontFamilyFallback: const <String>['monospace'],
              fontSize: (style.base.fontSize ?? 13) - 1,
              color: style.accent,
            ),
          ),
        ];

      case 'a':
        // Styled, not clickable. See the class comment: the app does not touch
        // the internet, and the href is still in the source.
        return <InlineSpan>[
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
        return <InlineSpan>[
          TextSpan(
            text: node.attributes['alt'] ?? '',
            style: style.base.copyWith(
              color: style.muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ];

      // Unreachable for a raw tag, which arrives as literal text; kept for the case
        // where the parser does build a `br`, and see [_withBreaks].
      case 'br':
        return const <InlineSpan>[TextSpan(text: '\n')];

      case 'p':
        // The alert title is a `<p class="markdown-alert-title">`. Drawn as a
        // label in the accent, not as body prose, or `[!NOTE]` reads as a
        // sentence that happens to start with the word Note.
        if ((node.attributes['class'] ?? '').contains('markdown-alert-title')) {
          return <InlineSpan>[
            TextSpan(
              text: node.textContent,
              style: style.base.copyWith(
                fontWeight: FontWeight.w600,
                color: style.accent,
              ),
            ),
          ];
        }
        return wrap(children, style, null);

      case 'sup':
        // The footnote reference. Not `verticalAlign`, which needs a text
        // direction this paragraph does not have; a smaller accent is enough.
        return wrap(
          children,
          style,
          style.base.copyWith(
            fontSize: (style.base.fontSize ?? 13) * 0.75,
            color: style.accent,
          ),
        );

      default:
        if (children.isEmpty) {
          final String text = node.textContent;
          return text.isEmpty ? const <InlineSpan>[] : <InlineSpan>[TextSpan(text: text)];
        }
        return wrap(children, style, null);
    }
  }

  /// `<br>` as a line break, split out of the text run. The `br` element case
  /// cannot do this: `encodeHtml: false` hands `a<br>b` back as one text node
  /// with the tag inside it. Every other raw tag stays literal (§3.15).
  static List<InlineSpan> _withBreaks(String text, MarkdownStyle style) {
    final List<InlineSpan> spans = <InlineSpan>[];
    for (final String part in text.split('<br>')) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n'));
      if (part.isNotEmpty) spans.add(TextSpan(text: part, style: style.base));
    }
    return spans;
  }

  static List<InlineSpan> wrap(
    List<md.Node> children,
    MarkdownStyle style,
    TextStyle? override,
  ) {
    final MarkdownStyle effective = override == null ? style : style.withBase(override);
    final List<InlineSpan> spans = <InlineSpan>[];
    for (final md.Node child in children) {
      spans.addAll(of(child, effective));
    }
    return spans;
  }
}
