import 'package:flutter/widgets.dart';

/// How the open note is picked out: an accent bar today, and three other ways
/// to do the same job. Two skins that differ here look like two designs, not
/// two colours.
enum SkinFocus {
  /// Accent left-edge, faint fill. What the app does with no skin chosen.
  bar,

  /// A full outline around the row, and no fill.
  outline,

  /// A filled block, and no edge.
  fill,

  /// Nothing marks it. The selection is then only in the editor's own title.
  none,
}

/// What goes between rows. `gap` is the widget today and `hairline` the editor
/// today, so "no skin" has to mean both of them.
enum SkinSeparator {
  /// Space, no rule. What the widget does today.
  gap,

  /// A hairline. What the editor's list does today.
  hairline,

  /// Neither - rows run together.
  none,
}

/// A skin: the **shape** of a card, and nothing else. Deliberately no colour
/// - that is [WinNotesPalette]`s job, and a skin that also carried a plate made
/// Skin and Colour two controls doing one thing, which is what this replaced.
@immutable
class WinNotesSkin {
  const WinNotesSkin({
    required this.id,
    required this.label,
    required this.cornerRadius,
    required this.density,
    required this.focus,
    required this.separator,
  });

  /// Stable, never reused or reordered. It lives in `settings.json`.
  final String id;
  final String label;

  /// Corner roundness in logical pixels. 0 is square, 18 is soft.
  final double cornerRadius;

  /// Multiplier on a row's padding. 1.0 is what the app has always used.
  final double density;

  final SkinFocus focus;
  final SkinSeparator separator;

  /// [base] scaled by [density], so a skin says "tighter" or "roomier" rather
  /// than restating four padding numbers per skin.
  double pad(double base) => base * density;

  BorderRadius get shape => BorderRadius.circular(cornerRadius);

  @override
  bool operator ==(Object other) => other is WinNotesSkin && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// No skin means no skin, and it means exactly what the app did before this
/// feature: rounded 10, roomy, an accent bar, gaps. Not the first entry in
/// [winNotesSkins] - a default is a promise that it will never move (§0.5).
const WinNotesSkin? noSkin = null;

/// Every skin, in the order Settings shows them. Four, and none is the
/// built-in look: one that matched "no skin" would be a control that repaints
/// nothing when tapped, which is worse than not offering it.
const List<WinNotesSkin> winNotesSkins = <WinNotesSkin>[
  WinNotesSkin(
    id: 'sharp',
    label: 'Sharp',
    cornerRadius: 0,
    density: 0.8,
    focus: SkinFocus.bar,
    separator: SkinSeparator.hairline,
  ),
  WinNotesSkin(
    id: 'soft',
    label: 'Soft',
    cornerRadius: 18,
    density: 1.25,
    focus: SkinFocus.bar,
    separator: SkinSeparator.gap,
  ),
  WinNotesSkin(
    id: 'outline',
    label: 'Outline',
    cornerRadius: 10,
    density: 1,
    focus: SkinFocus.outline,
    separator: SkinSeparator.hairline,
  ),
  WinNotesSkin(
    id: 'solid',
    label: 'Solid',
    cornerRadius: 10,
    density: 1,
    focus: SkinFocus.fill,
    separator: SkinSeparator.gap,
  ),
];

/// The skin for [id], or null when [id] is empty or names nothing. Null rather
/// than a fallback: an unrecognised id is a file written by a newer build and
/// must not be read as the first entry.
WinNotesSkin? skinById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final WinNotesSkin skin in winNotesSkins) {
    if (skin.id == id) return skin;
  }
  return null;
}

/// Resolves "no skin" in one place, so a card and a row cannot disagree about
/// what the app looks like with nothing chosen.
@immutable
class SkinLook {
  const SkinLook({
    required this.cornerRadius,
    required this.density,
    required this.focus,
    required this.separator,
  });

/// The app's own long-standing numbers, in one place so the built-in look
/// cannot drift from this file's idea of it.
  static const SkinLook builtIn = SkinLook(
    cornerRadius: 10,
    density: 1,
    focus: SkinFocus.bar,
    separator: SkinSeparator.gap,
  );

  final double cornerRadius;
  final double density;
  final SkinFocus focus;
  final SkinSeparator separator;

  BorderRadius get shape => BorderRadius.circular(cornerRadius);

  double pad(double base) => base * density;

  /// The editor's list separates with a hairline where the widget uses a gap, so
  /// "no skin" has to mean both of those rather than one number for both.
  static SkinSeparator forEditor(SkinSeparator widgetSeparator) =>
      widgetSeparator == SkinSeparator.gap
          ? SkinSeparator.hairline
          : widgetSeparator;
}

/// [skin]'s look, or [SkinLook.builtIn] when none is chosen.
SkinLook lookOf(WinNotesSkin? skin) =>
    skin == null ? SkinLook.builtIn : lookFrom(skin);

/// The same numbers, without the null check - for callers that already hold a
/// skin. Kept separate so [lookOf] stays the one place "no skin" is decided.
SkinLook lookFrom(WinNotesSkin skin) => SkinLook(
      cornerRadius: skin.cornerRadius,
      density: skin.density,
      focus: skin.focus,
      separator: skin.separator,
    );
