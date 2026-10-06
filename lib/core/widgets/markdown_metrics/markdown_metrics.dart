import 'package:flutter/material.dart';

import '../markdown_density/markdown_density.dart';

/// Type sizes and spacing for one density.
/// Every number lives here so the two surfaces stay comparable.
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
  /// Floors `h6` at body size: a smaller heading inverts what it is for.
  final double minHeadingScale;

  final double quoteIndent;
  final double codePadding;

  /// Code blocks clamp to this many lines: a long snippet has no meaning in
  /// a card, and truncating says so where scrolling does not fit.
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
  /// Asking for 1.0 must give 1.0, not silently clamp to the old floor.
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
  /// Ratios kept, pixel values scaled; `maxCodeLines` is a count, unscaled.
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
