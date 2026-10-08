// The preview pane must not re-render the document on a keystroke.
//
// The report this answers: "if I use the demo markdown and try to add something
// in there, the editor and preview both lag to display new changes". Measured on
// the 1012-line demo, one keystroke costs 64-169 ms, and none of it is the
// TextField - which is 6-10 ms on its own, and 3 ms for a plain keystroke.
//
// The cost was `PreviewPane`. Its content sits behind a ValueListenableBuilder on
// the debounced source, which looks like it only renders when the source changes
// - but `build` runs on every parent rebuild whether the listenable fired or not.
// `NoteEditorPane` watches the whole notes state and rebuilds on every keystroke,
// so ~500 blocks were re-split and re-rendered per character, for text that
// nothing had changed.
//
// The fix returns the identical composed widget when nothing that draws has
// changed, which is what makes Flutter skip the subtree. So the invariant is
// *identity*: same inputs must hand back the same widget, different inputs must
// not. That is asserted here rather than a timing, because a timing assertion
// would pass on a fast machine and fail on a slow one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/theme/theme.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/notes/presentation/widgets/preview_pane/preview_pane.dart';

Note noteWith(String body, {bool completed = false}) => Note(
      id: 'n1',
      title: 'Demo',
      body: body,
      markdown: true,
      completedAt: completed ? DateTime.utc(2026) : null,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

/// A parent that rebuilds on demand without changing anything the pane draws,
/// which is exactly what a keystroke does to the editor around it.
class _Parent extends StatelessWidget {
  const _Parent({required this.note, required this.source, required this.held});

  final Note note;
  final ValueNotifier<String> source;
  final int held;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: buildWinNotesTheme(brightness: Brightness.light, highContrast: false),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: PreviewPane(note: note, previewSource: source),
          ),
        ),
      );
}

void main() {
  group('a parent rebuild does not re-render the document', () {
    testWidgets('the same source hands back the identical widget',
        (WidgetTester tester) async {
      const String body = '# One\n\nSome **bold** text.\n\n- a\n- b\n';
      final ValueNotifier<String> source = ValueNotifier<String>(body);
      addTearDown(source.dispose);

      Widget build(int revision, {String text = body}) => _Parent(
            note: noteWith(text),
            source: source,
            held: revision,
          );

      await tester.pumpWidget(build(0));
      await tester.pump();
      final Widget first = tester.widget(find.byType(Scrollbar));

      // A rebuild carrying a different Note whose *body* is the only change -
      // what every keystroke does. The pane draws none of it.
      await tester.pumpWidget(build(1));
      await tester.pump();
      expect(
        identical(tester.widget(find.byType(Scrollbar)), first),
        isTrue,
        reason: 'an unchanged source must hand back the identical widget, or the '
            'document re-renders per keystroke',
      );
    });

    testWidgets('a changed source does re-render', (WidgetTester tester) async {
      const String body = '# One\n\nSome **bold** text.\n';
      final ValueNotifier<String> source = ValueNotifier<String>(body);
      addTearDown(source.dispose);

      Widget build(int revision) => _Parent(
            note: noteWith(body),
            source: source,
            held: revision,
          );

      await tester.pumpWidget(build(0));
      await tester.pump();
      final Widget first = tester.widget(find.byType(Scrollbar));

      // Through the notifier, because that - not `note.body` - is what the pane
      // draws. Editing the note alone must change nothing here, and the test
      // below that says so is the one that caught it being confused.
      source.value = '$body\n## Two\n';
      await tester.pumpWidget(build(1));
      await tester.pump();
      expect(
        identical(tester.widget(find.byType(Scrollbar)), first),
        isFalse,
        reason: 'new text must actually render - a cache that never misses is a '
            'blank pane, not a fast one',
      );
      expect(find.textContaining('Two', findRichText: true), findsWidgets);
    });

    testWidgets('editing the note alone changes nothing the pane draws',
        (WidgetTester tester) async {
      const String body = '# One\n\nSome **bold** text.\n';
      final ValueNotifier<String> source = ValueNotifier<String>(body);
      addTearDown(source.dispose);

      Widget build(String noteBody) => _Parent(
            note: noteWith(noteBody),
            source: source,
            held: noteBody.length,
          );

      await tester.pumpWidget(build(body));
      await tester.pump();
      final Widget first = tester.widget(find.byType(Scrollbar));

      // The typing path: the note changes on every keystroke and the debounced
      // source does not. This is the case the fix exists for.
      await tester.pumpWidget(build('$body typed more'));
      await tester.pump();
      expect(
        identical(tester.widget(find.byType(Scrollbar)), first),
        isTrue,
        reason: 'the preview follows the debounced source, not the note',
      );
      expect(find.textContaining('typed more'), findsNothing);
    });
  });

  group('what invalidates the cache', () {
    // Each of these changes something the pane draws, so each must miss. A cache
    // keyed on too little is a pane that silently ignores a real change, which
    // is worse than the lag it was meant to remove.
    testWidgets('the font size', (WidgetTester tester) async {
      const String body = '# One\n\nText.\n';
      final ValueNotifier<String> source = ValueNotifier<String>(body);
      addTearDown(source.dispose);

      Widget build(int size) => MaterialApp(
            theme: buildWinNotesTheme(
              brightness: Brightness.light,
              highContrast: false,
            ),
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 700,
                child: PreviewPane(
                  note: noteWith(body),
                  previewSource: source,
                  fontSize: size,
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(0));
      await tester.pump();
      final Widget first = tester.widget(find.byType(Scrollbar));

      await tester.pumpWidget(build(18));
      await tester.pump();
      expect(identical(tester.widget(find.byType(Scrollbar)), first), isFalse,
          reason: 'a font step has to reach the renderer');
    });

    testWidgets('the completion state', (WidgetTester tester) async {
      const String body = '# One\n\nText.\n';
      final ValueNotifier<String> source = ValueNotifier<String>(body);
      addTearDown(source.dispose);

      Widget build({required bool completed}) => MaterialApp(
            theme: buildWinNotesTheme(
              brightness: Brightness.light,
              highContrast: false,
            ),
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 700,
                child: PreviewPane(
                  note: noteWith(body, completed: completed),
                  previewSource: source,
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(completed: false));
      await tester.pump();
      final Widget first = tester.widget(find.byType(Scrollbar));

      await tester.pumpWidget(build(completed: true));
      await tester.pump();
      expect(
        identical(tester.widget(find.byType(Scrollbar)), first),
        isFalse,
        reason: 'finishing a note strikes it through, so the cache must miss',
      );
    });

    testWidgets('the theme', (WidgetTester tester) async {
      const String body = '# One\n\nText.\n';
      final ValueNotifier<String> source = ValueNotifier<String>(body);
      addTearDown(source.dispose);

      Widget build(Brightness brightness) => MaterialApp(
            theme: buildWinNotesTheme(brightness: brightness, highContrast: false),
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 700,
                child: PreviewPane(note: noteWith(body), previewSource: source),
              ),
            ),
          );

      await tester.pumpWidget(build(Brightness.light));
      await tester.pump();
      final Widget first = tester.widget(find.byType(Scrollbar));

      await tester.pumpWidget(build(Brightness.dark));
      // Past the end of AnimatedTheme's lerp: at t=0 the theme is still the old
      // one, and a test that samples frame zero is asserting nothing.
      await tester.pump(const Duration(milliseconds: 400));
      expect(identical(tester.widget(find.byType(Scrollbar)), first), isFalse,
          reason: 'a palette change has to reach the pane');
    });
  });
}