import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

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
/// How much room the renderer has, which decides how much structure it shows.
///
/// Not a quality setting. The same note at widget density is not a worse version
/// of the same note at editor density; it is the most a card can carry without
/// truncating into nonsense.
enum MarkdownDensity {
  /// A widget card. Inline formatting is real; block structure is compressed.
  widget,

  /// The editor's preview pane. Everything, comfortably.
  editor,
}

/// Type sizes and spacing for one density.
///
/// Every number lives here rather than inline, because the whole difference
/// between the two surfaces is these values and they should be comparable.
@immutable
class _Metrics {
  const _Metrics({
    required this.body,
    required this.lineHeight,
    required this.paragraphGap,
    required this.blockGap,
    required this.headingScale,
    required this.minHeadingScale,
    required this.quoteIndent,
    required this.codePadding,
    required this.maxCodeLines,
    required this.markerWidth,
  });

  final double body;
  final double lineHeight;

  /// Space after a paragraph, and the space above a heading.
  final double paragraphGap;

  /// Space between separate blocks.
  final double blockGap;

  /// Multiplier for an `h1`, shrinking with each level.
  final double headingScale;

  /// The smallest a heading may get, relative to body text.
  ///
  /// Without a floor, an `h6` in a card is smaller than the body around it,
  /// which inverts the one thing a heading is for.
  final double minHeadingScale;

  final double quoteIndent;
  final double codePadding;

  /// Code blocks clamp to this many lines. A twenty-line snippet has no meaning
  /// in a card, and truncating it says so; scrolling it does not fit.
  final int maxCodeLines;

  /// Width reserved for a bullet or number, so wrapped text lines up.
  final double markerWidth;

  static const widget = _Metrics(
    body: 13,
    lineHeight: 1.35,
    paragraphGap: 6,
    blockGap: 7,
    headingScale: 1.3,
    minHeadingScale: 1.05,
    quoteIndent: 8,
    codePadding: 6,
    maxCodeLines: 3,
    markerWidth: 15,
  );

  static const editor = _Metrics(
    body: 14.5,
    lineHeight: 1.55,
    paragraphGap: 12,
    blockGap: 12,
    headingScale: 1.9,
    minHeadingScale: 1.15,
    quoteIndent: 16,
    codePadding: 12,
    maxCodeLines: 24,
    markerWidth: 24,
  );

  static _Metrics of(MarkdownDensity density) =>
      density == MarkdownDensity.widget ? widget : editor;

  /// A copy with a different [headingScale], and the floor moved to match.
  ///
  /// The floor is not left behind on purpose: it exists so a heading is never
  /// *smaller* than the text around it, and a caller asking for 1.0 while the
  /// floor said 1.05 would get 1.05 and quietly get something other than what
  /// it asked for.
  _Metrics withHeadingScale(double scale) => _Metrics(
        body: body,
        lineHeight: lineHeight,
        paragraphGap: paragraphGap,
        blockGap: blockGap,
        headingScale: scale,
        minHeadingScale: scale < minHeadingScale ? scale : minHeadingScale,
        quoteIndent: quoteIndent,
        codePadding: codePadding,
        maxCodeLines: maxCodeLines,
        markerWidth: markerWidth,
      );

