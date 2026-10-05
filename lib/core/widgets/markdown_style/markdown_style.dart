import 'package:flutter/material.dart';

import '../markdown_density/markdown_density.dart';
import '../markdown_metrics/markdown_metrics.dart';

/// Everything a block or span builder needs that is not the node.
///
/// A value, not state: base text style, palette colors and measurements. Passed
/// whole rather than as seven primitives, because every renderer reads most of
/// it and the alternative is the same long parameter list on every widget.
@immutable
class MarkdownStyle {
    required this.base,
    required this.accent,
    required this.muted,
    required this.metrics,
    required this.density,
  });

  final TextStyle base;
  final Color accent;
  final Color muted;
  final MarkdownMetrics metrics;
  final MarkdownDensity density;

  MarkdownStyle withBase(TextStyle style) => MarkdownStyle(
        base: style,
        accent: accent,
        muted: muted,
        metrics: metrics,
        density: density,
      );
}
