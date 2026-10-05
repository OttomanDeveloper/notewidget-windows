import 'package:flutter/material.dart';

import '../../../../../core/theme/palette.dart';
import '../../../../../core/theme/theme.dart';

class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch({
    super.key,
    required this.palette,
    required this.isSelected,
    required this.onTap,
  });

  /// Exposed so widget tests aim at a swatch without reverse-engineering the
  /// wrap order — the same reason the composer's controls are keyed.
  static Key keyFor(String paletteId) => ValueKey('settings.palette.$paletteId');

  final WinNotesPalette palette;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A tick rather than a ring: a ring in the same colour as the swatch reads
    // as a slightly bigger swatch, which is not obviously "this one".
    final onAccent = readableOn(palette.accent);

    return Semantics(
      button: true,
      selected: isSelected,
      label: palette.label,
      // On the Semantics rather than the InkWell nested inside it, so a test can
      // ask "which swatch claims to be selected" by key. A key on the innermost
      // widget would make the selected state unobservable, because the
      // Semantics that carries it sits above.
      key: PaletteSwatch.keyFor(palette.id),
      child: Tooltip(
        message: palette.label,
        child: SizedBox(
          // Outside the Material, deliberately: a Material with a clip shape
          // expands to fill its constraints, which would make every swatch the
          // width of the picker and swallow taps meant for its neighbours.
          width: 30,
          height: 30,
          child: Material(
            color: Colors.transparent,
            shape: CircleBorder(
              side: BorderSide(
                color: isSelected ? palette.accent : scheme.outlineVariant,
                width: isSelected ? 2.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Center(
                child: AnimatedContainer(
                  // A plain duration rather than WinNotesMotion: that class is
                  // fed by the launch's animation flag, which this dialog is not
                  // plumbed to, and plumbing it for a 14px circle is not worth
                  // the seam.
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  width: isSelected ? 16 : 14,
                  height: isSelected ? 16 : 14,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                  ),
                  child: isSelected
                      ? Icon(Icons.check, size: 11, color: onAccent)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
