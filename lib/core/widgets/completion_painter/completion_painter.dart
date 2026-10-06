import 'package:flutter/material.dart';

/// The tick inside the completion circle.
///
/// One painter per file, with `shouldRepaint` answering only on real change.
class CompletionPainter extends CustomPainter {
  const CompletionPainter({required this.color, required this.visible});

  final Color color;
  final bool visible;

  /// Hoisted out of `paint()` so a repaint allocates nothing.
  /// Reused-and-updated `Paint`/`Path` sized in fractions of the box, per
  /// `flutter_architecture_pattern.md` §8 (never allocate in `paint()`).
  static final Paint _paint = Paint()..style = PaintingStyle.stroke;
  static final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;

    _paint
      ..color = color
      // Proportional to the box, so the tick keeps its weight when the widget
      // is resized rather than turning into a hairline or a blob.
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Two segments, in fractions of the box, so the tick stays centred in the
    // ring at every size the widget can be resized to. `reset` rather than a fresh
    // Path, for the reason above.
    _path
      ..reset()
      ..moveTo(size.width * 0.26, size.height * 0.52)
      ..lineTo(size.width * 0.43, size.height * 0.69)
      ..lineTo(size.width * 0.75, size.height * 0.33);
    canvas.drawPath(_path, _paint);
  }

  @override
  bool shouldRepaint(CompletionPainter old) =>
      old.color != color || old.visible != visible;
}
