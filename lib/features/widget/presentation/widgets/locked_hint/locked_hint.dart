import 'package:flutter/material.dart';

/// Says why a drag did nothing.
///
/// Only ever visible after someone has dragged a locked widget, which is the
/// only moment the answer is wanted. Naming the place to change it matters as
/// much as saying it is locked: "locked" alone leaves the next question
/// unanswered.
class LockedHint extends StatelessWidget {
  const LockedHint({super.key, required this.visible, required this.dark});

  final bool visible;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    // Not an AnimatedOpacity at zero. An invisible widget is still in the tree,
    // which means a screen reader would read "Locked in place" out loud on a
    // widget that is perfectly draggable, and it keeps a string of hidden text
    // in every widget surface for no reason.
    if (!visible) return const SizedBox.shrink();

    final foreground = dark ? const Color(0xFFEDEBF5) : const Color(0xFF23202E);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          // Opaque, not translucent: this is the one thing on the widget that
          // has to stay readable over an arbitrary wallpaper.
          color: dark ? const Color(0xFF2E2748) : const Color(0xFFFBFAF6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.10),
          ),
        ),
        child: Text(
          'Locked in place · turn it off in Settings',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foreground.withValues(alpha: 0.92),
            fontSize: 11.5,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
