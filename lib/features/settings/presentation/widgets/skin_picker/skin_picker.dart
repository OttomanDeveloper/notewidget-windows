import 'package:flutter/material.dart';

import '../../../../../core/theme/skin.dart';
import '../none_swatch/none_swatch.dart';
import '../skin_swatch/skin_swatch.dart';

/// Skin chips, and a way back to having none. The first is **None** - not a skin
/// but the absence of one, and what every existing install is on. Offered rather
/// than implied: a user who tries one must be able to undo it as visibly.
class SkinPicker extends StatelessWidget {
  const SkinPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.accent,
  });

  /// Null means no skin, which is not the same as the first skin in the list.
  final WinNotesSkin? selected;
  final ValueChanged<WinNotesSkin?> onSelected;

  /// The palette's accent, used only to draw the chips' focus markers. It is not
  /// the skin's to choose - that is the whole division of labour.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: 208,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: <Widget>[
              NoneSwatch(
                isSelected: selected == null,
                onTap: () => onSelected(null),
              ),
              for (final WinNotesSkin skin in winNotesSkins)
                SkinSwatch(
                  skin: skin,
                  accent: accent,
                  isSelected: selected?.id == skin.id,
                  onTap: () => onSelected(skin),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selected?.label ?? 'Default',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
