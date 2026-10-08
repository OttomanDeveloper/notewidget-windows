// That a design reaches the **card it is supposed to become**.
//
// The gap `skin_applied_test` was written for, applied to designs.
// `widget_design_test` proves the model is right and the picker chips report -
// and with the wiring broken the whole suite would stay green, because nothing
// asserts that Paper's rules, the Stamp's caps or the Ticket's perforations are
// ever drawn. A control that does nothing looks exactly like a control whose
// effect never reaches the thing it names.
//
// So the assertions here read the **rendered** values: the painted radius, the
// box shadow, the rotation, the typeface reaching the text, and the edge painter
// that only exists if the design asked for one.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart';
import 'package:win_notes/core/theme/theme.dart';
import 'package:win_notes/core/widgets/completion_toggle/completion_toggle.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/widget/domain/widget_design.dart';
import 'package:win_notes/features/widget/presentation/providers/widget_providers.dart';
import 'package:win_notes/features/widget/presentation/widgets/design_edge_painter/design_edge_painter.dart';
import 'package:win_notes/features/widget/presentation/widgets/designed_note/designed_note.dart';
import 'package:win_notes/features/widget/presentation/widgets/widget_note_card/widget_note_card.dart';

Note note() => Note(
      id: 'n1',
      title: 'Shopping',
      body: 'Milk\nBread\n**Coffee**',
      markdown: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

Future<void> pumpDesign(
  WidgetTester tester,
  WidgetDesign? design, {
  bool large = true,
  bool focused = true,
}) async {
  final Note theNote = note();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        widgetNoteByIdProvider(theNote.id).overrideWithValue(theNote),
      ],
      child: MaterialApp(
        theme: buildWinNotesTheme(brightness: Brightness.light, highContrast: false),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              height: 320,
              child: DesignedNote(
                note: theNote,
                design: design,
                accent: WinNotesColors.coral,
                titleColor: const Color(0xFF1B1B1B),
                bodyColor: const Color(0xFF3A3A3A),
                mutedColor: const Color(0xFF6B6B6B),
                large: large,
                done: false,
                focused: focused,
                onTap: () {},
                onToggleCompleted: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The radius actually painted, which is the number a person sees as a corner.
double? paintedRadius(WidgetTester tester) {
  final Iterable<Container> containers = tester.widgetList<Container>(
    find.descendant(of: find.byType(DesignedNote), matching: find.byType(Container)),
  );
  for (final Container c in containers) {
    final Decoration? d = c.decoration;
    if (d is BoxDecoration && d.borderRadius is BorderRadius) {
      return (d.borderRadius! as BorderRadius).topLeft.x;
    }
  }
  return null;
}

/// The content padding's bottom, which is where a bottom edge is drawn.
///
/// Matched on the `Padding` that wraps the content `Row`, because that is the
/// box the edge painter overlaps. The card's own padding used to sit *outside*
/// the painted area, which is why an edge drawn at the bottom of the painter
/// landed on the last line of text.
double bottomPadding(WidgetTester tester) {
  final Iterable<Padding> pads = tester.widgetList<Padding>(
    find.descendant(of: find.byType(DesignedNote), matching: find.byType(Padding)),
  );
  for (final Padding p in pads) {
    if (p.child is Row) return p.padding.resolve(TextDirection.ltr).bottom;
  }
  return 0;
}

bool paintedShadow(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(of: find.byType(DesignedNote), matching: find.byType(Container)),
    )
    .map((Container c) => c.decoration)
    .whereType<BoxDecoration>()
    .any((BoxDecoration d) => d.boxShadow != null && d.boxShadow!.isNotEmpty);

/// Every rotation actually applied, as an angle in radians.
///
/// `Transform.rotate` stores a **matrix**, not an angle, and `Matrix4.storage`
/// is column-major - the sine lives at index 1, not 2, which cost a run of this
/// test before it was checked. Only near-identity `cos` counts, so the other
/// transforms a card sits inside cannot be mistaken for a design's tilt.
Set<double> paintedTilts(WidgetTester tester) => tester
    .widgetList<Transform>(find.byType(Transform))
    .map((Transform t) => t.transform)
    .where((Matrix4 m) => (m.storage[0].abs() - 1).abs() < 0.01 && m.storage[0] > 0)
    .map((Matrix4 m) => math.asin(m.storage[1].clamp(-1.0, 1.0)))
    .toSet();

/// The typefaces actually applied inside the card.
///
/// Read from `DefaultTextStyle` as well as `Text`, because a Markdown note
/// renders through `MarkdownText` and never produces a `Text` widget at all -
/// probing only `Text` would report an empty set for every Markdown note and
/// quietly pass.
Set<String> paintedFamilies(WidgetTester tester) {
  final Set<String> found = <String>{};
  for (final DefaultTextStyle s in tester.widgetList<DefaultTextStyle>(
    find.descendant(of: find.byType(DesignedNote), matching: find.byType(DefaultTextStyle)),
  )) {
    final String? family = s.style.fontFamily;
    if (family != null && family.isNotEmpty) found.add(family);
  }
  for (final Text t in tester.widgetList<Text>(
    find.descendant(of: find.byType(DesignedNote), matching: find.byType(Text)),
  )) {
    final String? family = t.style?.fontFamily;
    if (family != null && family.isNotEmpty) found.add(family);
  }
  return found;
}

Set<DesignEdge> paintedEdges(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(of: find.byType(DesignedNote), matching: find.byType(CustomPaint)),
    )
    .map((CustomPaint p) => p.painter)
    .whereType<DesignEdgePainter>()
    .map((DesignEdgePainter p) => p.edge)
    .toSet();

void main() {
  group('a design reaches the drawn card', () {
    testWidgets('the corners come from the design', (WidgetTester tester) async {
      await pumpDesign(tester, designById('paper'));
      expect(paintedRadius(tester), designById('paper')!.cornerRadius);

      await pumpDesign(tester, designById('soft'));
      expect(paintedRadius(tester), 20);

      await pumpDesign(tester, designById('stamp'));
      expect(paintedRadius(tester), 1);
    });

    testWidgets('the typeface comes from the design', (WidgetTester tester) async {
      await pumpDesign(tester, designById('paper'));
      expect(paintedFamilies(tester), contains('Segoe Print'),
          reason: 'Paper is written by hand or not it is not paper');

      await pumpDesign(tester, designById('ticket'));
      expect(paintedFamilies(tester), contains('Consolas'));

      await pumpDesign(tester, designById('soft'));
      expect(paintedFamilies(tester), contains('Segoe UI'));
    });

    testWidgets('the edge painter is the design it asked for',
        (WidgetTester tester) async {
      for (final WidgetDesign d in widgetDesigns) {
        await pumpDesign(tester, d);
        expect(paintedEdges(tester), contains(d.edge),
            reason: '${d.id} asks for ${d.edge} and something else was painted');
      }
    });

    testWidgets('the shadow is the design and not always on',
        (WidgetTester tester) async {
      await pumpDesign(tester, designById('paper'));
      expect(paintedShadow(tester), isTrue, reason: 'paper lifts off the desktop');

      await pumpDesign(tester, designById('stamp'));
      expect(paintedShadow(tester), isFalse,
          reason: 'ink is on the desktop, not above it');

      await pumpDesign(tester, designById('receipt'));
      expect(paintedShadow(tester), isFalse);
    });

    testWidgets('the tilt is the design and not always square',
        (WidgetTester tester) async {
      await pumpDesign(tester, designById('stamp'));
      expect(paintedTilts(tester), contains(closeTo(designById('stamp')!.tilt, 0.001)));

      await pumpDesign(tester, designById('ticket'));
      expect(paintedTilts(tester), isEmpty, reason: 'a ticket is not crooked');
    });

    testWidgets('an edge drawn at the bottom leaves room for itself',
        (WidgetTester tester) async {
      // Found on a release build: the ticket's perforations and the receipt's
      // torn edge were drawn across the last line of the body, because the
      // painter fills the card and the card had no space set aside for it.
      // Stamp is the baseline: a plain edge and a small radius, so it shares the
      // compact vertical padding with the ticket and the receipt. Soft cannot be
      // the baseline - its radius makes it roomy, so its base padding is larger
      // for reasons that have nothing to do with its edge.
      await pumpDesign(tester, designById('stamp'));
      final double plain = bottomPadding(tester);

      await pumpDesign(tester, designById('paper'));
      expect(bottomPadding(tester), plain,
          reason: 'ruled lines are full-bleed background, not a bottom edge');

      await pumpDesign(tester, designById('ticket'));
      expect(bottomPadding(tester), greaterThan(plain),
          reason: 'the perforation would otherwise cut through the text');

      await pumpDesign(tester, designById('receipt'));
      expect(bottomPadding(tester), greaterThan(plain),
          reason: 'the torn edge would otherwise slice through the text');
    });

    testWidgets('the stamp sets its body in caps too, not just the title',
        (WidgetTester tester) async {
      // Found on a release build: the title was capitalised and the body was not,
      // which read as an oversight rather than a stamp.
      await pumpDesign(tester, designById('stamp'));
      final List<String> shown = <String>[
        for (final Text t in tester.widgetList<Text>(
          find.descendant(of: find.byType(DesignedNote), matching: find.byType(Text)),
        ))
          t.data ?? '',
        for (final RichText r in tester.widgetList<RichText>(
          find.descendant(of: find.byType(DesignedNote), matching: find.byType(RichText)),
        ))
          r.text.toPlainText(),
      ].where((String s) => s.trim().isNotEmpty).toList();

      expect(shown, isNotEmpty, reason: 'the stamp must draw the note at all');
      for (final String s in shown) {
        expect(s, s.toUpperCase(),
            reason: 'a stamp is pressed in capitals, so "$s" should be too');
      }
      expect(
        shown.any((String s) => s.contains('MILK')),
        isTrue,
        reason: 'the body has to be capitalised, not only the title',
      );
    });

    testWidgets('the other designs keep the body as written',
        (WidgetTester tester) async {
      await pumpDesign(tester, designById('ticket'));
      expect(find.text('SHOPPING'), findsNothing);
      expect(
        tester
            .widgetList<RichText>(
              find.descendant(of: find.byType(DesignedNote), matching: find.byType(RichText)),
            )
            .map((RichText r) => r.text.toPlainText())
            .join(' '),
        contains('Milk'),
        reason: 'only the stamp presses type in capitals',
      );
    });

    testWidgets('the stamp sets its type in caps and the others do not',
        (WidgetTester tester) async {
      await pumpDesign(tester, designById('stamp'));
      expect(
        find.text('SHOPPING'),
        findsOneWidget,
        reason: 'a stamp is pressed, and pressed type is capital',
      );

      await pumpDesign(tester, designById('ticket'));
      expect(find.text('Shopping'), findsOneWidget);
      expect(find.text('SHOPPING'), findsNothing);
    });
  });

  group('the built-in look is untouched by any of this', () {
    testWidgets('no design paints the built-in radius, shadow and tilt',
        (WidgetTester tester) async {
      await pumpDesign(tester, null);
      expect(paintedRadius(tester), 10);
      expect(paintedShadow(tester), isFalse);
      expect(paintedTilts(tester), isEmpty, reason: 'the built-in card is square');
    });

    testWidgets('the built-in card is still a different widget from a design',
        (WidgetTester tester) async {
      // The surface chooses between two widgets rather than branching inside
      // one, and this is what would catch that choice being lost: a card with
      // `WidgetNoteCard` where a design was asked for is the built-in look
      // wearing a design's name.
      await pumpDesign(tester, designById('paper'));
      expect(find.byType(WidgetNoteCard), findsNothing);
      expect(find.byType(DesignedNote), findsOneWidget);
    });
  });

  group('the affordances a design replaced still work', () {
    testWidgets('the tick is still there', (WidgetTester tester) async {
      await pumpDesign(tester, designById('ticket'));
      expect(find.byType(CompletionToggle), findsOneWidget);
    });

    testWidgets('a tap still reports', (WidgetTester tester) async {
      int taps = 0;
      final Note theNote = note();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            widgetNoteByIdProvider(theNote.id).overrideWithValue(theNote),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 340,
                height: 320,
                child: DesignedNote(
                  note: theNote,
                  design: designById('stamp'),
                  accent: WinNotesColors.coral,
                  titleColor: const Color(0xFF1B1B1B),
                  bodyColor: const Color(0xFF3A3A3A),
                  mutedColor: const Color(0xFF6B6B6B),
                  large: true,
                  done: false,
                  focused: true,
                  onTap: () => taps++,
                  onToggleCompleted: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DesignedNote));
      await tester.pumpAndSettle();
      expect(taps, 1, reason: 'the design replaced the card, not the tap target');
    });
  });
}