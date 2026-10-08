import 'package:flutter/material.dart';

import '../../../../../core/theme/skin.dart';
import '../skin_preview_row/skin_preview_row.dart';

/// A skin chip drawn as **shape**, not colour. The first version showed the
/// skin's plate, making Skin a second Colour control - the mistake this
/// corrected. A chip previews the four things a skin actually changes.
class SkinSwatch extends StatelessWidget {
  const SkinSwatch({
    super.key,
    required this.skin,
    required this.isSelected,
    required this.onTap,
    required this.accent,
  });

  final WinNotesSkin skin;
  final bool isSelected;
  final VoidCallback onTap;

  /// Borrowed from the palette, for the marker only. It is not the skin's to
  /// choose, which is the point.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SkinLook look = lookFrom(skin);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${skin.label} skin',
      child: Tooltip(
        message: skin.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 52,
            height: 38,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                SkinPreviewRow(look: look, marked: true, accent: accent),
                if (look.separator == SkinSeparator.hairline)
                  Divider(height: 1, thickness: 1, color: theme.dividerColor),
                if (look.separator == SkinSeparator.gap)
                  SizedBox(height: look.pad(2)),
                SkinPreviewRow(look: look, marked: false, accent: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
