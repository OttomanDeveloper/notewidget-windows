import 'package:flutter/material.dart';

/// Says why a drag did nothing. Shown only after a locked-widget drag: the only
/// moment the answer is wanted, with where to change it named too.
class LockedHint extends StatelessWidget {
  const LockedHint({super.key, required this.visible, required this.dark});

  final bool visible;
  final bool dark;

  @override
  Widget build(BuildContext context) {
      // No AnimatedOpacity-at-zero: a hidden widget is still in the tree, and a
      // screen reader would announce it on a draggable widget.
    if (!visible) return const SizedBox.shrink();

    final Color foreground = dark ? const Color(0xFFEDEBF5) : const Color(0xFF23202E);
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
