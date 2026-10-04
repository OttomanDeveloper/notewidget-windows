import 'package:flutter/material.dart';

/// The tick that marks a note finished.
///
/// Shared by both surfaces on purpose. The widget and the editor are the same app
/// showing the same notes on the same screen at the same time, and a control
/// that looked different in each would read as two different ideas about what
/// "done" means - or, worse, as a feature that only exists in one of them.
///
/// The shape is a circle rather than a square checkbox because a note is a task
/// you finish, not a line you tick off in a form, and because the ring reads at
/// the small size the widget has to draw it at. The check is drawn rather than
/// taken from the icon font so it can sit on the accent colour without fighting
/// it, and so it scales with the ring instead of drifting off-centre.
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
  ///
  /// Twenty pixels is not a comfortable target, and on the widget there is only
  /// the card's own height to spend.
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
                  child: CustomPaint(painter: _CheckPainter(color: mark, visible: completed)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.color, required this.visible});

  final Color color;
  final bool visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // Proportional to the box, so the tick keeps its weight when the widget
      // is resized rather than turning into a hairline or a blob.
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Two segments, in fractions of the box, so the tick stays centred in the
    // ring at every size the widget can be resized to.
    final path = Path()
      ..moveTo(size.width * 0.26, size.height * 0.52)
      ..lineTo(size.width * 0.43, size.height * 0.69)
      ..lineTo(size.width * 0.75, size.height * 0.33);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.color != color || old.visible != visible;
}

/// The line through finished text.
///
/// One place, because it is applied to the widget's cards, the editor's list and
/// the editor's two text fields, and three hand-written copies of a strikethrough
/// is three chances for one of them to end up a shade off or drawn in a different
/// colour from the text it is crossing.
///
/// The colour follows the text. A default strikethrough is drawn in the ambient
/// text colour at full strength, which over already-muted text reads as a smudge
/// rather than a line through something.
TextStyle? markCompleted(TextStyle? style, {required bool completed}) {
  if (!completed || style == null) return style;
  return style.copyWith(
    decoration: TextDecoration.lineThrough,
    decorationColor: style.color?.withValues(alpha: 0.75),
    decorationThickness: 1.5,
  );
}
