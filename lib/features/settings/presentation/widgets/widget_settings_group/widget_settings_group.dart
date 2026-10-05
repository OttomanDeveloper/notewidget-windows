import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_controller.dart';
import '../settings_group/settings_group.dart';
import '../settings_row/settings_row.dart';
import '../settings_separator/settings_separator.dart';

/// Everything about how the widget sits on the desktop.
///
/// Grouped separately from Appearance because these are the three decisions
/// about where it goes and whether it gets in the way, rather than how it
/// looks. A lock and an always-on-top switch sitting together also make the
/// trade-off obvious: a widget you cannot move is worth more if it is also not
/// covering your work.
class WidgetSettingsGroup extends ConsumerWidget {
  const WidgetSettingsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the two switches this group draws.
    final settings = ref.watch(
      settingsProvider.select(
        (v) => (
          v.value?.settings.alwaysOnTop ?? true,
          v.value?.settings.widgetPositionLocked ?? false,
        ),
      ),
    );
    final alwaysOnTop = settings.$1;
    final positionLocked = settings.$2;
    final controller = ref.read(settingsProvider.notifier);
    return SettingsGroup(
      title: 'Widget',
      children: [
        SettingsRow(
          label: 'Keep the widget above other windows',
          description: 'A note that cannot be seen is not a note.',
          trailing: Switch(
            value: alwaysOnTop,
            onChanged: (value) =>
                controller.apply((s) => s.copyWith(alwaysOnTop: value)),
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
            onChanged: (value) => controller.apply(
              (s) => s.copyWith(widgetPositionLocked: value),
            ),
          ),
        ),
      ],
    );
  }
}
