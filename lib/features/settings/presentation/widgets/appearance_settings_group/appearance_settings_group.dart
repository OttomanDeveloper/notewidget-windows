import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/settings_repository.dart';
import '../../../../../core/theme/palette.dart';
import '../../providers/settings_controller.dart';
import '../../providers/settings_providers.dart';
import '../palette_picker/palette_picker.dart';
import '../settings_group/settings_group.dart';
import '../settings_row/settings_row.dart';
import '../settings_separator/settings_separator.dart';

class AppearanceSettingsGroup extends ConsumerWidget {
  const AppearanceSettingsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
          settingsProvider.select((v) => v.value?.settings),
        ) ??
        SettingsRepository.defaults;
    final controller = ref.read(settingsProvider.notifier);
    final acrylicSupported = ref.watch(acrylicSupportedProvider);
    return SettingsGroup(
      title: 'Appearance',
      children: [
        SettingsRow(
          label: 'Theme',
          description: 'Follows Windows unless you say otherwise.',
          trailing: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (value) =>
                controller.apply((s) => s.copyWith(themeMode: value.first)),
          ),
        ),
        const SettingsSeparator(),
        SettingsRow(
          label: 'Colour',
          description: 'The accent, and the surfaces built around it.',
          trailing: PalettePicker(
            selected: paletteById(settings.accentPalette),
            onSelected: (palette) => controller.apply(
              (s) => s.copyWith(accentPalette: palette.id),
            ),
          ),
        ),
        const SettingsSeparator(),
        SettingsRow(
          label: 'Widget opacity',
          description: '${settings.widgetOpacity}%'
              '${settings.widgetOpacity < 100 ? '  Lower values let the desktop show through.' : ''}',
          trailing: SizedBox(
            width: 190,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: settings.widgetOpacity.toDouble(),
                    min: 30,
                    max: 100,
                    divisions: 14,
                    label: '${settings.widgetOpacity}%',
                    onChanged: (value) => controller.apply(
                      (s) => s.copyWith(widgetOpacity: value.round()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SettingsSeparator(),
        SettingsRow(
          label: 'Acrylic backdrop',
          description: acrylicSupported
              ? 'The widget picks up the wallpaper the way Windows surfaces do.'
              : 'This build of Windows cannot provide it, so the widget uses a '
                  'plain translucent surface instead.',
          trailing: Switch(
            value: settings.acrylicEnabled && acrylicSupported,
            onChanged: !acrylicSupported
                ? null
                : (value) => controller.apply(
                      (s) => s.copyWith(acrylicEnabled: value),
                    ),
          ),
        ),
      ],
    );
  }
}
