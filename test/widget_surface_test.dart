import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/src/data/note.dart';
import 'package:win_notes/src/ui/theme.dart';
import 'package:win_notes/src/ui/widget/widget_note_card.dart';

/// Rendering tests for the widget card, which is where the project's one real
/// design decision lives: one focused card rendered large, everything else
/// compact, in a single scrolling column.
///
/// PROJECT.md calls mixed note sizes "a design problem rather than a technical
/// one". These tests pin the answer down so a later tweak cannot quietly break
/// the reason it works.
void main() {
  Note note(String title, String body) => Note(
        id: title,
        title: title,
        body: body,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  Future<void> pump(
    WidgetTester tester, {
    required Note theNote,
    required bool focused,
    required bool roomy,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWinNotesTheme(brightness: brightness, highContrast: false),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              // Room for a large card, or deliberately too small for one.
              width: roomy ? 340 : 170,
              height: roomy ? 400 : 150,
              child: WidgetNoteCard(
                note: theNote,
                focused: focused,
                roomy: roomy,
                dark: brightness == Brightness.dark,
                accent: WinNotesColors.coral,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('the focused card', () {
    testWidgets('shows the title, the body and its line breaks', (tester) async {
      await pump(
        tester,
        theNote: note('Groceries', 'Milk, sourdough\nCheck the bike light'),
        focused: true,
        roomy: true,
      );

      expect(find.text('Groceries'), findsOneWidget);
      expect(find.textContaining('Check the bike light'), findsOneWidget);
    });

    testWidgets('is larger than a compact card', (tester) async {
      await pump(tester, theNote: note('T', 'B'), focused: true, roomy: true);
      final large = tester.widget<Text>(find.text('T'));
      await pump(tester, theNote: note('T', 'B'), focused: false, roomy: true);
      final small = tester.widget<Text>(find.text('T'));

      expect(large.style!.fontSize, greaterThan(small.style!.fontSize!));
    });

    testWidgets('says so when a note has no body yet', (tester) async {
      await pump(tester, theNote: note('Fresh', ''), focused: true, roomy: true);
      expect(find.text('No text yet'), findsOneWidget);
    });

    testWidgets('falls back to a placeholder when untitled', (tester) async {
      await pump(tester, theNote: note('', 'some text'), focused: true, roomy: true);
      expect(find.text('Untitled note'), findsOneWidget);
    });
  });

  group('a compact card', () {
    testWidgets('collapses line breaks so previews stay one paragraph',
        (tester) async {
      await pump(
        tester,
        theNote: note('Ideas', 'first line\nsecond line'),
        focused: false,
        roomy: true,
      );
      final preview = tester.widget<Text>(find.textContaining('first line'));
      expect(preview.data, isNot(contains('\n')));
    });

    testWidgets('shows a preview even with no body', (tester) async {
      await pump(tester, theNote: note('Empty', ''), focused: false, roomy: true);
      // A compact card omits the placeholder; it just shows the title alone.
      expect(find.text('Empty'), findsOneWidget);
    });
  });

  group('a widget too small for a large card', () {
    testWidgets('renders every card compact', (tester) async {
      await pump(
        tester,
        theNote: note('Groceries', 'a long body line of text'),
        focused: true,
        roomy: false,
      );
      final focused = tester.widget<Text>(find.text('Groceries'));
      // Same size as any other card, because there is no room to differ.
      expect(focused.style!.fontSize, 13);
    });
  });

  testWidgets('is announced as one actionable thing, not loose text',
      (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWinNotesTheme(
          brightness: Brightness.light,
          highContrast: false,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              height: 400,
              child: WidgetNoteCard(
                note: note('Groceries', 'Milk'),
                focused: true,
                roomy: true,
                dark: false,
                accent: WinNotesColors.coral,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );

    // The card is a button whose name includes the title. Matching on a prefix
    // rather than the whole label, because the body text is merged into the same
    // node and that is the intended behaviour: one item to focus, not three.
    expect(
      find.bySemanticsLabel(RegExp('^Groceries')),
      findsOneWidget,
    );

    await tester.tap(find.byType(WidgetNoteCard));
    expect(taps, 1, reason: 'the whole card is the target, not just its text');
    handle.dispose();
  });
}