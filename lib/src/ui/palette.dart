import 'package:flutter/material.dart';

/// One complete colour choice: the accent you interact with, and the neutral
/// family everything else is built from.
///
/// Three hand-picked values per palette, not ten. The accent pair is exact, so
/// the swatch in Settings is the colour you actually get. Everything else —
/// editor background, widget surface, dialog, dividers, switches — is derived
/// from [neutralSeed] with `ColorScheme.fromSeed`, which guarantees the tonal
/// relationships hold. Hand-picking ten colours per palette would put that
/// guarantee in nine places instead of one, and the ninth would be wrong.
///
/// Why a palette and not a free picker: these sit over an arbitrary desktop
/// wallpaper through an acrylic window, so an accent has to stay legible on a
/// light surface *and* a dark one *and* against a photograph. Every swatch here
/// has been chosen for that. A picker could produce a colour that fails, and
/// there is no honest way to let someone pick one.
@immutable
class WinNotesPalette {
  const WinNotesPalette({
    required this.id,
    required this.label,
    required this.accent,
    required this.accentDark,
    required this.neutralSeed,
  });

  /// Stored in `settings.json`. **Frozen** — renaming one silently resets
  /// anyone who chose it, so add new palettes, do not rename these.
  final String id;

  /// Shown in Settings.
  final String label;

  /// The caret colour on a light surface: the focused card's bar, the tick, the
  /// composer's border, the selection highlight.
  final Color accent;

  /// The same role on a dark surface. Always lighter than [accent] rather than
  /// darker, because a saturated colour on a dark background loses its edge.
  final Color accentDark;

  /// Drives every neutral: editor background, widget surface, dialog, dividers,
  /// the switches in Settings.
  ///
  /// Deliberately *not* the accent. The brand is a warm accent on a cool plate,
  /// and tying the two together would flatten it into a single hue. It is also
  /// what lets a palette be calm: the Coral default keeps the indigo-tinted
  /// darks and warm parchment lights the app has always had.
  final Color neutralSeed;

  /// Surfaces for [brightness], derived from [neutralSeed].
  ///
  /// The widget draws its own surface rather than using the theme's, because it
  /// composites over the desktop instead of over its own window, and it needs an
  /// alpha its theme does not know about.
  WidgetSurfaces surfaces(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: neutralSeed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    return isDark
        ? WidgetSurfaces(
            // Dark: the editor sits deepest, the widget floats a little lighter
            // so it separates from whatever is behind it.
            scaffold: scheme.surface,
            surface: scheme.surfaceContainerLow,
            // No acrylic to lift the background, so the surface has to carry
            // the separation itself: one step further from the editor.
            plain: scheme.surfaceContainer,
            dialog: scheme.surfaceContainerHigh,
            onSurface: scheme.onSurface,
            onSurfaceVariant: scheme.onSurfaceVariant,
            outlineVariant: scheme.outlineVariant,
          )
        : WidgetSurfaces(
            scaffold: scheme.surfaceContainerHigh,
            surface: scheme.surfaceContainerLow,
            plain: scheme.surfaceContainer,
            dialog: scheme.surfaceContainerLow,
            onSurface: scheme.onSurface,
            onSurfaceVariant: scheme.onSurfaceVariant,
            outlineVariant: scheme.outlineVariant,
          );
  }

  /// The accent for [brightness]. The single place that mapping is decided, so
  /// the widget card and the editor cannot disagree about it.
  Color accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? accentDark : accent;
}

/// The neutral surfaces one palette produces for one brightness.
@immutable
class WidgetSurfaces {
  const WidgetSurfaces({
    required this.scaffold,
    required this.surface,
    required this.plain,
    required this.dialog,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outlineVariant,
  });

  /// The editor's background.
  final Color scaffold;

  /// The widget's surface with acrylic behind it.
  final Color surface;

  /// The widget's surface with acrylic switched off, so it has to carry its own
  /// separation from the desktop.
  final Color plain;

  /// Dialogs and sheets, which need to read as raised above the editor.
  final Color dialog;

  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outlineVariant;

  /// The widget's fill, with or without acrylic behind it.
  ///
  /// Acrylic blurs and slightly lightens whatever is behind the window, so the
  /// same colour reads differently with it on and off. `plain` is a step further
  /// from the editor background to compensate for losing that lift.
  Color surfaceColor({required bool acrylicAvailable}) =>
      acrylicAvailable ? surface : plain;
}

/// Every palette, in the order Settings shows them.
///
/// The first is the default and must stay first: `settings.json` from before
/// this feature existed has no palette field, and a missing field resolves to
/// index zero rather than to a name, so reordering this list changes what an
/// existing install sees.
const List<WinNotesPalette> winNotesPalettes = <WinNotesPalette>[
  // The app's own colours, unchanged. Warm caret on a cool plate.
  WinNotesPalette(
    id: 'coral',
    label: 'Coral',
    accent: Color(0xFFE8551D),
    accentDark: Color(0xFFFF7A45),
    neutralSeed: Color(0xFF4B3FC0),
  ),
  WinNotesPalette(
    id: 'indigo',
    label: 'Indigo',
    accent: Color(0xFF4B3FC0),
    accentDark: Color(0xFF9C8CFF),
    neutralSeed: Color(0xFF3A3178),
  ),
  WinNotesPalette(
    id: 'teal',
    label: 'Teal',
    accent: Color(0xFF0B7285),
    accentDark: Color(0xFF52D3E0),
    neutralSeed: Color(0xFF17505A),
  ),
  WinNotesPalette(
    id: 'moss',
    label: 'Moss',
    accent: Color(0xFF3D7A2C),
    accentDark: Color(0xFF86D46F),
    neutralSeed: Color(0xFF2F5130),
  ),
  WinNotesPalette(
    id: 'amber',
    label: 'Amber',
    accent: Color(0xFFA9690A),
    accentDark: Color(0xFFF5BC4E),
    neutralSeed: Color(0xFF5C4822),
  ),
  WinNotesPalette(
    id: 'rose',
    label: 'Rose',
    accent: Color(0xFFB62A55),
    accentDark: Color(0xFFFF87AC),
    neutralSeed: Color(0xFF5E2338),
  ),
  WinNotesPalette(
    id: 'violet',
    label: 'Violet',
    accent: Color(0xFF6B3FBF),
    accentDark: Color(0xFFBCA3FF),
    neutralSeed: Color(0xFF413163),
  ),
  WinNotesPalette(
    id: 'steel',
    label: 'Steel',
    accent: Color(0xFF33637F),
    accentDark: Color(0xFF86BAD8),
    neutralSeed: Color(0xFF33434F),
  ),
  // For people who want the app to stop being colourful. Not grey exactly: a
  // pure neutral reads as unfinished next to a tinted option, so this is a very
  // slightly warm grey.
  WinNotesPalette(
    id: 'graphite',
    label: 'Graphite',
    accent: Color(0xFF4C4A50),
    accentDark: Color(0xFFB6B2BC),
    neutralSeed: Color(0xFF4A474D),
  ),
];

/// The palette for [id], or the default if it names nothing we ship.
///
/// Falling back silently is deliberate and is the whole backwards-compatibility
/// story: a `settings.json` written by an older build, or by a build with a
/// palette we have since removed, must still open. An unknown name is treated
/// as "never chose one" rather than as an error worth refusing to start over.
WinNotesPalette paletteById(String? id) {
  if (id == null) return winNotesPalettes.first;
  for (final palette in winNotesPalettes) {
    if (palette.id == id) return palette;
  }
  return winNotesPalettes.first;
}