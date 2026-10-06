import '../../../../core/widgets/markdown_metrics/markdown_metrics.dart';

/// The type sizes the editor uses before anyone has chosen one, and the rule for
/// reading a stored size. Two panes answering to one number is one too few, so
/// the source and the rendered preview are sized separately.
abstract final class TextSizes {
  /// The source in a Markdown note is monospace, and monospace at body size is a
  /// wall of text; this is what it has always been.
  static const double sourceInMarkdown = 13.5;

  /// Used only when the theme gives no `bodyLarge` size, so this is a floor and
  /// not a claim about what the theme is.
  static const double sourceFallback = 14;

  /// The size to render the source at. [chosen] is 0 for "nobody has chosen",
  /// which is what a settings file predating the setting looks like.
  static double source({
    required int chosen,
    required bool markdown,
    required double? plainSize,
  }) {
    if (chosen > 0) return chosen.toDouble();
    if (markdown) return sourceInMarkdown;
    return plainSize ?? sourceFallback;
  }

  /// The size to render the preview at. The default is read from the renderer
  /// rather than copied, so the two cannot drift apart.
  static double preview(int chosen) =>
      chosen > 0 ? chosen.toDouble() : MarkdownMetrics.editor.body;
}