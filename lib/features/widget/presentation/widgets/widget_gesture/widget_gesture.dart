import 'package:flutter/material.dart';

import '../../../../../core/platform/shell_channel.dart';

/// Which edge or corner a resize gesture grabbed, in surface terms.
enum GestureEdge {
  none,
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight
}

ResizeEdge toResizeEdge(GestureEdge edge) => switch (edge) {
      GestureEdge.left => ResizeEdge.left,
      GestureEdge.right => ResizeEdge.right,
      GestureEdge.top => ResizeEdge.top,
      GestureEdge.bottom => ResizeEdge.bottom,
      GestureEdge.topLeft => ResizeEdge.topLeft,
      GestureEdge.topRight => ResizeEdge.topRight,
      GestureEdge.bottomLeft => ResizeEdge.bottomLeft,
      GestureEdge.bottomRight => ResizeEdge.bottomRight,
      GestureEdge.none => ResizeEdge.right,
    };

enum GestureKind { moveCandidate, resize, handedOff }

class WidgetGesture {
  WidgetGesture({
    required this.kind,
    required this.anchor,
    required this.bounds,
    this.edge = GestureEdge.none,
  });

  final GestureKind kind;
  final Offset anchor;
  final NativeBounds? bounds;
  final GestureEdge edge;

  WidgetGesture handedOff() => WidgetGesture(
        kind: GestureKind.handedOff,
        anchor: anchor,
        bounds: bounds,
        edge: edge,
      );
}

/// How far the pointer must travel before a press becomes a drag.
///
/// Small enough that a drag feels immediate, large enough that pressing on a
/// card and moving slightly - or a shaky click - still selects the card.
const double widgetDragThreshold = 8;
