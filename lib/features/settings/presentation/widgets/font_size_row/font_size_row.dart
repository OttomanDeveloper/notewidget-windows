import 'package:flutter/material.dart';

import '../../../domain/settings.dart';
import '../settings_row/settings_row.dart';

/// A type-size row: a slider, the size it resolves to, and a way back to
/// "as designed". The slider sits at the size being rendered, not the stored
/// number - see widget_pattern.md §3.21.
class FontSizeRow extends StatelessWidget {
  const FontSizeRow({
    super.key,
    required this.label,
    required this.description,
    required this.chosen,
    required this.resolved,
    required this.onChanged,
    required this.onReset,
  });

  final String label;
  final String description;

  /// The stored size, or 0 for "as designed".
  final int chosen;

  /// The size being rendered now, in logical pixels.
  final int resolved;

  final ValueChanged<int> onChanged;

  /// Writes 0 back, which is the only way to return to "as designed".
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDefault = chosen == 0;
    return SettingsRow(
      label: label,
      description: description,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Slider(
              value: resolved
                  .toDouble()
                  .clamp(
                    WinNotesSettings.minFontSize.toDouble(),
                    WinNotesSettings.maxFontSize.toDouble(),
                  )
                  .toDouble(),
              min: WinNotesSettings.minFontSize.toDouble(),
              max: WinNotesSettings.maxFontSize.toDouble(),
              divisions: WinNotesSettings.maxFontSize - WinNotesSettings.minFontSize,
              label: '$resolved px',
              onChanged: (double value) => onChanged(value.round()),
            ),
          ),
          SizedBox(
            width: 82,
            child: Text(
              isDefault ? '$resolved px · auto' : '$resolved px',
              style: theme.textTheme.bodySmall,
            ),
          ),
          // Only offered once something has been chosen: there is nothing to
          // undo before the first change, and a dead button invites a click.
          if (isDefault)
            const SizedBox(width: 82)
          else
            SizedBox(
              width: 82,
              child: TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                child: const Text('Reset'),
              ),
            ),
        ],
      ),
    );
  }
}