import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';

import '../../../../../core/theme/palette.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/app_providers.dart';
import '../../../../../core/utils/atomic_json_file.dart';
import '../../data/settings_repository.dart';
import '../../domain/repositories.dart';
import './settings_controller.dart';

/// `settings.json`. Written only by the editor surface, watched by both.
final settingsRepositoryProvider = Provider<ISettingsRepository>((ref) {
  return SettingsRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).settingsFile),
    ref.watch(shellProvider),
  );
});

/// The `ThemeData` both surfaces draw with.
///
/// The editor uses it as the `MaterialApp`'s theme. The widget surface uses it for
/// the palette and high-contrast flag and then deliberately replaces the ambient
/// `ThemeData` with a bare one, because the widget paints its own surface colour and
/// an ambient brightness would be wrong - see `widget_app.dart`. That is a separate
/// decision about `Theme`, not a second answer to this question.
final widgetSurfaceThemeProvider = Provider<ThemeData>((ref) {
  final selected = ref.watch(
    settingsProvider.select(
      (v) => (
        v.value?.settings.themeMode,
        v.value?.settings.accentPalette,
      ),
    ),
  );
  final launch = ref.watch(launchInfoProvider);
  final systemBrightness = ref.watch(systemBrightnessProvider);

  final brightness = switch (selected.$1 ?? ThemeMode.system) {
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

/// The palette on its own, for the widget surface.
///
/// A separate provider rather than a field on [WidgetSurfaceTheme] because the
/// widget needs the accent colour and the palette's contrast helpers, and reading
/// them out of a `ThemeData` would mean reaching into it for fields it does not
/// expose. `paletteById(0)` is the default rather than a named constant, because a
/// settings file written before the setting existed resolves to index zero -
/// `AGENTS.md` §0.5.
final accentPaletteProvider = Provider<WinNotesPalette>((ref) {
  final id = ref.watch(
    settingsProvider.select((v) => v.value?.settings.accentPalette),
  );
  return paletteById(id);
});

/// Where notes actually live, honouring a custom location.
///
/// Derived rather than concatenated in `build()`: the only input is the
/// configured directory, so an unrelated settings change leaves this row alone.
final storageDirectoryProvider =
    Provider.family<String, String>((ref, defaultDirectory) {
  final configured = ref.watch(
    settingsProvider.select((v) => v.value?.settings.storageDirectory.trim() ?? ''),
  );
  if (configured.isEmpty) return defaultDirectory;
  return configured;
});

/// Whether animation is allowed, from the runner's report at launch.
final animationsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(
        settingsProvider.select((v) => v.value?.animationsEnabled),
      ) ??
      true;
});

/// Whether this build can do acrylic at all.
final acrylicSupportedProvider = Provider<bool>((ref) {
  return ref.watch(
        settingsProvider.select((v) => v.value?.acrylicSupported),
      ) ??
      false;
});
