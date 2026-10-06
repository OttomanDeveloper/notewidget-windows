import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';

import 'package:win_notes/core/platform/shell_channel.dart';

import '../../../../../core/theme/palette.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/app_providers.dart';
import '../../../../../core/utils/atomic_json_file.dart';
import '../../data/settings_repository.dart';
import '../../domain/repositories.dart';
import './settings_controller.dart';

/// `settings.json`. Written only by the editor surface, watched by both.
final Provider<ISettingsRepository> settingsRepositoryProvider = Provider<ISettingsRepository>((Ref ref) {
  return SettingsRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).settingsFile),
    ref.watch(shellProvider),
  );
});

/// The `ThemeData` both surfaces draw with. The widget replaces the ambient one
/// with a bare surface (it paints its own colour); see `widget_app.dart`.
final Provider<ThemeData> widgetSurfaceThemeProvider = Provider<ThemeData>((Ref ref) {
  final (ThemeMode?, String?) selected = ref.watch(
    settingsProvider.select(
      (AsyncValue<SettingsState> v) => (
        v.value?.settings.themeMode,
        v.value?.settings.accentPalette,
      ),
    ),
  );
  final LaunchInfo launch = ref.watch(launchInfoProvider);
  final Brightness systemBrightness = ref.watch(systemBrightnessProvider);

  final Brightness brightness = switch (selected.$1 ?? ThemeMode.system) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => systemBrightness,
  };

  return buildWinNotesTheme(
    brightness: brightness,
    highContrast: launch.highContrast,
    palette: paletteById(selected.$2),
  );
});

/// The palette on its own, for the widget surface. Separate because `ThemeData`
/// exposes no palette fields; index zero is the default for pre-setting files
/// (`AGENTS.md` §0.5).
final Provider<WinNotesPalette> accentPaletteProvider = Provider<WinNotesPalette>((Ref ref) {
  final String? id = ref.watch(
    settingsProvider.select((AsyncValue<SettingsState> v) => v.value?.settings.accentPalette),
  );
  return paletteById(id);
});

/// Where notes actually live: derived from the configured directory, so
/// unrelated settings changes leave this row alone.
final storageDirectoryProvider =
    Provider.family<String, String>((Ref ref, String defaultDirectory) {
  final String configured = ref.watch(
    settingsProvider.select((AsyncValue<SettingsState> v) => v.value?.settings.storageDirectory.trim() ?? ''),
  );
  if (configured.isEmpty) return defaultDirectory;
  return configured;
});

/// Whether animation is allowed, from the runner's report at launch.
final Provider<bool> animationsEnabledProvider = Provider<bool>((Ref ref) {
  return ref.watch(
        settingsProvider.select((AsyncValue<SettingsState> v) => v.value?.animationsEnabled),
      ) ??
      true;
});

/// Whether this build can do acrylic at all.
final Provider<bool> acrylicSupportedProvider = Provider<bool>((Ref ref) {
  return ref.watch(
        settingsProvider.select((AsyncValue<SettingsState> v) => v.value?.acrylicSupported),
      ) ??
      false;
});
