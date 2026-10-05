import 'package:markdown/markdown.dart' as md;

/// Pure predicates over the parsed tree.
///
/// One home for the questions every block widget asks, so the dispatcher and
/// the quote do not each carry their own copy of "what counts as a container".
class MarkdownNodes {
  const MarkdownNodes._();

  /// Whether [node] groups with the one before it.
  static bool isLoose(md.Node node) {
    if (node is! md.Element) return false;
    const grouping = {'li', 'p', 'pre', 'blockquote'};
    return grouping.contains(node.tag);
  }

  static bool isContainer(md.Element node) =>
      (node.children?.isNotEmpty ?? false);

  static bool isBlank(md.Node node) => node.textContent.trim().isEmpty;

  /// A quote's children. A quote holding one paragraph is that paragraph rather
  /// than a nested column with a gap in it.
  static List<md.Node> childBlocks(md.Element node) {
    final children = node.children ?? const <md.Node>[];
    final elements = children.whereType<md.Element>().toList();
    if (elements.length == 1 && elements.first.tag == 'p') {
      return [elements.first];
    }
    return children;
  }

  /// Nested levels get a different glyph. The same bullet three levels deep
  /// reads as three siblings, which is the whole thing indentation is for.
  static String bulletAt(int depth) {
    const glyphs = ['•', '◦', '‣'];
    return glyphs[depth % glyphs.length];
  }

  /// `[ ]` / `[x]` as a leading `<input type="checkbox">`, or null.
  ///
  /// The parser consumes the bracket syntax and replaces it with that element;
  /// it does not leave the characters in the text. So this reads the element
  /// rather than looking for `[`. Reading the literal would work on some inputs
  /// and silently stop working on others, which is the worst of both.
  static String? taskOf(md.Element item) {
    for (final child in item.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'input') {
        return child.attributes['checked'] == 'true' ? '☑' : '☐';
      }
    }
    return null;
  }

  static String languageOf(md.Element node) {
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
}
