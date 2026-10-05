import 'package:flutter/material.dart';

import '../../../../../core/theme/theme.dart';

/// The app's mark, drawn from the same geometry as the icon file.
class BrandGlyph extends StatelessWidget {
  const BrandGlyph({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [WinNotesColors.indigoDeep, Color(0xFF332A6B), WinNotesColors.indigo],
          ),
        ),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.56,
            heightFactor: 0.56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WinNotesColors.parchment,
                borderRadius: BorderRadius.circular(size * 0.14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
