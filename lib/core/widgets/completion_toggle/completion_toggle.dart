import 'package:flutter/material.dart';

import '../completion_painter/completion_painter.dart';

/// The tick that marks a note finished.
/// Shared by both surfaces so "done" reads as one idea; a circle (drawn
/// check, not an icon) because a note is finished, and it must read small.
class CompletionToggle extends StatelessWidget {
  const CompletionToggle({
    super.key,
    required this.completed,
    required this.onToggle,
    this.diameter = 20,
    this.hitTarget,
    this.color,
    this.filled = false,
  });

  final bool completed;
  final VoidCallback onToggle;

  /// How big the drawn circle is.
  final double diameter;

  /// How big the thing you actually aim at is, defaults to [diameter].
  /// 20px is not a comfortable target, and the card has only its own height.
  final double? hitTarget;

  /// The ring and the check take this. Falls back to the ambient outline colour.
  final Color? color;

  /// Whether the control gets a filled background. The editor wants it behind a
  /// text field; the widget does not, where it would add a second box to a card
  /// that is already mostly text.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.colorScheme.brightness == Brightness.dark;
    final outline = color ?? theme.colorScheme.outline;
    final mark = completed ? (color ?? theme.colorScheme.primary) : outline;
    final target = hitTarget ?? diameter;

    return Semantics(
      button: true,
      checked: completed,
      label: completed ? 'Mark as not done' : 'Mark as done',
      child: Tooltip(
        message: completed ? 'Mark as not done' : 'Mark as done',
        child: SizedBox(
          width: target,
          height: target,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggle,
              customBorder: const CircleBorder(),
              child: Center(
                child: Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: completed
                        ? mark.withValues(alpha: 0.14)
                        : filled
                            ? theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.45)
                            : Colors.transparent,
                    border: Border.all(
                      color: completed ? mark : outline.withValues(alpha: dark ? 0.55 : 0.4),
                      width: completed ? 2 : 1.5,
                    ),
                  ),
                  child: RepaintBoundary(
                    child: CustomPaint(
                        painter: CompletionPainter(color: mark, visible: completed)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line through finished text.
/// One place for both surfaces' lists and fields, so no copy drifts; the
/// colour follows the text rather than smudging over muted text.
TextStyle? markCompleted(TextStyle? style, {required bool completed}) {
  if (!completed || style == null) return style;
  return style.copyWith(
    decoration: TextDecoration.lineThrough,
    decorationColor: style.color?.withValues(alpha: 0.75),
    decorationThickness: 1.5,
  );
}
