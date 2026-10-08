import 'package:flutter/material.dart';

/// A divider the user can drag, for resizing the pane beside it. Its hit
/// area is wider than the line it draws: 1px is not a target, and 10px is the
/// grab band the native window already uses for its own edges.
class PaneDivider extends StatefulWidget {
  const PaneDivider({
    super.key,
    required this.onDrag,
    this.onReset,
    this.tooltip = 'Drag to resize. Double-click to reset.',
  });

  /// How far the pointer moved this drag, positive to the right. A delta,
  /// not a position: a position needs the parent's left edge, which a
  /// LayoutBuilder cannot read during uild - its box has no size yet.
  final ValueChanged<double> onDrag;

  /// Double-click, which is the one gesture that needs no instructions.
  final VoidCallback? onReset;

  final String tooltip;

  @override
  State<PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<PaneDivider> {
  /// Hover or drag: either is enough to draw the handle as grabbed.
  ///
  /// survives only to dispose this, which is the one thing it is allowed for.
  final ValueNotifier<bool> _active = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _active,
      builder: (BuildContext context, bool active, _) {
        final Color line =
            active ? theme.colorScheme.primary : theme.dividerColor;
        return Tooltip(
          message: widget.tooltip,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            onEnter: (_) => _active.value = true,
            onExit: (_) => _active.value = false,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _active.value = true,
              onHorizontalDragUpdate: (DragUpdateDetails details) =>
                  widget.onDrag(details.delta.dx),
              onHorizontalDragEnd: (_) => _active.value = false,
              onDoubleTap: widget.onReset,
              child: SizedBox(
                width: 10,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: active ? 3 : 1,
                    color: line,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
