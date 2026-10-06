import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/appearance_settings_group/appearance_settings_group.dart';
import '../../widgets/hotkey_settings_group/hotkey_settings_group.dart';
import '../../widgets/settings_dialog_header/settings_dialog_header.dart';
import '../../widgets/startup_settings_group/startup_settings_group.dart';
import '../../widgets/storage_settings_group/storage_settings_group.dart';
import '../../widgets/widget_settings_group/widget_settings_group.dart';

/// Settings in five flat groups, each a `Card`: a setting hidden behind a click
/// is a setting nobody changes.
class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({
    super.key,
    required this.defaultDataDirectory,
  });

  /// Values, not state: nothing here rebuilds, so plain parameters are fine.
  /// State would arrive via `ref` (`AGENTS.md` §0.8).
  final String defaultDataDirectory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The dialog itself does not read the settings; each group watches what it
    // draws, so toggling the theme repaints the appearance group and not the
    // storage group's folder path.
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SettingsDialogHeader(),
            Divider(height: 1, color: theme.dividerColor),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  const AppearanceSettingsGroup(),
                  const SizedBox(height: 20),
                  const WidgetSettingsGroup(),
                  const SizedBox(height: 20),
                  const StartupSettingsGroup(),
                  const SizedBox(height: 20),
                  const HotkeySettingsGroup(),
                  const SizedBox(height: 20),
                  StorageSettingsGroup(defaultDirectory: defaultDataDirectory),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
