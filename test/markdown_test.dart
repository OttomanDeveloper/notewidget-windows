import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart';
import 'package:win_notes/core/utils/atomic_json_file.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/notes/data/notes_repository.dart';
import 'package:win_notes/core/widgets/markdown_text/markdown_text.dart';
import 'package:win_notes/core/widgets/markdown_density/markdown_density.dart';
import 'package:win_notes/features/notes/presentation/widgets/note_editor_pane/note_editor_pane.dart';
import 'package:win_notes/features/notes/presentation/widgets/markdown_toggle_button/markdown_toggle_button.dart';
import 'package:win_notes/features/notes/presentation/widgets/note_list_pane/note_list_pane.dart';
import 'package:win_notes/core/theme/theme.dart';
import 'package:win_notes/features/widget/presentation/providers/widget_providers.dart';
import 'package:win_notes/features/widget/presentation/widgets/widget_note_card/widget_note_card.dart';

import 'helpers/file_io.dart';
import 'helpers/provider_harness.dart';

/// A card at the size that decides its budget: `roomy` for the large card, and
/// deliberately too small for one otherwise, which is what a compact card is.
///
/// At the top level rather than inside a group, because the renderer's own
/// tests need it: what a heading costs a card is a decision the card makes.
Future<void> pumpCard(
  WidgetTester tester,
  Note theNote, {
  bool roomy = true,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        widgetNoteByIdProvider(theNote.id).overrideWithValue(theNote),
      ],
      child: MaterialApp(
        theme: buildWinNotesTheme(
          brightness: brightness,
          highContrast: false,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: roomy ? 340 : 170,
              height: roomy ? 400 : 150,
              child: WidgetNoteCard(
                noteId: theNote.id,
                focused: true,
                roomy: roomy,
                dark: brightness == Brightness.dark,
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
  await tester.pump();
}

void main() {
  Note note(String title, String body, {bool markdown = false}) => Note(
        id: title,
        title: title,
        body: body,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        markdown: markdown,
      );

  Future<void> pumpMarkdown(
    WidgetTester tester,
    String source, {
    MarkdownDensity density = MarkdownDensity.editor,
    int? maxLines,
    double? maxHeight,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWinNotesTheme(
          brightness: Brightness.light,
          highContrast: false,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 500,
            child: SingleChildScrollView(
              child: MarkdownText(
                source: source,
                color: const Color(0xFF23202E),
                accent: const Color(0xFFE8551D),
                density: density,
                maxLines: maxLines,
                maxHeight: maxHeight,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('the markdown flag on a note', () {
    test('is omitted from the file when off, so old notes stay untouched', () {
      expect(note('a', 'b').toJson().containsKey('markdown'), isFalse);
      expect(note('a', 'b', markdown: true).toJson()['markdown'], isTrue);
    });

    test('absent means off', () {
      // Every file written before this feature existed, and every plain note
      // written after it.
      final Note loaded = Note.fromJson(<String, dynamic>{
        'id': 'a',
        'title': 't',
        'body': 'b',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });
      expect(loaded.markdown, isFalse);
    });

    test('only a literal true turns it on', () {
      // A hand-edited "yes" or 1 must not produce a note the renderer has never
      // been asked to handle.
      for (final Object? value in <Object?>['yes', 1, 'true', null]) {
        final Note loaded = Note.fromJson(<String, dynamic>{
          'id': 'a',
          'title': 't',
          'body': 'b',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'markdown': value,
        });
        expect(loaded.markdown, isFalse, reason: 'markdown: $value');
      }
    });

    test('copy carries it, because undo restores a note wholesale', () {
      expect(note('a', 'b', markdown: true).copy().markdown, isTrue);
      expect(note('a', 'b').copy().markdown, isFalse);
    });

    test('the body is never rewritten by turning it on or off', () {
      // The whole promise of the flag: it decides presentation, not content.
      const String source = '# Heading\n\n**bold** and `code`';
      Note n = note('t', source);
      n = n.copyWith(markdown: true);
      expect(n.body, source, reason: 'switching on must not touch the source');
      n = n.copyWith(markdown: false);
      expect(n.body, source, reason: 'and switching off must not either');
    });
  });

  group('the renderer', () {
    testWidgets('bold, italic and strikethrough survive as styles',
        (WidgetTester tester) async {
      await pumpMarkdown(tester, 'a **b** c *d* e ~~f~~ g');

      final List<({GestureRecognizer? recognizer, TextStyle style, String text})> runs = _runs(tester);
      expect(
        runs.any((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'b' && r.style.fontWeight == FontWeight.w700),
        isTrue,
        reason: 'bold',
      );
      expect(
        runs.any((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'd' && r.style.fontStyle == FontStyle.italic),
        isTrue,
        reason: 'italic',
      );
      expect(
        runs.any(
          (({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'f' && r.style.decoration == TextDecoration.lineThrough,
        ),
        isTrue,
        reason: 'strikethrough',
      );
    });

    testWidgets('a heading is larger than the body', (WidgetTester tester) async {
      await pumpMarkdown(tester, '# Big\n\ntext');

      final ({GestureRecognizer? recognizer, TextStyle style, String text}) heading = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'Big');
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) body = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'text');
      expect(heading.style.fontSize, greaterThan(body.style.fontSize!),
          reason: 'an h1 must be bigger than body text');
    });

    testWidgets('an h6 is still not smaller than the body', (WidgetTester tester) async {
      // The floor. Without it the smallest heading renders smaller than the text
      // around it, which inverts the one thing a heading is for.
      await pumpMarkdown(tester, '###### Deep\n\ntext');

      final ({GestureRecognizer? recognizer, TextStyle style, String text}) heading = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'Deep');
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) body = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'text');
      expect(heading.style.fontSize, greaterThanOrEqualTo(body.style.fontSize!));
    });

    testWidgets('only the compact card flattens a heading', (WidgetTester tester) async {
      // A compact card shows the note's title immediately above the body, so a
      // body opening with `# Title` repeats itself. At 1.3x that repeat ate a
      // third of a two-line budget and pushed the content off the end of the
      // card. The large card has seven lines and is the surface you actually
      // read a note on, so it keeps the real scale.
      //
      // Driven through WidgetNoteCard rather than MarkdownText, because the
      // decision belongs to the card: density alone cannot express "two lines"
      // against "seven".
      const String body = '# Release\n\n- [x] one\n- [ ] two';
      final Note n = note('Release checklist', body, markdown: true);

      await pumpCard(tester, n, roomy: false);
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) compact = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'Release');
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) compactBody = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'one');
      expect(compact.style.fontSize, compactBody.style.fontSize,
          reason: 'a heading must not cost a two-line card more than the line '
              'it is');
      expect(compact.style.fontWeight, FontWeight.w700,
          reason: 'it still has to read as a heading');

      await pumpCard(tester, n, roomy: true);
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) large = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'Release');
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) largeBody = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'one');
      expect(large.style.fontSize, greaterThan(largeBody.style.fontSize!));
    });

    testWidgets('editor density still gives a heading its size', (WidgetTester tester) async {
      // The other half of the rule above. Density is about the room available,
      // not a belief that headings are unimportant.
      await pumpMarkdown(tester, '# Release\n\ntext',
          density: MarkdownDensity.editor);

      final ({GestureRecognizer? recognizer, TextStyle style, String text}) heading = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'Release');
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) body = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'text');
      expect(heading.style.fontSize, greaterThan(body.style.fontSize!));
    });

    testWidgets('an explicit heading scale is honoured exactly', (WidgetTester tester) async {
      // Asking for 1.0 must not quietly return 1.05, which is what happens if
      // the floor is left behind when the scale is overridden.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWinNotesTheme(
            brightness: Brightness.light,
            highContrast: false,
          ),
          home: const Scaffold(
            body: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: MarkdownText(
                  source: '# Release\n\ntext',
                  color: Color(0xFF23202E),
                  accent: Color(0xFFE8551D),
                  density: MarkdownDensity.widget,
                  headingScale: 1.0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final ({GestureRecognizer? recognizer, TextStyle style, String text}) heading = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'Release');
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) body = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'text');
      expect(heading.style.fontSize, body.style.fontSize);
    });

    testWidgets('a task list draws a box and keeps the words beside it',
        (WidgetTester tester) async {
      // The parser replaces `[ ]` with an <input> element rather than leaving the
      // characters in the text, so a renderer that looked for the brackets drew
      // a bullet and dropped the item's words on the floor.
      await pumpMarkdown(tester, '- [ ] open\n- [x] done');

      expect(find.textContaining('☐'), findsOneWidget);
      expect(find.textContaining('☑'), findsOneWidget);
      expect(find.textContaining('open'), findsOneWidget);
      expect(find.textContaining('done'), findsOneWidget);
    });

    testWidgets('a task marker is not a control', (WidgetTester tester) async {
      // The one place the renderer refuses to be useful, on purpose: completion
      // is per note here and per line in Markdown, and two sources of truth is
      // worse than one that only looks like the other.
      await pumpMarkdown(tester, '- [ ] open\n- [x] done');

      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('links are styled but cannot be tapped', (WidgetTester tester) async {
      // PROJECT.md: the app does not touch the internet at all. A widget with
      // nowhere to send you has no business pretending otherwise.
      await pumpMarkdown(tester, 'see [the docs](https://example.com) now');

      final ({GestureRecognizer? recognizer, TextStyle style, String text}) link = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'the docs');
      expect(link.style.color, isNotNull);
      expect(link.recognizer, isNull,
          reason: 'a link must carry no gesture recogniser at all');
    });

    testWidgets('inline code is monospace', (WidgetTester tester) async {
      await pumpMarkdown(tester, 'use `dart run` here');

      final ({GestureRecognizer? recognizer, TextStyle style, String text}) code = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'dart run');
      expect(code.style.fontFamily, 'Consolas');
    });

    testWidgets('an image becomes its alt text, never a fetch', (WidgetTester tester) async {
      await pumpMarkdown(tester, '![a chart](https://example.com/x.png) here');

      expect(find.textContaining('a chart'), findsWidgets);
      expect(find.byType(Image), findsNothing,
          reason: 'this app has no network code and must not pretend to');
    });

    testWidgets('raw HTML is text, not markup', (WidgetTester tester) async {
      await pumpMarkdown(tester, '<b>not bold</b> here');

      // The parser hands this back as one literal text run - the brackets are
      // characters, not an element - so the assertion is on the run that
      // contains the words, not on a run of exactly those words.
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) run = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text.contains('not bold'));
      expect(run.style.fontWeight, isNot(FontWeight.w700));
      expect(find.textContaining('<b>'), findsWidgets,
          reason: 'the brackets are shown as the characters they are');
    });

    testWidgets('a horizontal rule draws a divider', (WidgetTester tester) async {
      await pumpMarkdown(tester, 'above\n\n---\n\nbelow');
      expect(find.byType(Divider), findsWidgets);
    });

    testWidgets('a block quote is indented and muted', (WidgetTester tester) async {
      await pumpMarkdown(tester, '> quoted words');
      final ({GestureRecognizer? recognizer, TextStyle style, String text}) run = _runs(tester).firstWhere((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text.contains('quoted'));

      final Container container = tester.widgetList<Container>(find.byType(Container))
          .firstWhere((Container c) => c.decoration is BoxDecoration);
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect((decoration.border as Border).left.width, greaterThan(0));
      expect(run.style.color, isNotNull);
    });

    testWidgets('a fenced block keeps its code and shows the language',
        (WidgetTester tester) async {
      await pumpMarkdown(tester, '```dart\nvoid main() {}\n```');
      expect(find.textContaining('void main() {}'), findsWidgets);
      expect(find.text('dart'), findsOneWidget);
    });

    testWidgets('a nested list is not a flat one', (WidgetTester tester) async {
      await pumpMarkdown(tester, '- outer\n  - inner');
      expect(find.textContaining('outer'), findsOneWidget);
      expect(find.textContaining('inner'), findsOneWidget);
    });

    testWidgets('an ordered list numbers itself', (WidgetTester tester) async {
      await pumpMarkdown(tester, '1. one\n2. two');
      expect(find.textContaining('1.'), findsOneWidget);
      expect(find.textContaining('2.'), findsOneWidget);
    });

    testWidgets('unrecognised content degrades to text, never to nothing',
        (WidgetTester tester) async {
      // The promise that matters most: a note must never render as less than
      // what it says.
      await pumpMarkdown(tester, 'Some perfectly ordinary sentence.');
      expect(find.textContaining('perfectly ordinary'), findsWidgets);
    });

    testWidgets('a code block is clamped and says how much was hidden',
        (WidgetTester tester) async {
      final String long = List.generate(20, (int i) => 'line $i').join('\n');
      await pumpMarkdown(tester, '```\n$long\n```',
          density: MarkdownDensity.widget);

      expect(find.textContaining('more lines'), findsOneWidget,
          reason: 'silently truncating would look like the note is short');
      expect(find.textContaining('line 19'), findsNothing);
    });

    testWidgets('widget density is smaller than editor density',
        (WidgetTester tester) async {
      await pumpMarkdown(tester, 'plain words here',
          density: MarkdownDensity.widget);
      final double? widgetSize = _runs(tester).first.style.fontSize;

      await pumpMarkdown(tester, 'plain words here',
          density: MarkdownDensity.editor);
      final double? editorSize = _runs(tester).first.style.fontSize;

      expect(widgetSize, lessThan(editorSize!));
    });

    testWidgets('an empty source renders nothing rather than throwing',
        (WidgetTester tester) async {
      await pumpMarkdown(tester, '');
      expect(tester.takeException(), isNull);
    });

    testWidgets('malformed syntax does not throw', (WidgetTester tester) async {
      // Half-written Markdown is the normal state of a note being typed.
      for (final String source in <String>[
        '**unclosed',
        '[link](unclosed',
        '```\nunterminated fence',
        '| a | b\n|--',
        '- [ ]',
        '#',
        '> quote\n>> nested',
        '~~~',
        '<div>',
      ]) {
        await pumpMarkdown(tester, source);
        expect(tester.takeException(), isNull, reason: 'source: $source');
      }
    });

    testWidgets('a table is real in the editor and readable text in a card',
        (WidgetTester tester) async {
      const String table = '| a | b |\n|---|---|\n| 1 | 2 |';

      await pumpMarkdown(tester, table, density: MarkdownDensity.editor);
      expect(
        _runs(tester).where((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text.trim() == '1'),
        isNotEmpty,
        reason: 'cells are separate runs, not one blob of pipes',
      );

      await pumpMarkdown(tester, table, density: MarkdownDensity.widget);
      final String cardText = _allText(tester).join(' ');

      // One line per row, cells still separated. Flattening the *grid* is the
      // point; flattening the *cells together* would turn `a | b` into `ab`,
      // which is less than the note said.
      expect(cardText, contains('a | b'));
      expect(cardText, contains('1 | 2'));
      expect(find.byType(RichText), findsWidgets);
    });
  });

  group('the per-note switch', () {
    late TestHarness harness;
    late Notes controller;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.winnotes/shell'),
        (MethodCall call) async => null,
      );
      harness = TestHarness.build();
    });

    tearDown(() async {
      await harness.dispose();
    });

    /// Seeds [notes] into the container's profile and returns the facade.
    ///
    /// The file is written *before* the provider is first read, because a provider
    /// builds on first read and that read is what pulls the file in.
    Future<Notes> load(List<Note> notes) async {
      final NotesRepository repo = NotesRepository(AtomicJsonFile(harness.notesFile));
      await repo.saveNow(notes);
      await harness.notes();
      controller = Notes(harness);
      return controller;
    }

    test('turning it on changes the note and persists', () async {
      await load(<Note>[note('a', '# hi')]);
      expect(controller.notes.single.markdown, isFalse);

      controller.setMarkdown('a', enabled: true);

      expect(controller.notes.single.markdown, isTrue);

      // And it reaches disk, debounce and all.
      final String written = await waitForContent(
        File(harness.notesFile),
        '"markdown": true',
      );
      expect(written, contains('"markdown": true'));
      expect(
        Note.fromJson(
          (jsonDecode(written)['notes'] as List).first as Map<String, dynamic>,
        ).markdown,
        isTrue,
        reason: 'and it reads back as a Markdown note, not as a plain one',
      );
    });

    test('turning it on bumps updatedAt, unlike finishing a task', () async {
      // Finishing a note deliberately does not reorder the list. Switching a
      // note into Markdown *is* an edit - it changes how the note reads - so it
      // earns its place at the top like any other change.
      await load(<Note>[note('a', 'body')]);
      final DateTime before = controller.notes.single.updatedAt;

      controller.setMarkdown('a', enabled: true);
      expect(controller.notes.single.updatedAt.isAfter(before), isTrue);

      await load(<Note>[note('b', 'body')]);
      final DateTime beforeToggle = controller.notes.single.updatedAt;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.toggleCompleted('b');
      expect(controller.notes.single.updatedAt, beforeToggle,
          reason: 'a tick is not an edit');
    });

    test('setting it to what it already is does nothing', () async {
      await load(<Note>[note('a', 'body', markdown: true)]);
      final DateTime before = controller.notes.single.updatedAt;
      controller.setMarkdown('a', enabled: true);
      expect(controller.notes.single.updatedAt, before);
    });

    test('a note that is not there is ignored', () async {
      await load(<Note>[note('a', 'body')]);
      controller.setMarkdown('missing', enabled: true);
      expect(controller.notes.single.markdown, isFalse);
    });
  });

  group('the widget card', () {
    testWidgets('a plain note is untouched by any of this', (WidgetTester tester) async {
      await pumpCard(tester, note('Title', '**not bold**'));
      // The asterisks stay visible, because the note did not ask for otherwise.
      expect(find.textContaining('**not bold**'), findsWidgets);
      expect(find.byType(MarkdownText), findsNothing);
    });

    testWidgets('a markdown note renders rather than showing its source',
        (WidgetTester tester) async {
      await pumpCard(tester, note('Title', '**bold** words', markdown: true));

      expect(_allText(tester).join(' '), isNot(contains('**')),
          reason: 'the asterisks are syntax and should not be on screen');
      expect(find.byType(MarkdownText), findsWidgets);
    });

    testWidgets('a markdown title honours inline formatting', (WidgetTester tester) async {
      await pumpCard(tester, note('**Loud** title', 'body', markdown: true));
      final String texts = _allText(tester).join(' ');
      expect(texts, isNot(contains('**')));
      expect(texts, contains('Loud'));
    });

    testWidgets('a finished markdown card is struck through', (WidgetTester tester) async {
      final Note finished = note('t', '**bold**', markdown: true)
          .copyWith(completedAt: DateTime(2026));
      await pumpCard(tester, finished);

      // Carried by the enclosing DefaultTextStyle rather than by any one span,
      // because a rendered note is many spans and none of them is "the text".
      final bool carried = tester
          .widgetList<DefaultTextStyle>(find.byType(DefaultTextStyle))
          .any((DefaultTextStyle d) => d.style.decoration == TextDecoration.lineThrough);
      expect(carried, isTrue,
          reason: 'a finished note must still read as finished');
    });

    testWidgets('a compact card still clamps to its line budget',
        (WidgetTester tester) async {
      await pumpCard(
        tester,
        note('Title', List.generate(20, (int i) => 'line $i').join('\n\n'),
            markdown: true),
        roomy: false,
      );
      expect(tester.takeException(), isNull,
          reason: 'overflowing a small card would throw, not truncate');
    });
  });

  group('the notes list rows', () {
    late TestHarness harness;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.winnotes/shell'),
        (MethodCall call) async => null,
      );
      harness = TestHarness.build();
    });

    tearDown(() async {
      await harness.dispose();
    });

    /// The list pane at its real width: 300px, which is what the editor gives it.
    ///
    /// The provider is warmed inside `runAsync` and before `pumpWidget`, for the
    /// reason spelled out in `pumpEditor` in `editor_navigation_test`: a provider
    /// built during a pump issues its file read under the fake clock, which never
    /// advances, so the list renders nothing and the test finds no rows.
    /// reason spelled out in pumpEditor in ditor_navigation_test: a provider
    /// built during a pump issues its file read under the fake clock, which never
    /// advances.
    Future<void> pumpList(WidgetTester tester, List<Note> notes) async {
      await tester.runAsync(() async {
        final NotesRepository repo = NotesRepository(AtomicJsonFile(harness.notesFile));
        await repo.saveNow(notes);
        await harness.notes();
      });

      await tester.pumpWidget(
        harness.wrap(
          MaterialApp(
            theme: buildWinNotesTheme(
              brightness: Brightness.light,
              highContrast: false,
            ),
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: NoteListPane(
                  onOpenNote: () {},
                  onNewNote: () {},
                  onCloseList: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a plain row still shows its source', (WidgetTester tester) async {
      // The whole point of the per-note flag: a note that never asked for
      // Markdown must be byte-for-byte what it was.
      await pumpList(tester, <Note>[note('Plain', '**not bold** and `code`')]);

      expect(find.byType(MarkdownText), findsNothing);
      expect(find.textContaining('**not bold**'), findsOneWidget);
      expect(find.textContaining('`code`'), findsOneWidget);
    });

    testWidgets('a markdown row renders its preview rather than its source',
        (WidgetTester tester) async {
      await pumpList(tester, <Note>[
        note('Reference', '**Bold**, *italic*, ~~struck~~ and `code`',
            markdown: true),
      ]);

      final String text = _allText(tester).join(' ');
      expect(text, isNot(contains('**')), reason: 'bold markers');
      expect(text, isNot(contains('*italic*')), reason: 'italic markers');
      expect(text, isNot(contains('~~')), reason: 'strikethrough markers');
      expect(text, isNot(contains('`')), reason: 'code backticks');

      final List<({GestureRecognizer? recognizer, TextStyle style, String text})> runs = _runs(tester);
      expect(runs.any((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'Bold' && r.style.fontWeight == FontWeight.w700),
          isTrue);
      expect(runs.any((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'italic' && r.style.fontStyle == FontStyle.italic),
          isTrue);
      expect(runs.any((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'code' && r.style.fontFamily == 'Consolas'),
          isTrue);
    });

    testWidgets('a markdown row keeps list structure in its preview',
        (WidgetTester tester) async {
      // Inline-only rendering would have concatenated the items with no marker
      // at all, which is *less* than the note said - the same failure the table
      // flatten had. Rows get blocks, not just spans.
      await pumpList(tester, <Note>[
        note('Tasks', '- [ ] open\n- [x] done', markdown: true),
      ]);

      expect(find.textContaining('☐'), findsWidgets);
      expect(find.textContaining('☑'), findsWidgets);
    });

    testWidgets('a markdown row renders its title inline', (WidgetTester tester) async {
      await pumpList(tester, <Note>[note('**Loud** title', 'body', markdown: true)]);

      expect(_allText(tester).join(' '), isNot(contains('**')));
      expect(_runs(tester).any((({GestureRecognizer? recognizer, TextStyle style, String text}) r) => r.text == 'Loud'), isTrue);
    });

    testWidgets('a markdown row stays inside the row height', (WidgetTester tester) async {
      // A long note must clip rather than grow the row or throw. Overflow is
      // what `maxLines` cannot prevent - it bounds lines inside one Text, not
      // the number of blocks.
      await pumpList(tester, <Note>[
        note(
          'Long',
          List.generate(30, (int i) => 'line $i').join('\n\n'),
          markdown: true,
        ),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a markdown row is no taller than a plain one', (WidgetTester tester) async {
      // Both get two lines of preview, so the list rhythm does not change
      // depending on whether a note happens to use Markdown.
      await pumpList(tester, <Note>[
        note('Md', '# Heading\n\nsome **body** text', markdown: true),
      ]);
      final double mdHeight = tester.getSize(find.byType(NoteListPane)).height;

      await pumpList(tester, <Note>[
        note('Plain', '# Heading\n\nsome **body** text'),
      ]);
      final double plainHeight = tester.getSize(find.byType(NoteListPane)).height;

      // The pane fills its box either way; what matters is that nothing threw
      // and the row content stayed put.
      expect(mdHeight, plainHeight);
      expect(tester.takeException(), isNull);
    });
  });

  group('a clamped render', () {
    test('the fade band is added to the lines, not taken from them', () {
      // Two lines means two lines you can read. If the band came out of them,
      // the second line would sit inside the fade and be unreadable - which
      // looks like the renderer lost a line rather than like a clamp.
      final double two = MarkdownText.budgetForLines(
        fontSize: 13,
        lineHeight: 1.35,
        lines: 2,
      );
      const double oneLine = 13 * 1.35;

      expect(two, greaterThan(oneLine * 2));
      expect(two, lessThan(oneLine * 3));
    });

    test('the budget scales with the surface type size', () {
      final double small = MarkdownText.budgetForLines(
        fontSize: 12,
        lineHeight: 1.35,
        lines: 2,
      );
      final double large = MarkdownText.budgetForLines(
        fontSize: 13,
        lineHeight: 1.35,
        lines: 2,
      );
      expect(large, greaterThan(small));
    });

    testWidgets('a title honours the line count it is given', (WidgetTester tester) async {
      // Regression: `MarkdownText.inline` used to ignore `maxLines` and always
      // clip at one, so the large widget card's two-line title silently got
      // one.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildWinNotesTheme(
            brightness: Brightness.light,
            highContrast: false,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: MarkdownText.inline(
                'a title long enough that it must wrap onto a second line',
                color: const Color(0xFF23202E),
                accent: const Color(0xFFE8551D),
                style: const TextStyle(fontSize: 14, color: Color(0xFF23202E)),
                maxLines: 2,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final RichText text = tester.widget<RichText>(find.byType(RichText).first);
      final InlineSpan span = text.text;
      expect(span, isA<TextSpan>());
      expect((span as TextSpan).style?.decoration, isNot(TextDecoration.lineThrough));
      // maxLines and overflow are RichText's, not the span's.
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('the editor switch and preview', () {
    late TestHarness harness;
    late Notes controller;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.winnotes/shell'),
        (MethodCall call) async => null,
      );
      harness = TestHarness.build();
    });

    tearDown(() async {
      // The debounce timers are fake under a widget test, so they never elapse on
      // their own and the test ends with one still pending. The harness's dispose
      // gives up on the directory rather than failing, which is what that comment
      // was protecting against - but the write genuinely should not land here,
      // because what is under test is what is on screen.
      await harness.dispose();
    });

    Future<void> pumpPane(WidgetTester tester, double width) async {
      // Real file IO has to happen inside `runAsync`. Under a widget test's fake
      // clock the event loop is never really pumped, so awaiting a disk write here
      // hangs forever - the timer the debounce starts fires, but the write it began
      // never completes. Which looks exactly like a widget test that hangs for no
      // reason. See docs/testing_pattern.md section 4.
      await tester.runAsync(() async {
        final NotesRepository repo = NotesRepository(AtomicJsonFile(harness.notesFile));
        await repo.saveNow(<Note>[
          note('t', '# Heading\n\n**bold** words', markdown: true),
        ]);
        // Warmed here, before the pump, for the same reason as everywhere else:
        // a provider built during pumpWidget reads the file under the fake clock.
        await harness.notes();
        controller = Notes(harness);
      });

      await tester.pumpWidget(
        harness.wrap(
          MaterialApp(
            theme: buildWinNotesTheme(
              brightness: Brightness.light,
              highContrast: false,
            ),
            home: Scaffold(
              body: SizedBox(
                width: width,
                height: 600,
                child: const NoteEditorPane(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the switch is present', (WidgetTester tester) async {
      await pumpPane(tester, 800);
      expect(find.byKey(markdownToggleKey), findsOneWidget);
    });

    testWidgets('a wide pane shows the source and the preview together',
        (WidgetTester tester) async {
      await pumpPane(tester, 800);
      // Title and body source. A preview is not a third field.
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(MarkdownText), findsWidgets,
          reason: 'and the rendered note beside them');
      expect(find.byType(VerticalDivider), findsWidgets);
    });

    testWidgets('a narrow pane offers a switch instead of two cramped columns',
        (WidgetTester tester) async {
      await pumpPane(tester, 380);
      expect(find.byType(MarkdownText), findsNothing,
          reason: 'no room for both, so it asks rather than guessing');
      expect(find.text('Show preview'), findsOneWidget);

      await tester.tap(find.text('Show preview'));
      await tester.pump();

      expect(find.byType(MarkdownText), findsWidgets);
      expect(find.text('Edit source'), findsOneWidget);
    });

    testWidgets('the switch says what turning it on gets you',
        (WidgetTester tester) async {
      await pumpPane(tester, 800);
      // It used to be an 18px circle next to the completion circle, which read as
      // a second checkbox. The word is the whole fix, so it is asserted: a
      // designer tidying the row back to a bare icon fails this test.
      expect(
        find.descendant(
          of: find.byKey(markdownToggleKey),
          matching: find.text('Preview'),
        ),
        findsOneWidget,
        reason: 'an unlabelled circle beside the completion circle is a checkbox',
      );
    });

    testWidgets('the switch keeps the same width in both states',
        (WidgetTester tester) async {
      await pumpPane(tester, 800);
      final double off = tester.getSize(find.byKey(markdownToggleKey)).width;

      await tester.tap(find.byKey(markdownToggleKey));
      await tester.pump();
      await tester.pump();

      // The state is carried by fill and colour, not by the word appearing and
      // disappearing - a label that changes length shunts the title sideways.
      expect(tester.getSize(find.byKey(markdownToggleKey)).width, off);

      // Same trap as the toggle test below: the state change schedules a debounced
      // write, and under a widget test that timer is fake and never elapses.
      harness.cancelPendingWrites();
    });

    testWidgets('tapping the switch turns Markdown off for that note',
        (WidgetTester tester) async {
      await pumpPane(tester, 800);
      expect(controller.notes.single.markdown, isTrue);

      await tester.tap(find.byKey(markdownToggleKey));
      await tester.pump();
      await tester.pump();

      expect(controller.notes.single.markdown, isFalse);
      expect(find.byType(MarkdownText), findsNothing,
          reason: 'and the preview goes with it');

      // Turning Markdown off schedules a debounced write, and under a widget test
      // that timer is fake - it never elapses on its own, and the test ends with
      // one still pending. Cancelled here rather than in tearDown: the pending-timer
      // check runs before tearDown does, so tearDown is too late to save this test.
      //
      // Cancelled rather than flushed, and that is the whole point. `flush` *awaits*
      // the write, and under a fake clock it never completes - so the first version
      // of this line turned a failing assertion into a ten-minute hang, which is a
      // much worse way to hear about it. See `TestHarness.cancelPendingWrites` and
      // `docs/testing_pattern.md` §4.
      harness.cancelPendingWrites();
    });

    testWidgets('the source keeps the syntax while it is being typed',
        (WidgetTester tester) async {
      await pumpPane(tester, 800);
      // The preview is rendered; the field beside it still holds the raw text,
      // because rendering must never rewrite what gets saved.
      final Iterable<TextField> fields = tester.widgetList<TextField>(find.byType(TextField));
      final TextField body = fields.last;
      expect(body.controller!.text, contains('# Heading'));
    });
  });
}

/// One text run on screen, with the style that actually applies to it.
///
/// Span styles inherit, and leaf runs in this renderer usually carry none -
/// the style lives on the paragraph above them. Reading `span.style` directly
/// therefore reports null for most of what is drawn, which is a fact about the
/// renderer rather than about the note, and a test that believed it would
/// "pass" by finding nothing.
List<({String text, TextStyle style, GestureRecognizer? recognizer})> _runs(
  WidgetTester tester,
) {
  final List<({GestureRecognizer? recognizer, TextStyle style, String text})> out =
      <({String text, TextStyle style, GestureRecognizer? recognizer})>[];

  void walk(InlineSpan span, TextStyle inherited) {
    final TextStyle? own = span is TextSpan ? span.style : null;
    final TextStyle effective =
        own?.inherit == false ? (own ?? const TextStyle()) : inherited.merge(own);
    if (span is TextSpan && span.text != null) {
      out.add((
        text: span.text!,
        style: effective,
        recognizer: span.recognizer,
      ));
    }
    if (span is TextSpan) {
      for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
        walk(child, effective);
      }
    }
  }

  // Seeded empty: every span this renderer builds carries its style on the
  // root of the run, which is what a child span inherits from. Plain Text`n  // widgets get their style from a DefaultTextStyle instead and are read
  // through [_allText], which asks the widget directly.
  for (final RichText r in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(r.text, const TextStyle());
  }
  return out;
}

/// Every string on screen, including the plain `Text` widgets the renderer uses
/// for list markers.
List<String> _allText(WidgetTester tester) {
  final List<String> out = <String>[];
  for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
    final String? data = t.data;
    if (data != null) out.add(data);
  }
  for (final ({GestureRecognizer? recognizer, TextStyle style, String text}) r in _runs(tester)) {
    out.add(r.text);
  }
  return out;
}
