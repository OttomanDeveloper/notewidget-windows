import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win_notes/features/settings/domain/settings.dart';

import '../../providers/settings_controller.dart';
import '../settings_group/settings_group.dart';
import '../settings_row/settings_row.dart';
import '../settings_separator/settings_separator.dart';

class StartupSettingsGroup extends ConsumerWidget {
  const StartupSettingsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the two fields this group draws.
    final (bool, int) settings = ref.watch(
      settingsProvider.select(
        (AsyncValue<SettingsState> v) => (
          v.value?.settings.autoStart ?? true,
          v.value?.settings.autoStartDelayMs ?? 0,
        ),
      ),
    );
    final bool autoStart = settings.$1;
    final int delayMs = settings.$2;
    final SettingsNotifier controller = ref.read(settingsProvider.notifier);
    return SettingsGroup(
      title: 'Startup',
      children: <Widget>[
        SettingsRow(
          label: 'Bring the widget back after every restart',
          description: 'One entry under your own account, so no administrator '
              'rights are needed and it shows up in Task Manager.',
          trailing: Switch(
            value: autoStart,
            onChanged: (bool enabled) => controller.setAutoStart(enabled: enabled),
          ),
        ),
        const SettingsSeparator(),
        SettingsRow(
          label: 'Startup delay',
          description: delayMs == 0
              ? 'Show the widget the moment Windows gets there.'
              : 'Wait ${(delayMs / 1000).toStringAsFixed(1)} '
                  'seconds so the widget does not race the login animation. '
                  'Applies to startup only, never to a launch by hand.',
          trailing: SizedBox(
            width: 190,
            child: Slider(
              value: delayMs.toDouble(),
              min: 0,
              max: 15000,
              divisions: 30,
              label: '${(delayMs / 1000).toStringAsFixed(1)}s',
              onChanged: (double value) => controller.apply(
                (WinNotesSettings s) => s.copyWith(autoStartDelayMs: value.round()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
