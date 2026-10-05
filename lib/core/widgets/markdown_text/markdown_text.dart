import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../markdown_block_list/markdown_block_list.dart';
import '../markdown_density/markdown_density.dart';
import '../markdown_inline_line/markdown_inline_line.dart';
import '../markdown_metrics/markdown_metrics.dart';
import '../markdown_style/markdown_style.dart';

/// Renders Markdown into ordinary Flutter widgets.
///
/// **Why a renderer written here rather than a Markdown widget package.** The
/// parser is the hard part and is not reimplemented: this builds on
/// `package:markdown`, a conforming CommonMark implementation with GitHub
/// Flavored extensions. What is written here is the *presentation*, for two
/// reasons a package could not satisfy. The widget floats over an arbitrary
/// desktop wallpaper in a 360px window, so what it can honestly render is a
/// deliberate subset — a card cannot show a heading tree, and making it try
/// produces something worse than prose. And a package's theming is built around
/// Material's defaults, which would fight the nine colour palettes this app has.
/// Owning the renderer also means the widget and the editor preview cannot
/// disagree, because they are the same code with a different budget.
///
/// **Supported**, in both densities:
///
/// * headings, paragraphs, horizontal rules
/// * ordered, unordered and task lists, nested
/// * block quotes
/// * fenced and indented code blocks, and inline code
/// * bold, italic, strikethrough, links, images (as their alt text)
/// * tables, at [MarkdownDensity.editor] only
///
/// **Not supported, and what happens instead:**
///
/// * **Links are styled but not clickable.** `PROJECT.md` says the app "does
///   not touch the internet at all", and a widget with nowhere to send you has
///   no business pretending otherwise. The href stays in the source.
/// * Raw HTML is not interpreted. CommonMark passes it through as text, which is
///   the safe reading — rendering it would be a way for a note to try.
/// * Anything unrecognised degrades to its text content rather than
///   disappearing. A note must never render as less than what it says.
///
/// **Task list markers are decoration, not controls.** A `- [x]` renders as a
/// filled box and cannot be clicked. Completion in this app is per *note* — the
/// circle beside the title, and `Ctrl+D` — while a Markdown task list is per
/// *line*, and two sources of truth for "is this done" is worse than one that
/// only looks like the other.
class MarkdownText extends StatelessWidget {
  /// How much of a line the clamp's fade covers, in lines.
  ///
  /// Shared between [budgetForLines] and the shader, so the two cannot drift: if
  /// the budget did not include the band the shader fades, the last readable
  /// line would be eaten by the fade instead of being shown.
  static const double _fadeLines = 0.55;

  /// The box height that shows [lines] whole lines and fades in the next.
  ///
  /// The fade band is *added* to the requested lines rather than taken out of
  /// them. Two lines means two lines you can read, plus a hint of what is below
  /// — which is what the plain-text preview has always done with its ellipsis,
  /// and what a reader expects "two lines" to mean. Sizing the box at exactly
  /// two lines and fading its bottom 55% instead leaves the second line
  /// unreadable, which looks like the renderer lost a line rather than like a
  /// clamp.
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
  ///
  /// Null means "whatever [density] says", and density is the usual answer.
  /// This exists for the one case density cannot express: the compact card and
  /// the large card share a density but not a budget, and only the compact one
  /// needs a heading flattened. It shows the note's title immediately above the
  /// body, so a body opening with `# Title` is repeating itself - and at 1.3x
  /// that repeat eats a third of a two-line card and pushes the content out.
  /// 1.0 keeps it bold and keeps its place in the hierarchy by weight, so the
  /// line it costs is a line of content.
  final double? headingScale;

  /// Overrides the density's body size, scaling every derived measurement with
  /// it.
  ///
  /// For a surface with its own type scale. The editor's list rows are 12px
  /// `bodySmall`, not the widget's 13px, and a renderer that hard-coded its size
  /// would either fight the theme or silently ignore a change to it. Unitless
  /// ratios — line height, heading scale — are kept; the pixel values are
  /// multiplied, so a smaller surface gets proportionally tighter spacing rather
  /// than the same gaps in a smaller box.
  final double? fontSize;

  /// Renders a single line of inline formatting only, ignoring block structure.
  ///
  /// For titles. A title is one line by definition, so a `# ` in one is a
  /// mistake rather than a heading, and rendering the `# ` would be pedantic in
  /// the wrong direction — but `**` and `` ` `` in a title are people being
  /// emphatic, and those are worth honouring.
  static Widget inline(
    String source, {
    required Color color,
    required Color accent,
    required TextStyle style,
    int? maxLines,
  }) {
    final nodes = _ParseCache.of(source);
    final inlineStyle = MarkdownStyle(
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
    var metrics = MarkdownMetrics.of(density);
    if (headingScale != null) {
      metrics = metrics.withHeadingScale(headingScale!);
    }
    if (fontSize != null && fontSize != metrics.body) {
      // A surface can have its own type scale - the editor's list rows use the
      // theme's `bodySmall`, not the widget's 13px - and a renderer that
      // ignored that would either fight the theme or quietly ignore a change to
      // it.
      metrics = metrics.scaledTo(fontSize!);
    }
    final style = MarkdownStyle(
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
      // OverflowBox rather than a plain ConstrainedBox.
      //
      // A Column of blocks reports an overflow the moment its natural height
      // exceeds the box it was given, and clipping the paint does not silence
      // that - the note still threw. Giving the child unbounded height and
      // clipping the parent's edge is what actually clamps a note made of
      // blocks: `maxLines` cannot, because it bounds the lines inside one Text
      // and says nothing about how many blocks there are.
      //
      // The cut is then faded out rather than left as a hard edge. It cannot be
      // made to land on a line boundary - block gaps and a heading's own
      // padding do not sit on the line grid - and a half-visible line with a
      // sharp edge reads as a rendering fault rather than as "there is more".
      // Content shorter than the box ends above the fade and is unaffected,
      // because the child is top-aligned.
      final fadeBand = metrics.body * metrics.lineHeight * _fadeLines;
      child = SizedBox(
        height: maxHeight,
        child: ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final fadeFrom = bounds.height <= 0
                  ? 1.0
                  : ((bounds.height - fadeBand) / bounds.height)
                      .clamp(0.0, 1.0)
                      .toDouble();
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0x00000000),
                ],
                stops: [0.0, fadeFrom, 1.0],
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
///
/// The widget list re-renders on every scroll tick and the editor preview on
/// every keystroke. Parsing a short note is fast, but doing it once per card per
/// frame is work with no result.
///
/// Bounded rather than unbounded: a long editing session touches many distinct
/// bodies, and a cache that only ever grows is a leak wearing a library's
/// clothes. Re-inserting on a hit makes the eviction order least-recently-used.
class _ParseCache {
  static const int _capacity = 48;
  static final Map<String, List<md.Node>> _entries = <String, List<md.Node>>{};

  static List<md.Node> of(String source) {
    final hit = _entries.remove(source);
    if (hit != null) {
      _entries[source] = hit;
      return hit;
    }
    final nodes = _parse(source);
    _entries[source] = nodes;
    if (_entries.length > _capacity) {
      _entries.remove(_entries.keys.first);
    }
    return nodes;
  }

  /// `gitHubFlavored` because `- [ ]` task lists and pipe tables are the two
  /// things people actually write in a note, and CommonMark alone has neither.
  ///
          ),
  /// `encodeHtml: false` so raw HTML stays text. See the class comment.
  static List<md.Node> _parse(String source) => md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
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
