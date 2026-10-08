// That a skin reaches the **cards it is supposed to shape**.
//
// This is the test the feature needed and did not have. `skin_test` proves the
// model is right, `skin_picker_test` proves the chips draw and report - and with
// the wiring broken, the whole suite stayed green, because nothing asserted that
// a card's corners came from the skin at all.
//
// That is the same gap as the original complaint: "there is no difference between
// the colours and the skin". A control that does nothing looks exactly like a
// control whose effect never reaches the thing it names.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/src/framework.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/theme/skin.dart';
import 'package:win_notes/core/theme/theme.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/notes/presentation/widgets/note_list_item/note_list_item.dart';
import 'package:win_notes/features/widget/presentation/providers/widget_providers.dart';
import 'package:win_notes/features/widget/presentation/widgets/widget_note_card/widget_note_card.dart';

Note note(String id) => Note(
      id: id,
      title: 'Note',
      body: 'Body',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

Future<void> pumpCard(WidgetTester tester, {WinNotesSkin? skin, bool focused = true}) async {
  final Note theNote = note('n1');
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
              height: 300,
              child: WidgetNoteCard(
                noteId: theNote.id,
                focused: focused,
                roomy: true,
                skin: skin,
                dark: false,
                accent: WinNotesColors.coral,
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

Future<void> pumpRow(WidgetTester tester, {WinNotesSkin? skin, bool selected = true}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWinNotesTheme(brightness: Brightness.light, highContrast: false),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: NoteListItem(
            note: note('n1'),
            selected: selected,
            skin: skin,
            onTap: () {},
            onToggleCompleted: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The radii actually painted inside [finder].
Set<double> paintedRadii(WidgetTester tester, Finder finder) => tester
    .widgetList<Container>(find.descendant(of: finder, matching: find.byType(Container)))
    .map((Container c) => c.decoration)
    .whereType<BoxDecoration>()
    .map((BoxDecoration d) => d.borderRadius)
    .whereType<BorderRadius>()
    .map((BorderRadius r) => r.topLeft.x)
    .toSet();

double paddingOf(WidgetTester tester, Finder finder) => tester
    .widgetList<Container>(find.descendant(of: finder, matching: find.byType(Container)))
    .map((Container c) => c.padding)
    .whereType<EdgeInsetsGeometry>()
    .first
    .vertical;

void main() {
  group('a skin reaches the widget card', () {
    testWidgets('the card corners come from the skin', (WidgetTester tester) async {
      await pumpCard(tester, skin: skinById('sharp'));
      expect(paintedRadii(tester, find.byType(WidgetNoteCard)), contains(0.0),
          reason: 'Sharp is square and the card should be too');

      await pumpCard(tester, skin: skinById('soft'));
      expect(paintedRadii(tester, find.byType(WidgetNoteCard)), contains(18.0),
          reason: 'Soft declares 18 and the card should follow');

      await pumpCard(tester, skin: null);
      expect(paintedRadii(tester, find.byType(WidgetNoteCard)), contains(10.0),
          reason: 'no skin means the built-in 10');
    });

    testWidgets('the card padding comes from the skin''s density',
        (WidgetTester tester) async {
      await pumpCard(tester, skin: skinById('sharp'));
      final double tight = paddingOf(tester, find.byType(WidgetNoteCard));

      await pumpCard(tester, skin: null);
      final double builtIn = paddingOf(tester, find.byType(WidgetNoteCard));

      await pumpCard(tester, skin: skinById('soft'));
      final double loose = paddingOf(tester, find.byType(WidgetNoteCard));

      expect(tight, lessThan(builtIn));
      expect(loose, greaterThan(builtIn));
    });

    testWidgets('the focus marker is the skin and not always a bar',
        (WidgetTester tester) async {
      // A bar skin draws an edge as a child; an outline skin draws a border.
      await pumpCard(tester, skin: skinById('outline'));
      final Iterable<Container> outlined = tester
          .widgetList<Container>(find.descendant(
              of: find.byType(WidgetNoteCard), matching: find.byType(Container)))
          .where((Container c) =>
              c.decoration is BoxDecoration &&
              ((c.decoration! as BoxDecoration).border?.top.color ?? Colors.transparent) ==
                  WinNotesColors.coral);
      expect(outlined, isNotEmpty, reason: 'Outline draws a full border');
    });
  });

  group('a skin reaches the editor list', () {
    testWidgets('the row corners come from the skin', (WidgetTester tester) async {
      await pumpRow(tester, skin: skinById('sharp'));
      expect(paintedRadii(tester, find.byType(NoteListItem)), contains(0.0));

      await pumpRow(tester, skin: skinById('soft'));
      expect(paintedRadii(tester, find.byType(NoteListItem)), contains(18.0));

      await pumpRow(tester, skin: null);
      expect(paintedRadii(tester, find.byType(NoteListItem)), contains(10.0));
    });

    testWidgets('the row padding comes from the skin', (WidgetTester tester) async {
      await pumpRow(tester, skin: skinById('sharp'));
      final double tight = paddingOf(tester, find.byType(NoteListItem));

      await pumpRow(tester, skin: null);
      final double builtIn = paddingOf(tester, find.byType(NoteListItem));

      expect(tight, lessThan(builtIn));
    });
  });
}
