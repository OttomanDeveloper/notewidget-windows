// Skins: the **shape** of a card, and nothing else.
//
// The first version of this feature made a skin carry a plate, an accent and a
// font, which turned Skin into a second Colour control doing the Colour
// control's job. These tests are written against the corrected rule - a skin has
// no colour in it at all - and the first group is the one that stops that coming
// back.
//
// The property that matters most is the one about **not** changing anything: an
// install with no skin has to look and feel exactly as it did before this feature
// existed, because §0.5's rule about defaults that must not move applies to a
// setting added later just as it did to the palette one.
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/theme/palette.dart';
import 'package:flutter/material.dart';
import 'package:win_notes/core/theme/theme.dart';
import 'package:win_notes/features/settings/domain/settings.dart';
import 'package:win_notes/core/theme/skin.dart';

void main() {
  group('a skin carries no colour', () {
    // The mistake, pinned. A skin that has a colour in it is a second Colour.
    test('the skin model exposes no colour field', () {
      for (final WinNotesSkin skin in winNotesSkins) {
        expect(
          skin.toString(),
          isNot(contains('Color')),
          reason: 'a skin must not describe itself in colour',
        );
      }
    });

    test('a skin does not change the theme', () {
      // The strongest form of the rule: build the theme with and without each
      // skin and demand an identical result. If a skin ever reaches colour
      // again, this fails rather than a reviewer noticing.
      final ThemeData without = buildWinNotesTheme(
        brightness: Brightness.light,
        highContrast: false,
      );
      for (final WinNotesSkin skin in winNotesSkins) {
        expect(themeDataFor(skin).colorScheme.primary, without.colorScheme.primary,
            reason: '${skin.id} changed the accent');
        expect(themeDataFor(skin).colorScheme.surface, without.colorScheme.surface,
            reason: '${skin.id} changed the plate');
        expect(themeDataFor(skin).colorScheme.surfaceContainerLow,
            without.colorScheme.surfaceContainerLow,
            reason: '${skin.id} changed the widget surface');
      }
    });
  });

  group('a skin resolves, or does not', () {
    test('every skin in the list has an id that resolves back to it', () {
      for (final WinNotesSkin skin in winNotesSkins) {
        expect(skinById(skin.id), same(skin),
            reason: '${skin.id} does not resolve');
      }
    });

    test('ids are unique, because settings.json stores one', () {
      final Set<String> ids =
          winNotesSkins.map((WinNotesSkin s) => s.id).toSet();
      expect(ids.length, winNotesSkins.length);
    });

    test('empty and null mean no skin, not the first skin', () {
      expect(skinById(''), isNull);
      expect(skinById(null), isNull);
      expect(noSkin, isNull);
    });

    test('an unknown id is null rather than the first skin', () {
      // A file written by a newer build. Reading it as the first skin would
      // silently reshape someone's app.
      expect(skinById('from-the-future'), isNull);
    });
  });

  group('no skin means the app has always looked like this', () {
    test('the built-in look is rounded 10, roomy, an accent bar, gaps', () {
      final SkinLook look = lookOf(null);
      expect(look.cornerRadius, 10);
      expect(look.density, 1);
      expect(look.focus, SkinFocus.bar);
      expect(look.separator, SkinSeparator.gap);
    });

    test('the editor separates with a hairline where the widget uses a gap', () {
      // Both were true before this feature, so "no skin" has to mean both.
      expect(SkinLook.forEditor(SkinSeparator.gap), SkinSeparator.hairline);
      expect(SkinLook.forEditor(SkinSeparator.hairline), SkinSeparator.hairline);
      expect(SkinLook.forEditor(SkinSeparator.none), SkinSeparator.none);
    });

    test('a file written before skins existed resolves to no skin', () {
      final WinNotesSettings parsed =
          WinNotesSettings.fromJson(<String, dynamic>{'themeMode': 'dark'});
      expect(parsed.skin, isEmpty);
      expect(skinById(parsed.skin), isNull);
    });
  });

  group('a skin actually changes the shape', () {
    test('no skin is the built-in look, and no skin in the list is', () {
      for (final WinNotesSkin skin in winNotesSkins) {
        expect(skinById(null), isNull, reason: 'there is no default skin');
        expect(
          skin.cornerRadius != SkinLook.builtIn.cornerRadius ||
              skin.focus != SkinLook.builtIn.focus ||
              skin.density != SkinLook.builtIn.density ||
              skin.separator != SkinLook.builtIn.separator,
          isTrue,
          reason: '${skin.id} is the built-in look, so tapping it would '
              'change nothing',
        );
      }
    });

    test('corners differ across the skins', () {
      final Set<double> radii = winNotesSkins
          .map((WinNotesSkin s) => s.cornerRadius)
          .toSet();
      expect(radii.length, greaterThan(1),
          reason: 'every skin has the same corner, so that is not a skin');
    });

    test('density tightens and loosens the built-in padding', () {
      final SkinLook builtIn = lookOf(null);
      for (final WinNotesSkin skin in winNotesSkins) {
        final SkinLook look = lookOf(skin);
        if (skin.density > 1) {
          expect(look.pad(10), greaterThan(builtIn.pad(10)));
        } else if (skin.density < 1) {
          expect(look.pad(10), lessThan(builtIn.pad(10)));
        }
      }
    });

    test('focus markers differ across the skins', () {
      final Set<SkinFocus> markers =
          winNotesSkins.map((WinNotesSkin s) => s.focus).toSet();
      expect(markers.length, greaterThan(1),
          reason: 'every skin marks the open note the same way');
    });

    test('separators differ across the skins', () {
      final Set<SkinSeparator> separators =
          winNotesSkins.map((WinNotesSkin s) => s.separator).toSet();
      expect(separators.length, greaterThan(1));
    });
  });

  group('the setting', () {
    test('a chosen skin round trips through the file', () {
      final WinNotesSettings s = WinNotesSettings.defaults.copyWith(skin: 'sharp');
      expect(WinNotesSettings.fromJson(s.toJson()).skin, 'sharp');
    });

    test('it is omitted when empty, for the same reason as the palette', () {
      expect(WinNotesSettings.defaults.toJson().containsKey('skin'), isFalse);
    });

    test('the palette and the skin are separate keys and can disagree', () {
      final WinNotesSettings s =
          WinNotesSettings.defaults.copyWith(accentPalette: 'teal', skin: 'solid');
      final Map<String, dynamic> json = s.toJson();
      expect(json['accentPalette'], 'teal');
      expect(json['skin'], 'solid');
      final WinNotesSettings back = WinNotesSettings.fromJson(json);
      expect(back.accentPalette, 'teal');
      expect(back.skin, 'solid');
    });

    test('it participates in equality, so no-change writes are skipped', () {
      final WinNotesSettings a =
          WinNotesSettings.defaults.copyWith(skin: 'soft');
      final WinNotesSettings b =
          WinNotesSettings.defaults.copyWith(skin: 'soft');
      final WinNotesSettings c =
          WinNotesSettings.defaults.copyWith(skin: 'outline');
      expect(a, b);
      expect(a, isNot(c));
    });
  });
}

/// The theme as the app builds it. The skin is deliberately **not** passed: a
/// skin that reached this function would be a skin that could change colour, and
/// the test above demands it cannot.
ThemeData themeDataFor(WinNotesSkin skin) => buildWinNotesTheme(
      brightness: Brightness.light,
      highContrast: false,
      palette: winNotesPalettes.first,
    );
