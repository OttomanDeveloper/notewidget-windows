import 'package:flutter/material.dart';

import './palette.dart';

/// WinNotes' brand colours.
///
/// These are the *logo* — the indigo plate and the coral caret baked into the
/// mark, and the artwork derived from it. They are deliberately **not** the
/// user's palette: `WinNotesPalette` changes what the app looks like, and the
/// mark stays the mark. Tinting the logo with a chosen colour would make the
/// thing people recognise into one of nine variations of itself.
///
/// The live accent comes from [WinNotesPalette] instead. The values below are
/// the default palette's, kept here so the relationship between the two is
/// visible from one file.
class WinNotesColors {
  const WinNotesColors._();

  static const Color indigoDeep = Color(0xFF2B2450);
  static const Color indigo = Color(0xFF4B3FC0);
  static const Color indigoLight = Color(0xFF6A5BD0);
  static const Color coral = Color(0xFFE8551D);
  static const Color coralSoft = Color(0xFFFF7A45);
  static const Color parchment = Color(0xFFF7F5F0);
  static const Color inkMuted = Color(0xFFAEB4C6);
}

/// Motion durations, zeroed out when Windows reports animation is off.
class WinNotesMotion {
  const WinNotesMotion({required this.enabled});

  final bool enabled;

  Duration get fast => enabled ? const Duration(milliseconds: 120) : Duration.zero;
  Duration get medium => enabled ? const Duration(milliseconds: 220) : Duration.zero;
  Duration get slow => enabled ? const Duration(milliseconds: 340) : Duration.zero;
}

ThemeData buildWinNotesTheme({
  required Brightness brightness,
  required bool highContrast,
  WinNotesPalette? palette,
}) {
  final chosen = palette ?? winNotesPalettes.first;
  final isDark = brightness == Brightness.dark;
  final surfaces = chosen.surfaces(brightness);
  final accent = chosen.accentFor(brightness);

  // Built from the accent so the switches, checkboxes and text selections in
  // Settings belong to the palette, then the neutrals are replaced wholesale
  // with the ones from the neutral seed. Overriding the roles actually used
  // beats copyWith on a forty-field scheme: a field nobody reads cannot be
  // wrong in a way anyone sees.
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  ).copyWith(
    primary: accent,
    onPrimary: readableOn(accent),
    surface: surfaces.scaffold,
    onSurface: surfaces.onSurface,
    surfaceContainerLow: surfaces.surface,
    surfaceContainer: surfaces.plain,
    surfaceContainerHigh: surfaces.dialog,
    onSurfaceVariant: surfaces.onSurfaceVariant,
    outlineVariant: surfaces.outlineVariant,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: surfaces.scaffold,
  );

  final textTheme = base.textTheme.apply(
    bodyColor: surfaces.onSurface,
    displayColor: surfaces.onSurface,
  );

  return base.copyWith(
    textTheme: textTheme.copyWith(
      // Note bodies are read at a glance, so they get a touch more size and
      // looser line height than the Material default.
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.45, fontSize: 14.5),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(
      color: surfaces.outlineVariant.withValues(alpha: highContrast ? 0.9 : 0.35),
      thickness: highContrast ? 2 : 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaces.dialog,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 2),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark
            ? surfaces.dialog
            : surfaces.onSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: isDark ? surfaces.onSurface : Colors.white,
        fontSize: 12,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
  );
}

/// Black or white, whichever actually reads better on [background].
///
/// Both contrasts are computed and the higher one wins. A luminance *threshold*
/// looks equivalent and is not: the crossover where black overtakes white sits
/// at luminance 0.179, so a threshold anywhere near it gets mid-luminance
/// colours wrong. Mid-luminance saturated colours are precisely what an accent
/// is — coral's dark-mode variant measures 0.356, where white gives 2.6:1 and
/// black gives 8.1:1, and a threshold of 0.45 would have picked white.
///
/// This is what the palette's tick, the checkbox mark and the selection ring are
/// drawn in, so getting it wrong makes a finished task look unfinished.
Color readableOn(Color background) {
  const dark = Color(0xFF17151C);
  final luminance = background.computeLuminance();
  final againstWhite = 1.05 / (luminance + 0.05);
  final againstDark = (luminance + 0.05) / 0.05;
  return againstWhite >= againstDark ? Colors.white : dark;
}

/// Shorthand for picking the right surface colour for the widget.
Color widgetSurfaceColor({
  required Brightness brightness,
  required bool acrylicAvailable,
  required int opacityPercent,
  WinNotesPalette? palette,
}) {
  final chosen = palette ?? winNotesPalettes.first;
  final base = chosen
      .surfaces(brightness)
      .surfaceColor(acrylicAvailable: acrylicAvailable);
  // The window already carries a per-window alpha for this setting; the colour
  // alpha here is only a floor so text never sits on a fully clear surface.
  final floor = (opacityPercent / 100).clamp(0.35, 1.0);
  return base.withValues(alpha: base.a * floor);
}

/// Text colour for a note body on the widget surface.
///
/// Chosen for contrast against the widget surface rather than inherited from
/// the editor theme, because the widget floats over arbitrary content.
Color widgetBodyColor(Brightness brightness) =>
    brightness == Brightness.dark ? const Color(0xFFEDEBF5) : const Color(0xFF221E30);

Color widgetMutedColor(Brightness brightness) =>
    brightness == Brightness.dark ? const Color(0xFF9A94B4) : const Color(0xFF6B6479);