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

  static bool isBlank(md.Node node) => node.textContent.trim().isEmpty;

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
