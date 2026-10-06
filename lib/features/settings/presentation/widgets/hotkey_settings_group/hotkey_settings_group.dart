import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win_notes/features/settings/domain/settings.dart';

import '../../../domain/hotkey_binding.dart';
import '../../../data/settings_repository.dart';
import '../../providers/settings_controller.dart';
import '../hotkey_capture_dialog/hotkey_capture_dialog.dart';
import '../settings_group/settings_group.dart';
import '../settings_row/settings_row.dart';
import '../settings_separator/settings_separator.dart';

class HotkeySettingsGroup extends ConsumerWidget {
  const HotkeySettingsGroup({super.key});

    /// Opens the capture dialog and stores the pressed combination. Reads through
    /// `ref`: this runs outside `build`, where a settings field cannot reach.
  Future<void> _capture(BuildContext context, WidgetRef ref) async {
    final WinNotesSettings settings =
        ref.read(settingsProvider).value?.settings ?? SettingsRepository.defaults;
    final HotkeyBinding binding = settings.editorHotkey;
    final HotkeyBinding? captured = await showDialog<HotkeyBinding>(
      context: context,
      builder: (BuildContext context) => HotkeyCaptureDialog(initial: binding),
    );
    if (captured == null) return;
    await ref
        .read(settingsProvider.notifier)
        .apply((WinNotesSettings s) => s.copyWith(editorHotkey: captured));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the binding and the problem this group draws.
    final HotkeyBinding binding = ref.watch(
          settingsProvider.select(
            (AsyncValue<SettingsState> v) => v.value?.settings.editorHotkey ?? HotkeyBinding.defaultBinding,
          ),
        );
    final SettingsNotifier controller = ref.read(settingsProvider.notifier);
    final ThemeData theme = Theme.of(context);
    final String? problem = ref.watch(
      settingsProvider.select((AsyncValue<SettingsState> v) => v.value?.hotkeyProblem),
    );

    return SettingsGroup(
      title: 'Hotkey',
      children: <Widget>[
        SettingsRow(
          label: 'Open the editor from anywhere',
          description: 'Works from any application, including full-screen ones.',
          onTap: () => _capture(context, ref),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (!binding.enabled)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Off',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: () => _capture(context, ref),
                child: Text(binding.display),
              ),
              const SizedBox(width: 6),
              if (binding != HotkeyBinding.defaultBinding)
                IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  tooltip: 'Back to ${HotkeyBinding.defaultBinding.display}',
                  onPressed: () => controller.apply(
                    (WinNotesSettings s) => s.copyWith(editorHotkey: HotkeyBinding.defaultBinding),
                  ),
                ),
            ],
          ),
        ),
        // A collision has to be visible. The spec is explicit that the app
        // notices rather than silently doing nothing.
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: <Widget>[
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    problem,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SettingsSeparator(),
        SettingsRow(
          label: 'Turn the hotkey off',
          description: 'The tray menu still opens the editor.',
          trailing: Switch(
            value: binding.enabled,
            onChanged: (bool value) => controller.apply(
              (WinNotesSettings s) => s.copyWith(
                editorHotkey: s.editorHotkey.copyWith(enabled: value),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