  /// The same shape at a different body size.
  ///
  /// Ratios are kept and pixel values are scaled, so the result is the same
  /// design at a different size rather than the same gaps crammed into a smaller
  /// box. `maxCodeLines` is a line *count* and deliberately does not scale.
  _Metrics scaledTo(double size) {
    if (size == body) return this;
    final k = size / body;
    return _Metrics(
      body: size,
      lineHeight: lineHeight,
      paragraphGap: paragraphGap * k,
      blockGap: blockGap * k,
      headingScale: headingScale,
      minHeadingScale: minHeadingScale,
      quoteIndent: quoteIndent * k,
      codePadding: codePadding * k,
      maxCodeLines: maxCodeLines,
      markerWidth: markerWidth * k,
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

/// Renders [source] as Markdown.
///
/// [selectable] adds selection handles, which the editor preview wants and a
/// widget card must not have: a card you can drag should not also start
/// selecting text when someone drags across it.
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
    final builder = _Builder(
      style: _Style(
        base: style,
        accent: accent,
        muted: color.withValues(alpha: 0.62),
        metrics: _Metrics.editor,
        density: MarkdownDensity.editor,
      ),
      // The builder's own maxLines is what `_text` reads when no explicit line
      // count is passed, so the caller's value is honoured here. It previously
      // was not: `buildInlineLine` always passed a hard-coded 1, which meant a
      // caller asking for two lines - the large widget card's title - silently
      // got one.
      maxLines: maxLines,
    );
    return builder.buildInlineLine(nodes);
  }

  @override
  Widget build(BuildContext context) {
    var metrics = _Metrics.of(density);
    if (headingScale != null) {
      // `_Metrics` is const-constructible precisely so a variant can be made
      // without a subclass or a mutable field; the with* methods exist for the
      // same reason on every other knob here.
      metrics = metrics.withHeadingScale(headingScale!);
    }
    if (fontSize != null && fontSize != metrics.body) {
      // A surface can have its own type scale - the editor's list rows use the
      // theme's `bodySmall`, not the widget's 13px - and a renderer that
      // ignored that would either fight the theme or quietly ignore a change to
      // it.
      metrics = metrics.scaledTo(fontSize!);
    }
    final style = _Style(
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

    final builder = _Builder(
      style: style,
      maxLines: maxLines,
      selectable: selectable,
    );
    var child = builder.buildBlocks(_ParseCache.of(source));

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

/// Everything the span builder needs that is not the node.
@immutable
class _Style {
  const _Style({
    required this.base,
    required this.accent,
    required this.muted,
    required this.metrics,
    required this.density,
  });

  final TextStyle base;
  final Color accent;
  final Color muted;
  final _Metrics metrics;
  final MarkdownDensity density;

  _Style withBase(TextStyle style) => _Style(
        base: style,
        accent: accent,
        muted: muted,
        metrics: metrics,
        density: density,
      );
}

/// Walks the AST and produces widgets.
///
/// Stateless: every method takes the style and the depth, so one instance per
/// build is enough and nothing has to be threaded through a `BuildContext`.
class _Builder {
  _Builder({required this.style, this.maxLines, this.selectable = false});

  _Style style;
  final int? maxLines;
  final bool selectable;

  // --- blocks ---------------------------------------------------------------

  Widget buildBlocks(List<md.Node> nodes, {int depth = 0}) {
    final blocks = <Widget>[];
    var previousWasLoose = false;

    for (final node in nodes) {
      final block = buildBlock(node, depth: depth);
      if (block == null) continue;
      // Consecutive loose blocks sit tighter than separated ones, which is what
      // makes a list or a quote read as one thing rather than a stack.
      final gap = previousWasLoose ? 0.0 : style.metrics.blockGap;
      if (gap > 0 && blocks.isNotEmpty) blocks.add(SizedBox(height: gap));
      blocks.add(block);
      previousWasLoose = _isLoose(node);
    }

    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  /// Whether [node] groups with the one before it.
  static bool _isLoose(md.Node node) {
    if (node is! md.Element) return false;
    const grouping = {'li', 'p', 'pre', 'blockquote'};
    return grouping.contains(node.tag);
  }

  Widget? buildBlock(md.Node node, {int depth = 0}) {
    if (node is md.Text) {
      final text = node.text.trim();
      if (text.isEmpty) return null;
      return _paragraphOf(node);
    }
    if (node is! md.Element) return null;

    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _heading(node);

      case 'p':
        return _paragraphOf(node);

      case 'hr':
        return Padding(
          padding: EdgeInsets.symmetric(vertical: style.metrics.blockGap / 2),
          child: Divider(
            height: 1,
            thickness: 1,
            color: style.muted.withValues(alpha: 0.35),
          ),
        );

      case 'pre':
        return _codeBlock(node);

      case 'blockquote':
        return _quote(node, depth: depth);

      case 'ul':
      case 'ol':
        return _list(node, depth: depth, ordered: node.tag == 'ol');

      case 'table':
        // A table in a 360px card is a grid of unreadable slivers, so the
        // structure is dropped rather than shrunk. The cells must keep a
        // separator though: `textContent` concatenates them with nothing, which
        // turns `Surface | Density | Widget | compressed` into
        // `SurfaceDensityWidgetcompressed` - and a renderer that produces less
        // than the note said is the one failure this file does not have.
        if (style.density == MarkdownDensity.widget) {
          return _tableAsText(node, style);
        }
        return _table(node);

      default:
        // Unknown block: keep the text rather than dropping the note on the floor.
        if (_isContainer(node)) return buildBlocks(_childBlocks(node), depth: depth);
        final text = node.textContent.trim();
        if (text.isEmpty) return null;
        return _paragraphOf(node);
    }
  }

  static bool _isContainer(md.Element node) =>
      (node.children?.isNotEmpty ?? false);

  Widget _heading(md.Element node) {
    final level = int.tryParse(node.tag.substring(1)) ?? 1;
    // A step down per level, with the floor from _Metrics doing the work at the
    // bottom of the range.
    final step = 1 - ((level - 1) * 0.11).clamp(0.0, 1.0);
    final size = (style.metrics.body * style.metrics.headingScale * step)
        .clamp(style.metrics.body * style.metrics.minHeadingScale, 40.0)
        .toDouble();

    return Padding(
      padding: EdgeInsets.only(top: style.metrics.paragraphGap),
      child: _inlineText(
        node,
        style.withBase(style.base.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w700,
          // Tight: a heading with loose leading reads as a paragraph in a
          // slightly larger font.
          height: 1.2,
        )),
      ),
    );
  }

  Widget? _paragraphOf(md.Node node) {
    if (_isBlank(node)) return null;
    return Padding(
      padding: EdgeInsets.only(bottom: style.metrics.paragraphGap),
      child: _inlineText(node, style),
    );
  }

  static bool _isBlank(md.Node node) => node.textContent.trim().isEmpty;

  Widget _codeBlock(md.Element node) {
    // The fence's language arrives as a class on the inner <code>, e.g.
    // `class="language-dart"`. Shown when there is room, because it is often
    // the only clue about what a snippet is.
    final language = _languageOf(node);
    final lines = node.textContent.trimRight().split('\n');
    final shown = lines.take(style.metrics.maxCodeLines).toList();
    final hidden = lines.length - shown.length;

    final code = Text.rich(
      TextSpan(
        text: shown.join('\n'),
        style: style.base.copyWith(
          fontFamily: 'Consolas',
          fontFamilyFallback: const ['monospace'],
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
        children: [
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

  static String _languageOf(md.Element node) {
    for (final child in node.children ?? const <md.Node>[]) {
      if (child is md.Element) {
        final cls = child.attributes['class'];
        if (cls != null && cls.startsWith('language-')) {
          return cls.substring('language-'.length);
        }
      }
    }
    return '';
  }

  Widget _quote(md.Element node, {required int depth}) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: style.metrics.paragraphGap / 2),
      padding: EdgeInsets.only(left: style.metrics.quoteIndent),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: style.muted.withValues(alpha: 0.45),
            width: 3,
          ),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: style.base.copyWith(
          color: style.muted,
          fontStyle: FontStyle.italic,
        ),
        child: buildBlocks(_childBlocks(node), depth: depth),
      ),
    );
  }

  Widget _list(md.Element node, {required int depth, required bool ordered}) {
    final items = (node.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .where((child) => child.tag == 'li')
        .toList();

    final rows = <Widget>[];
    var index = 1;

    for (final item in items) {
      final marker = ordered ? '$index.' : _bulletAt(depth);
      index++;
      // Checked before the marker, so a task list shows a box rather than a
      // bullet with a box in it.
      final task = _taskOf(item);

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2, top: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: style.metrics.markerWidth,
                child: Text(
                  task ?? marker,
                  style: style.base.copyWith(
                    color: task == null ? style.muted : style.accent,
                    fontWeight:
                        task == null ? FontWeight.normal : FontWeight.w700,
                    height: style.metrics.lineHeight,
                  ),
                ),
              ),
              Expanded(child: _listItemBody(item, depth: depth)),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: style.metrics.paragraphGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  /// Nested levels get a different glyph. The same bullet three levels deep
  /// reads as three siblings, which is the whole thing indentation is for.
  static String _bulletAt(int depth) {
    const glyphs = ['•', '◦', '‣'];
    return glyphs[depth % glyphs.length];
  }

  Widget _listItemBody(md.Element item, {required int depth}) {
    // The checkbox the parser produced for a task item is dropped here: the
    // glyph in the gutter already says so, and the element renders as nothing.
    //
    // Text nodes are kept as well as elements, and they come first. A task item
    // arrives as `[<input>, Text('open')]` with no paragraph element at all, so
    // a version that looked only at child elements rendered the box and dropped
    // the words next to it.
    final children = (item.children ?? const <md.Node>[])
        .where((child) => !(child is md.Element && child.tag == 'input'))
        .toList();

    final leading = <md.Node>[];
    final blocks = <md.Element>[];
    for (final child in children) {
      if (child is md.Element) {
        blocks.add(child);
      } else if (blocks.isEmpty) {
        leading.add(child);
      }
    }

    final parts = <Widget>[];
    if (leading.isNotEmpty) {
      parts.add(_inlineFrom(leading, style));
    }
    for (final block in blocks) {
      parts.add(buildBlock(block, depth: depth + 1) ?? const SizedBox.shrink());
    }

    if (parts.isEmpty) return const SizedBox.shrink();
    if (parts.length == 1) return parts.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: parts,
    );
  }

  /// `[ ]` / `[x]` as a leading `<input type="checkbox">`, or null.
  ///
  /// The parser consumes the bracket syntax and replaces it with that element;
  /// it does not leave the characters in the text. So this reads the element
  /// rather than looking for `[`. Reading the literal would work on some inputs
  /// and silently stop working on others, which is the worst of both.
  static String? _taskOf(md.Element item) {
    for (final child in item.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'input') {
        return child.attributes['checked'] == 'true' ? '☑' : '☐';
      }
    }
    return null;
  }

  Widget? _table(md.Element node) {
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
    if (rows.isEmpty) return null;

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
                        child: _inlineText(
                          cell,
                          index == 0
                              ? style.withBase(style.base.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ))
                              : style,
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

  /// A table flattened to one line per row, cells separated by `|`.
  ///
  /// Same content, no grid. The separator is the point: see the call site.
  Widget? _tableAsText(md.Element node, _Style style) {
    final lines = <String>[];

    void collect(md.Element parent) {
      for (final child in parent.children ?? const <md.Node>[]) {
        if (child is! md.Element) continue;
        if (child.tag == 'tr') {
          final cells = (child.children ?? const <md.Node>[])
              .whereType<md.Element>()
              .where((cell) => cell.tag == 'th' || cell.tag == 'td')
              .map((cell) => cell.textContent.trim())
              .where((cell) => cell.isNotEmpty)
              .toList();
          if (cells.isNotEmpty) lines.add(cells.join(' | '));
        } else {
          collect(child);
        }
      }
    }

    collect(node);
    if (lines.isEmpty) return null;

    return Padding(
      padding: EdgeInsets.only(bottom: style.metrics.paragraphGap),
      child: _inlineText(md.Element.text('p', lines.join('\n')), style),
    );
  }

  /// A quote's children. A quote holding one paragraph is that paragraph rather
  /// than a nested column with a gap in it.
  static List<md.Node> _childBlocks(md.Element node) {
    final children = node.children ?? const <md.Node>[];
    final elements = children.whereType<md.Element>().toList();
    if (elements.length == 1 && elements.first.tag == 'p') {
      return [elements.first];
    }
    return children;
  }

  // --- inline ---------------------------------------------------------------

  /// One element's inline content as a run of styled text.
  Widget _inlineText(md.Node node, _Style style) {
    final previous = this.style;
    this.style = style;
    try {
      final spans = _inlineSpans(node, style);
      if (spans.isEmpty) return const SizedBox.shrink();
      return _text(TextSpan(style: style.base, children: spans));
    } finally {
      this.style = previous;
    }
  }

  /// Several sibling nodes as one run of styled text.
  ///
  /// Needed because a list item does not always wrap its own words in a
  /// paragraph: a task item arrives as bare text nodes beside a checkbox
  /// element, and there is no single element to hand to [_inlineText].
  Widget _inlineFrom(List<md.Node> nodes, _Style style) {
    final previous = this.style;
    this.style = style;
    try {
      final spans = <InlineSpan>[];
      for (final node in nodes) {
        spans.addAll(_inlineSpans(node, style));
      }
      if (spans.isEmpty) return const SizedBox.shrink();
      return _text(TextSpan(style: style.base, children: spans));
    } finally {
      this.style = previous;
    }
  }

  /// A single line of inline formatting across [nodes], for titles.
  Widget buildInlineLine(List<md.Node> nodes) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      spans.addAll(_inlineSpans(node, style));
    }
    if (spans.isEmpty) {
      return Text('', style: style.base, maxLines: maxLines);
    }
    return _text(TextSpan(style: style.base, children: spans));
  }

  Widget _text(InlineSpan span, {int? lines}) {
    final limit = lines ?? maxLines;
    final text = Text.rich(
      span,
      maxLines: limit,
      // With no limit the clip is the point - a block taller than its box is
      // already being clipped by the caller. With one, ellipsis is the honest
      // way to say there is more.
      overflow: limit == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
    if (!selectable) return text;
    // So that a word can be copied out of the preview. Only ever on the editor
    // side: a widget card is a drag handle first, and a card that starts
    // selecting text when someone drags across it turns every drag into a
    // misfire.
    return SelectionArea(child: text);
  }

  /// Inline spans for [node], ignoring block structure entirely.
  List<InlineSpan> _inlineSpans(md.Node node, _Style style) {
    if (node is md.Text) {
      if (node.text.isEmpty) return const [];
      // The style is attached here rather than left to the enclosing span.
      // Leaving it off means the run inherits from the block, which is the
      // *body* style - so `**bold**` inside a heading rendered at body size and
      // body weight. The two cases that actually need a style are handled in the
      // switch below; this one handles every leaf.
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
        return _wrap(children, style,
            style.base.copyWith(fontWeight: FontWeight.w700));

      case 'em':
        return _wrap(children, style,
            style.base.copyWith(fontStyle: FontStyle.italic));

      case 'del':
        return _wrap(children, style,
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
        return _wrap(children, style, null);
    }
  }

  List<InlineSpan> _wrap(
    List<md.Node> children,
    _Style style,
    TextStyle? override,
  ) {
    final effective = override == null ? style : style.withBase(override);
    final spans = <InlineSpan>[];
    for (final child in children) {
      spans.addAll(_inlineSpans(child, effective));
    }
    return spans;
  }

}