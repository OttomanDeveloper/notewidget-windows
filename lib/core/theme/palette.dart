import 'package:flutter/material.dart';

/// One complete colour choice: accent, neutrals seed, and the rule that no
/// free picker can satisfy - legible on light, dark and photographic surfaces.
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

  /// Drives every neutral. Deliberately not the accent: the brand is a warm
  /// accent on a cool plate, and tying them would flatten it to one hue.
  final Color neutralSeed;

  /// Surfaces for [brightness]. The widget draws its own surface with an alpha
  /// its theme does not know about, over the desktop rather than its window.
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

  /// The widget's fill. `plain` compensates for losing acrylic's lift, so the
  /// same colour reads the same with it on and off.
  Color surfaceColor({required bool acrylicAvailable}) =>
      acrylicAvailable ? surface : plain;
}

/// Every palette, in the order Settings shows them. First stays first: a missing
/// palette field resolves to index zero, so reordering changes old installs.
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

/// The palette for [id], or the default. Unknown names fall back silently:
/// an old file must still open, so "never chose one" beats refusing to start.
WinNotesPalette paletteById(String? id) {
  if (id == null) return winNotesPalettes.first;
  for (final palette in winNotesPalettes) {
    if (palette.id == id) return palette;
  }
  return winNotesPalettes.first;
}