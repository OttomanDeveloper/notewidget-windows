import 'package:flutter/material.dart';

import '../../../../../core/theme/palette.dart';
import '../palette_swatch/palette_swatch.dart';

/// Colour swatches, not a dropdown: recognition beats reading names. Light-mode
/// accents (legible on pale dialogs); the dark variant is the same hue, lighter.
class PalettePicker extends StatelessWidget {
  const PalettePicker(
      {super.key, required this.selected, required this.onSelected});

  final WinNotesPalette selected;
  final ValueChanged<WinNotesPalette> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: 196,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: <Widget>[
              for (final WinNotesPalette palette in winNotesPalettes)
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
