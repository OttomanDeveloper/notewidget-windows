import 'package:flutter/material.dart';

import '../../../domain/widget_design.dart';

/// The design's edge: ruled lines, punched perforations, a dot field, a torn
/// bottom, or nothing. Its own file because one widget is one file, and this
/// is the only place a `Paint` or `Path` is built rather than in `paint()`.
class DesignEdgePainter extends CustomPainter {
  DesignEdgePainter(this.edge, this.ink)
      : _faint = Paint()..color = ink.withValues(alpha: 0.16),
        _strong = Paint()
          ..color = ink.withValues(alpha: 0.32)
          ..strokeWidth = 1,
        _tear = Path();

  final DesignEdge edge;
  final Color ink;
  final Paint _faint;
  final Paint _strong;
  final Path _tear;

  @override
  void paint(Canvas canvas, Size size) {
    switch (edge) {
      case DesignEdge.plain:
        return;
      case DesignEdge.ruled:
        for (double y = 16; y < size.height; y += 19) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), _faint);
        }
      case DesignEdge.perforated:
        final double y = size.height - 9;
        for (double x = 10; x < size.width - 6; x += 14) {
          canvas.drawCircle(Offset(x, y), 2.4, _faint);
        }
        canvas.drawLine(Offset(6, y), Offset(size.width - 6, y), _strong);
      case DesignEdge.dotted:
        for (double y = 10; y < size.height; y += 12) {
          for (double x = 10; x < size.width; x += 12) {
            canvas.drawCircle(Offset(x, y), 0.9, _faint);
          }
        }
      case DesignEdge.torn:
        _tear
          ..moveTo(0, size.height)
          ..lineTo(0, size.height - 7);
        for (double x = 0; x < size.width; x += 9) {
          // Alternating teeth, so the bottom reads as torn rather than wavy.
          final double dip = (x ~/ 9).isEven ? 2.0 : 11.0;
          _tear.lineTo(x + 4.5, size.height - dip);
        }
        _tear
          ..lineTo(size.width, size.height)
          ..close();
        canvas.drawPath(_tear, _faint);
    }
  }

  @override
  bool shouldRepaint(DesignEdgePainter old) => old.edge != edge || old.ink != ink;
}
