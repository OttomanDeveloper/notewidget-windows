import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win_notes/features/settings/domain/settings.dart';

import '../../providers/settings_controller.dart';
import '../settings_group/settings_group.dart';
import '../settings_row/settings_row.dart';
import '../settings_separator/settings_separator.dart';

/// How the widget sits on the desktop: position, not looks. Lock and
/// always-on-top together make the trade-off obvious: immovable is worth
/// more when not covering work.
class WidgetSettingsGroup extends ConsumerWidget {
  const WidgetSettingsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the two switches this group draws.
    final (bool, bool) settings = ref.watch(
      settingsProvider.select(
        (AsyncValue<SettingsState> v) => (
          v.value?.settings.alwaysOnTop ?? true,
          v.value?.settings.widgetPositionLocked ?? false,
        ),
      ),
    );
    final bool alwaysOnTop = settings.$1;
    final bool positionLocked = settings.$2;
    final SettingsNotifier controller = ref.read(settingsProvider.notifier);
    return SettingsGroup(
      title: 'Widget',
      children: <Widget>[
        SettingsRow(
          label: 'Keep the widget above other windows',
          description: 'A note that cannot be seen is not a note.',
          trailing: Switch(
            value: alwaysOnTop,
            onChanged: (bool value) =>
                controller.apply((WinNotesSettings s) => s.copyWith(alwaysOnTop: value)),
          ),
        ),
        const SettingsSeparator(),
        SettingsRow(
          label: 'Lock the widget in place',
          description: positionLocked
              ? 'Dragging the widget does nothing, so it cannot be knocked out '
                  'of position by accident. Turn this off to move it, then '
                  'lock it again once it is where you want it. Resizing from a '
                  'corner still works either way.'
              : 'The widget can be dragged anywhere, and stays where you drop '
                  'it. Turn this on to stop an accidental drag moving it.',
          trailing: Switch(
            value: positionLocked,
            onChanged: (bool value) => controller.apply(
              (WinNotesSettings s) => s.copyWith(widgetPositionLocked: value),
            ),
          ),
        ),
      ],
    );
  }
}
