import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_block_list/markdown_block_list.dart';
import '../markdown_density/markdown_density.dart';
import '../markdown_inline_line/markdown_inline_line.dart';
import '../markdown_metrics/markdown_metrics.dart';
import '../markdown_style/markdown_style.dart';

/// Renders Markdown into Flutter widgets, over `package:markdown`. Deliberate
/// subset per density (see `docs/widget_pattern.md` §3.15); links inert, HTML as
/// text, unknown degrades to text, `- [x]` draws an inert box.
class MarkdownText extends StatelessWidget {
  /// How much of a line the clamp's fade covers, in lines.
  /// Shared with the shader so the budget includes the band the fade eats.
  static const double _fadeLines = 0.55;

  /// The box height that shows [lines] whole lines and fades in the next.
  /// The fade band is added to the lines, not taken out of them, so two
  /// lines means two readable lines plus a hint of what is below.
  static double budgetForLines({
    required double fontSize,
    required double lineHeight,
    required int lines,
  }) =>
      fontSize * lineHeight * (lines + _fadeLines);

  const MarkdownText({
    super.key,
    required this.source,
    required this.color,
    required this.accent,
    this.mutedColor,
    this.density = MarkdownDensity.editor,
    this.selectable = false,
    this.maxLines,
    this.maxHeight,
    this.headingScale,
    this.fontSize,
  });

  final String source;
  final Color color;

  /// Used for links and inline code, so a rendered note belongs to the same
  /// palette as the app around it.
  final Color accent;

  final Color? mutedColor;
  final MarkdownDensity density;
  final bool selectable;

  /// Clamps to one rendered line, for compact widget cards where the design
  /// already promises a single-line preview.
  final int? maxLines;

  /// Clamps the whole render, for the large card.
  final double? maxHeight;

  /// Overrides how much larger than body text a heading renders.
  /// Null means [density]'s answer; only the compact card flattens to 1.0 so
  /// a body opening with `# Title` does not repeat the title shown above it.
  final double? headingScale;

  /// Overrides the density's body size, scaling every derived measurement with
  /// it. Ratios kept, pixel values multiplied: a smaller surface gets tighter
  /// spacing, not the same gaps in a smaller box.
  final double? fontSize;

  /// Renders a single line of inline formatting only, ignoring block structure.
  /// For titles: one line by definition, so `# ` is a mistake but `**`/`` ` ``
  /// emphasis is still honoured.
  static Widget inline(
    String source, {
    required Color color,
    required Color accent,
    required TextStyle style,
    int? maxLines,
  }) {
    final List<md.Node> nodes = _ParseCache.of(source);
    final MarkdownStyle inlineStyle = MarkdownStyle(
      base: style,
      accent: accent,
      muted: color.withValues(alpha: 0.62),
      metrics: MarkdownMetrics.editor,
      density: MarkdownDensity.editor,
    );
    // The caller's line count is honoured here. It previously was not:
    // `buildInlineLine` always passed a hard-coded 1, which meant a caller
    // asking for two lines - the large widget card's title - silently got one.
    return MarkdownInlineLine(
      nodes: nodes,
      style: inlineStyle,
      maxLines: maxLines,
    );
  }

  @override
  Widget build(BuildContext context) {
    MarkdownMetrics metrics = MarkdownMetrics.of(density);
    if (headingScale != null) {
      metrics = metrics.withHeadingScale(headingScale!);
    }
    if (fontSize != null && fontSize != metrics.body) {
      // Surface type scale (editor rows are `bodySmall`): scale rather than
      // fight the theme or ignore a change to it.
      metrics = metrics.scaledTo(fontSize!);
    }
    final MarkdownStyle style = MarkdownStyle(
      base: TextStyle(
        color: color,
        fontSize: metrics.body,
        height: metrics.lineHeight,
      ),
      accent: accent,
      muted: mutedColor ?? color.withValues(alpha: 0.62),
      metrics: metrics,
      density: density,
    );

    Widget child = MarkdownBlockList(
      nodes: _ParseCache.of(source),
      style: style,
      depth: 0,
      maxLines: maxLines,
      selectable: selectable,
    );

    if (maxHeight != null) {
      // OverflowBox + ClipRect + fade: a Column of blocks overflows its box and
      // clipping paint does not silence it; `maxLines` bounds one Text, not
      // a block count. The cut is faded (it cannot land on a line boundary).
      final double fadeBand = metrics.body * metrics.lineHeight * _fadeLines;
      child = SizedBox(
        height: maxHeight,
        child: ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (Rect bounds) {
              final double fadeFrom = bounds.height <= 0
                  ? 1.0
                  : ((bounds.height - fadeBand) / bounds.height)
                      .clamp(0.0, 1.0)
                      .toDouble();
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const <Color>[
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0x00000000),
                ],
                stops: <double>[0.0, fadeFrom, 1.0],
              ).createShader(bounds);
            },
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: child,
            ),
          ),
        ),
      );
    }

    return DefaultTextStyle.merge(
      style: TextStyle(color: color, fontSize: metrics.body),
      child: child,
    );
  }
}

/// Parsed Markdown, memoised by source text.
/// Re-renders happen per scroll tick/keystroke; bounded (LRU, 48) so a long
/// session does not leak.
class _ParseCache {
  static const int _capacity = 48;
  static final Map<String, List<md.Node>> _entries = <String, List<md.Node>>{};

  static List<md.Node> of(String source) {
    final List<md.Node>? hit = _entries.remove(source);
    if (hit != null) {
      _entries[source] = hit;
      return hit;
    }
    final List<md.Node> nodes = _parse(source);
    _entries[source] = nodes;
    if (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
    return nodes;
  }

  /// `gitHubFlavored`, plus emoji and alerts — which the parser implements and
  /// that set omits, so they are named here. `encodeHtml: false`, §3.15.
  static final md.ExtensionSet _extensions = md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes +
            <md.BlockSyntax>[const md.AlertBlockSyntax()],
        md.ExtensionSet.gitHubFlavored.inlineSyntaxes +
            <md.InlineSyntax>[md.EmojiSyntax()],
      );

  static List<md.Node> _parse(String source) => md.Document(
        extensionSet: _extensions,
        encodeHtml: false,
      ).parseLines(_lines(source));

  /// CRLF normalised first, or every body line ends in a stray `\r` that shows
  /// up as a stray glyph in the preview.
  static List<String> _lines(String source) {
    if (source.isEmpty) return const <String>[];
    return source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
  }
}
