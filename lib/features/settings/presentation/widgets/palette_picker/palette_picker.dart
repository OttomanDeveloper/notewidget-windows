import 'package:flutter/material.dart';

import '../../../../../core/theme/palette.dart';
import '../palette_swatch/palette_swatch.dart';

/// The colour swatches.
///
/// Nine circles and the name of the one you picked, rather than a dropdown:
/// the whole point of a colour list is that you can recognise the colour you
/// want without reading its name, and a dropdown throws that away.
///
/// Each swatch shows the palette's **light-mode** accent, because that is the
/// one with to stay legible against a pale dialog — the dark-mode variant is a
/// lighter shade of the same hue, so the swatch reads as the family rather than
/// as a colour you will not actually get.
class PalettePicker extends StatelessWidget {
  const PalettePicker(
      {super.key, required this.selected, required this.onSelected});

  final WinNotesPalette selected;
  final ValueChanged<WinNotesPalette> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 196,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              for (final palette in winNotesPalettes)
                PaletteSwatch(
                  palette: palette,
                  isSelected: palette.id == selected.id,
                  onTap: () => onSelected(palette),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selected.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
