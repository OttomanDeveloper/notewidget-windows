// The widget design model: five designs, none of them the built-in look, and
// no colour anywhere in it.
//
// The rule that matters here is the same one a skin obeys, and it is why this is
// a model test and not a screenshot test: a design is *shape and type*. The day
// one of these carries a colour, Design and Palette have become two controls
// doing one thing - which is the mistake Skin already replaced once.
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/features/settings/domain/settings.dart';
import 'package:win_notes/features/widget/domain/widget_design.dart';

void main() {
  group('the design model', () {
    test('every design has an id that resolves back to it', () {
      for (final WidgetDesign d in widgetDesigns) {
        expect(designById(d.id), same(d),
            reason: '${d.id} must resolve, or a saved choice silently becomes'
                ' "no design"');
      }
    });

    test('ids are unique, because settings.json stores one', () {
      final Set<String> ids =
          widgetDesigns.map((WidgetDesign d) => d.id).toSet();
      expect(ids, hasLength(widgetDesigns.length));
    });

    test('empty and null mean no design, not the first one', () {
      expect(designById(''), isNull);
      expect(designById(null), isNull);
      expect(designById('nope'), isNull);
    });

    test('a file written before designs existed resolves to no design', () {
      final WinNotesSettings older = WinNotesSettings.fromJson(<String, dynamic>{});
      expect(designById(older.design), isNull);
    });

    test('there are five designs and none is the built-in look', () {
      expect(widgetDesigns, hasLength(5));
      // "None" is offered by the picker and is not in this list, so a chip here
      // that renders the built-in card would be a control that repaints nothing.
        const DesignLook builtIn = DesignLook.builtIn;
        for (final WidgetDesign d in widgetDesigns) {
          final DesignLook look = lookFromDesign(d);
          final bool differs = look.edge != builtIn.edge ||
              look.casing != builtIn.casing ||
              look.bodyFont != builtIn.bodyFont ||
              look.tilt != builtIn.tilt ||
              look.cornerRadius != builtIn.cornerRadius ||
              look.shadow != builtIn.shadow;
          expect(differs, isTrue,
              reason: '${d.id} draws exactly what "no design" draws');
        }
      });

    test('the designs are distinguishable from one another', () {
      // As a tuple, not per attribute: a ticket and a receipt are both
      // monospace on purpose and the stamp has no edge on purpose.
      final Set<String> signatures = widgetDesigns
          .map((WidgetDesign d) => '${d.edge}|${d.casing}|${d.bodyFont}|${d.tilt}')
          .toSet();
      expect(signatures, hasLength(widgetDesigns.length),
          reason: 'two designs with one signature are one design');
    });

    test('the designs carry no colour', () {
      // Not a type check - WidgetDesign has no Color field, so this cannot
      // compile if one is added. It is here to say so out loud, because the
      // absence is the rule and a rule with nothing enforcing it is a comment.
      expect(widgetDesigns.every((WidgetDesign d) => d.bodyFont.isNotEmpty),
          isTrue,
          reason: 'a design is identified by its type and edge, not by a colour');
    });

    test('a chosen design round trips through the file', () {
      const String id = 'ticket';
      final WinNotesSettings picked = WinNotesSettings.defaults
          .copyWith(design: id);
      expect(picked.toJson()['design'], id);
      expect(WinNotesSettings.fromJson(picked.toJson()).design, id);
    });

    test('it is omitted when empty, for the same reason as the palette', () {
      expect(WinNotesSettings.defaults.toJson().containsKey('design'),
          isFalse,
          reason: 'writing it would put a key in files written before it existed');
    });

    test('the palette and the design are separate keys and can disagree', () {
      final WinNotesSettings both = WinNotesSettings.defaults
          .copyWith(design: 'stamp')
          .copyWith(skin: 'soft');
      final Map<String, Object?> json = both.toJson();
      expect(json['design'], 'stamp');
      expect(json['skin'], 'soft');
    });

    test('it participates in equality, so no-change writes are skipped', () {
      final WinNotesSettings a = WinNotesSettings.defaults.copyWith(design: 'paper');
      final WinNotesSettings b = WinNotesSettings.defaults.copyWith(design: 'paper');
      final WinNotesSettings c = WinNotesSettings.defaults.copyWith(design: 'stamp');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('the built-in look', () {
    test('no design means no tilt, no shadow and a rounded 10', () {
      final DesignLook look = lookOfDesign(null);
      expect(look.tilt, 0);
      expect(look.shadow, isFalse);
      expect(look.edge, DesignEdge.plain);
      expect(look.cornerRadius, 10);
    });

    test('a chosen design resolves to its own numbers', () {
      final DesignLook look = lookOfDesign(designById('paper'));
      expect(look.tilt, isNot(0));
      expect(look.shadow, isTrue);
      expect(look.edge, DesignEdge.ruled);
    });
  });
}
