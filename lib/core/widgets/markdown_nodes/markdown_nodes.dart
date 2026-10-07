import 'package:markdown/markdown.dart' as md;

/// Pure predicates over the parsed tree.
/// One home for them, so dispatcher and quote do not each copy "container".
class MarkdownNodes {
  const MarkdownNodes._();

  /// Whether [node] groups with the one before it.
  static bool isLoose(md.Node node) {
    if (node is! md.Element) return false;
    const Set<String> grouping = <String>{'li', 'p', 'pre', 'blockquote'};
    return grouping.contains(node.tag);
  }

  static bool isContainer(md.Element node) =>
      (node.children?.isNotEmpty ?? false);

  /// Whether [node] would draw nothing at all. `alt` on an `<img>` is an
  /// attribute rather than a text child, so a paragraph holding only an image
  /// has empty `textContent` and is not blank. widget_pattern.md §3.15.
  static bool isBlank(md.Node node) {
    if (hasImage(node)) return false;
    return visibleText(node).trim().isEmpty;
  }

  /// The text a node actually draws. Same comment rule as `MarkdownSpans`:
  /// `<!-- note -->` is markup for the reader and nothing for the author, so a
  /// paragraph holding only a comment is blank rather than a gap on screen.
  static String visibleText(md.Node node) =>
      node.textContent.replaceAll(_comment, '');

  static final RegExp _comment = RegExp(r'<!--[\s\S]*?-->');

  /// Whether [node] holds an `<img>` anywhere inside it. Recurses, because in a
  /// table cell or a list item the image is deeper than a `<p>` wrapper.
  static bool hasImage(md.Node node) {
    if (node is md.Element) {
      if (node.tag == 'img') return true;
      for (final md.Node child in node.children ?? const <md.Node>[]) {
        if (hasImage(child)) return true;
      }
    }
    return false;
  }

  /// A quote's children. A quote holding one paragraph is that paragraph rather
  /// than a nested column with a gap in it.
  static List<md.Node> childBlocks(md.Element node) {
    final List<md.Node> children = node.children ?? const <md.Node>[];
    final List<md.Element> elements = children.whereType<md.Element>().toList();
    if (elements.length == 1 && elements.first.tag == 'p') {
      return <md.Node>[elements.first];
    }
    return children;
  }

  /// Nested levels get a different glyph. The same bullet three levels deep
  /// reads as three siblings, which is the whole thing indentation is for.
  static String bulletAt(int depth) {
    const List<String> glyphs = <String>['•', '◦', '‣'];
    return glyphs[depth % glyphs.length];
  }

  /// `[ ]` / `[x]` as a leading `<input type="checkbox">`, or null.
  /// Read the element, not the literal `[`: the parser consumes the brackets.
  static String? taskOf(md.Element item) {
    for (final md.Node child in item.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'input') {
        return child.attributes['checked'] == 'true' ? '☑' : '☐';
      }
    }
    return null;
  }

  static String languageOf(md.Element node) {
    for (final md.Node child in node.children ?? const <md.Node>[]) {
      if (child is md.Element) {
        final String? cls = child.attributes['class'];
        if (cls != null && cls.startsWith('language-')) {
          return cls.substring('language-'.length);
        }
      }
    }
    return '';
  }
}
