import 'package:flutter/material.dart';

import '../../../../widget/domain/widget_design.dart';
import '../design_chip/design_chip.dart';

/// Which whole-card design the widget draws. Five, and a first chip that clears
/// the choice rather than picking the first design - the built-in card is not in
/// the list, so a chip that picked it would be offering it twice.
class DesignPicker extends StatelessWidget {
  const DesignPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final WidgetDesign? selected;
  final ValueChanged<WidgetDesign?> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // `SettingsRow` puts its trailing widget in a Row with an `Expanded` label,
    // so the trailing gets its intrinsic width and six chips overflow by 27px.
    // A bounded width lets the `Wrap` break onto more lines instead.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          DesignChip(
            label: 'None',
            chosen: selected == null,
            onTap: () => onSelected(null),
            color: theme.colorScheme.onSurfaceVariant,
          ),
          for (final WidgetDesign design in widgetDesigns)
            DesignChip(
              label: design.label,
              chosen: selected?.id == design.id,
              onTap: () => onSelected(design),
              color: theme.colorScheme.onSurface,
            ),
        ],
      ),
    );
  }
}
