import 'package:flutter/material.dart';

import '../markdown_density/markdown_density.dart';

/// Type sizes and spacing for one density.
///
/// Every number lives here rather than inline, because the whole difference
/// between the two surfaces is these values and they should be comparable.
@immutable
class MarkdownMetrics {
  const MarkdownMetrics({
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

  static const widget = MarkdownMetrics(
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

  static const editor = MarkdownMetrics(
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

  static MarkdownMetrics of(MarkdownDensity density) =>
      density == MarkdownDensity.widget ? widget : editor;

  /// A copy with a different [headingScale], and the floor moved to match.
  ///
  /// The floor is not left behind on purpose: it exists so a heading is never
  /// *smaller* than the text around it, and a caller asking for 1.0 while the
  /// floor said 1.05 would get 1.05 and quietly get something other than what
  /// it asked for.
  MarkdownMetrics withHeadingScale(double scale) => MarkdownMetrics(
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
  MarkdownMetrics scaledTo(double size) {
    if (size == body) return this;
    final k = size / body;
    return MarkdownMetrics(
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
