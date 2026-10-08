import 'package:flutter/widgets.dart';

/// What a design's edge does, which is most of what makes it recognisable: a
/// ruled sheet, a row of perforations, a torn stub, a dotted field, or nothing.
enum DesignEdge {
  /// No edge treatment. What the widget draws today.
  plain,

  /// Faint horizontal rules behind the text, like a sheet of paper.
  ruled,

  /// A row of punched holes with a dashed line through them.
  perforated,

  /// A zigzag along the bottom, as if torn off.
  torn,

  /// A dot grid behind the content.
  dotted,
}

/// How a design sets type: sentence case, or all caps as a stamp would.
enum DesignCasing {
  sentence,
  upper,
}

/// A widget design: the **shape and type** of a card, and nothing else. No
/// colour, for the reason a skin carries none: colour is [WinNotesPalette]
/// s job, and three controls doing overlapping work is worse than two.
@immutable
class WidgetDesign {
  const WidgetDesign({
    required this.id,
    required this.label,
    required this.edge,
    required this.casing,
    required this.bodyFont,
    required this.bodyFontFallback,
    required this.titleFont,
    required this.tilt,
    required this.cornerRadius,
    required this.budgetScale,
    required this.shadow,
  });

  /// Stable, never reused or reordered. It lives in `settings.json`, so a
  /// rename here silently resets anyone's choice (`AGENTS.md` §0.5).
  final String id;
  final String label;

  final DesignEdge edge;
  final DesignCasing casing;

  /// Windows fonts, by name, so no font binary is added to the repo and none
  /// of these needs a dependency (`AGENTS.md` §0.4). Flutter ships only
  /// Roboto, and a paper or a ticket has to *look* like one.
  final String bodyFont;
  final List<String> bodyFontFallback;
  final String titleFont;

  /// Degrees. A sheet lies flat and a stamp does not; 0 means square to the
  /// window, which is what "no design" does.
  final double tilt;
  final double cornerRadius;

  /// Multiplier on the body's line budget. A receipt is narrow and wants more
  /// lines in less height; paper wants fewer and roomier.
  final double budgetScale;

  /// Whether the card casts a shadow. A stamp is ink on the desktop and casts
  /// none; a sheet of paper does.
  final bool shadow;
}

/// No design means no design, and it means exactly what the widget drew before
/// this feature existed. Not the first entry in [widgetDesigns] - a default is
/// a promise that it will never move (`AGENTS.md` §0.5).
const WidgetDesign? noDesign = null;

/// Every design, in the order Settings shows them. Five, and none is the
/// built-in look: an entry that renders what "no design" renders is a chip
/// that repaints nothing when tapped, which is worse than not offering it.
const List<WidgetDesign> widgetDesigns = <WidgetDesign>[
  WidgetDesign(
    id: 'paper',
    label: 'Paper',
    edge: DesignEdge.ruled,
    casing: DesignCasing.sentence,
    bodyFont: 'Segoe Print',
    bodyFontFallback: <String>['Segoe Script', 'Comic Sans MS', 'cursive'],
    titleFont: 'Segoe Print',
    tilt: -0.012,
    cornerRadius: 2,
    budgetScale: 0.8,
    shadow: true,
  ),
  WidgetDesign(
    id: 'stamp',
    label: 'Stamp',
    edge: DesignEdge.plain,
    casing: DesignCasing.upper,
    bodyFont: 'Bahnschrift Condensed',
    bodyFontFallback: <String>['Impact', 'Arial Narrow', 'sans-serif'],
    titleFont: 'Impact',
    tilt: -0.045,
    cornerRadius: 1,
    budgetScale: 0.7,
    shadow: false,
  ),
  WidgetDesign(
    id: 'ticket',
    label: 'Ticket',
    edge: DesignEdge.perforated,
    casing: DesignCasing.sentence,
    bodyFont: 'Consolas',
    bodyFontFallback: <String>['Courier New', 'monospace'],
    titleFont: 'Consolas',
    tilt: 0,
    cornerRadius: 4,
    budgetScale: 0.85,
    shadow: true,
  ),
  WidgetDesign(
    id: 'soft',
    label: 'Soft',
    edge: DesignEdge.dotted,
    casing: DesignCasing.sentence,
    bodyFont: 'Segoe UI',
    bodyFontFallback: <String>['Verdana', 'sans-serif'],
    titleFont: 'Segoe UI Semibold',
    tilt: 0,
    cornerRadius: 20,
    budgetScale: 1,
    shadow: true,
  ),
  WidgetDesign(
    id: 'receipt',
    label: 'Receipt',
    edge: DesignEdge.torn,
    casing: DesignCasing.sentence,
    bodyFont: 'Consolas',
    bodyFontFallback: <String>['Courier New', 'monospace'],
    titleFont: 'Consolas',
    tilt: 0.008,
    cornerRadius: 0,
    budgetScale: 1.15,
    shadow: false,
  ),
];

/// The design for [id], or null when [id] is empty or names nothing. Null
/// rather than a fallback: an unrecognised id is a file written by a newer
/// build and must not be read as the first entry.
WidgetDesign? designById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final WidgetDesign design in widgetDesigns) {
    if (design.id == id) return design;
  }
  return null;
}

/// The built-in look's own numbers, in one place, so "no design" cannot drift
/// from the widget's idea of it.
@immutable
class DesignLook {
  const DesignLook({
    required this.edge,
    required this.casing,
    required this.bodyFont,
    required this.bodyFontFallback,
    required this.titleFont,
    required this.tilt,
    required this.cornerRadius,
    required this.budgetScale,
    required this.shadow,
  });

  static const DesignLook builtIn = DesignLook(
    edge: DesignEdge.plain,
    casing: DesignCasing.sentence,
    bodyFont: '',
    bodyFontFallback: <String>[],
    titleFont: '',
    tilt: 0,
    cornerRadius: 10,
    budgetScale: 1,
    shadow: false,
  );

  final DesignEdge edge;
  final DesignCasing casing;
  final String bodyFont;
  final List<String> bodyFontFallback;
  final String titleFont;
  final double tilt;
  final double cornerRadius;
  final double budgetScale;
  final bool shadow;

  BorderRadius get shape => BorderRadius.circular(cornerRadius);
}

/// [design]'s look, or [DesignLook.builtIn] when none is chosen - the one place
/// "no design" is decided, so two cards cannot disagree about it.
DesignLook lookOfDesign(WidgetDesign? design) =>
    design == null ? DesignLook.builtIn : lookFromDesign(design);

/// The same numbers without the null check, for callers that already hold a
/// design. Kept separate so [lookOfDesign] stays the single decision point.
DesignLook lookFromDesign(WidgetDesign design) => DesignLook(
      edge: design.edge,
      casing: design.casing,
      bodyFont: design.bodyFont,
      bodyFontFallback: design.bodyFontFallback,
      titleFont: design.titleFont,
      tilt: design.tilt,
      cornerRadius: design.cornerRadius,
      budgetScale: design.budgetScale,
      shadow: design.shadow,
    );
