import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// A minimal scroll rail that appears while scrolling and fades out after.
///
/// Hand-rolled rather than [Scrollbar] because the built-in one either paints a
/// permanent track that narrows the cards or needs hover to show at all, and
/// this widget is too small for either.
class FloatingScrollRail extends StatelessWidget {
  const FloatingScrollRail({
    super.key,
    required this.scroll,
    required this.opacity,
  });

  final ScrollController scroll;
  final ValueListenable<double> opacity;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<double>(
      valueListenable: opacity,
      builder: (context, value, _) {
        if (value <= 0.01) return const SizedBox.shrink();
        return AnimatedOpacity(
          opacity: value,
          duration: const Duration(milliseconds: 220),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 3),
              child: SizedBox(
                width: 4,
                child: ListenableBuilder(
                  listenable: scroll,
                  builder: (context, _) {
                    if (!scroll.hasClients) return const SizedBox.shrink();
                    final position = scroll.position;
                    final total = position.maxScrollExtent + position.viewportDimension;
                    if (total <= 0) return const SizedBox.shrink();
                    final fraction = position.viewportDimension / total;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: FractionallySizedBox(
                        heightFactor: fraction.clamp(0.08, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.45)
                                : Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
