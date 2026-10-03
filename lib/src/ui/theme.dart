import 'package:flutter/material.dart';

/// WinNotes' colours.
///
/// Built from the logo rather than from Material's defaults: the indigo plate
/// and the coral caret are the two brand colours, and the accent is the caret
/// because that is the part of the mark that means "being written right now".
class WinNotesColors {
  const WinNotesColors._();

  static const Color indigoDeep = Color(0xFF2B2450);
  static const Color indigo = Color(0xFF4B3FC0);
  static const Color indigoLight = Color(0xFF6A5BD0);
  static const Color coral = Color(0xFFE8551D);
  static const Color coralSoft = Color(0xFFFF7A45);
  static const Color parchment = Color(0xFFF7F5F0);
  static const Color inkMuted = Color(0xFFAEB4C6);

  /// Widget surface fills.
  ///
  /// The widget is drawn over the desktop, so these need to hold up against an
  /// arbitrary wallpaper. The light surface is warm rather than pure white so
  /// it separates from a white background without needing a border.
  static const Color widgetSurfaceLight = Color(0xF2F7F5F0);
  static const Color widgetSurfaceDark = Color(0xF21F1A38);
  static const Color widgetSurfacePlainLight = Color(0xE6EDE9E1);
  static const Color widgetSurfacePlainDark = Color(0xE6161228);
}

/// Motion durations, zeroed out when Windows reports animation is off.
class WinNotesMotion {
  const WinNotesMotion(this.enabled);

  final bool enabled;

  Duration get fast => enabled ? const Duration(milliseconds: 120) : Duration.zero;
  Duration get medium => enabled ? const Duration(milliseconds: 220) : Duration.zero;
  Duration get slow => enabled ? const Duration(milliseconds: 340) : Duration.zero;
}

ThemeData buildWinNotesTheme({
  required Brightness brightness,
  required bool highContrast,
}) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: WinNotesColors.indigo,
    brightness: brightness,
  ).copyWith(
    // The caret colour, used for the one interactive accent per surface.
    primary: isDark ? WinNotesColors.coralSoft : WinNotesColors.coral,
    secondary: WinNotesColors.indigoLight,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF14111F)
        : const Color(0xFFF3F1EA),
  );

  final textTheme = base.textTheme.apply(
    bodyColor: isDark ? const Color(0xFFE8E6F0) : const Color(0xFF23202E),
    displayColor: isDark ? const Color(0xFFF5F3FA) : const Color(0xFF1B1826),
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
      color: scheme.outlineVariant.withValues(alpha: highContrast ? 0.9 : 0.35),
      thickness: highContrast ? 2 : 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF221D33) : WinNotesColors.parchment,
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
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF322B4C) : const Color(0xFF2B2450),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
  );
}

/// Shorthand for picking the right surface colour for the widget.
Color widgetSurfaceColor({
  required Brightness brightness,
  required bool acrylicAvailable,
  required int opacityPercent,
}) {
  final isDark = brightness == Brightness.dark;
  final base = acrylicAvailable
      ? (isDark ? WinNotesColors.widgetSurfaceDark : WinNotesColors.widgetSurfaceLight)
      : (isDark ? WinNotesColors.widgetSurfacePlainDark : WinNotesColors.widgetSurfacePlainLight);
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