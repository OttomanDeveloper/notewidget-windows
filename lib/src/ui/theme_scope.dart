/// The theme, resolved once for both surfaces.
///
/// This file exists because of a divergence, not for tidiness. `AGENTS.md` §4.7:
/// `_resolveBrightness` had three copies across `EditorApp` and `WidgetApp`, and
/// the widget's copies disagreed with the editor's about what "system" brightness
/// means when Windows has not reported one. With both surfaces open and a theme
/// change while the app runs, the two could resolve differently and the widget would
/// stop matching the editor.
///
/// One provider, one function, and both surfaces read it. The inputs are the settings
/// and the live system brightness, both of which are already providers, so there is
/// nothing here that can drift.
///
/// It lives under `ui/` rather than beside the other providers because it imports
/// `theme.dart` and `palette.dart`, and `state/` must not reach up into `ui/` -
/// `AGENTS.md` §3 draws those arrows one way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../state/settings_controller.dart';
import 'palette.dart';
import 'theme.dart';

/// The `ThemeData` both surfaces draw with.
///
/// The editor uses it as the `MaterialApp`'s theme. The widget surface uses it for
/// the palette and high-contrast flag and then deliberately replaces the ambient
/// `ThemeData` with a bare one, because the widget paints its own surface colour and
/// an ambient brightness would be wrong - see `widget_app.dart`. That is a separate
/// decision about `Theme`, not a second answer to this question.
final widgetSurfaceThemeProvider = Provider<ThemeData>((ref) {
  final settings = ref.watch(settingsProvider).value?.settings;
  final launch = ref.watch(launchInfoProvider);
  final systemBrightness = ref.watch(systemBrightnessProvider);

  final brightness = switch (settings?.themeMode ?? ThemeMode.system) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => systemBrightness,
  };

  return buildWinNotesTheme(
    brightness: brightness,
    highContrast: launch.highContrast,
    palette: paletteById(settings?.accentPalette),
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
  final id = ref.watch(settingsProvider).value?.settings.accentPalette;
  return paletteById(id);
});

/// Whether animation is allowed, from the runner's report at launch.
final animationsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).value?.animationsEnabled ?? true;
});

/// Whether this build can do acrylic at all.
final acrylicSupportedProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).value?.acrylicSupported ?? false;
});