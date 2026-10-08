// What the preview must do, and why it is not lazy.
//
// The first version of this rendered blocks lazily, a `ListView.builder` over
// `MarkdownBlockList.slotsOf`. That made a keystroke about 7x cheaper, and it
// **broke the preview**: the scrollbar could not hold a position, because a lazy
// list of unknown-height children has no extent to represent. Measured on the
// 1012-line demo, `maxScrollExtent` swung between 2,278px and 608,271px across
// twenty scrolls - a drift of 585,563px - while a non-lazy list sat at 24,997px
// and never moved.
//
// The frame cost was identical either way (9-19ms lazy, 14-21ms not), so
// laziness bought nothing for scrolling and cost the scrollbar. It was reverted.
//
// So the invariant pinned here is **a stable scroll extent**, which is what the
// user actually notices, plus the obvious rendering guarantees. Structure, not
// milliseconds - see `docs/testing_pattern.md`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/theme/theme.dart';
import 'package:win_notes/core/widgets/markdown_block/markdown_block.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/notes/presentation/widgets/preview_pane/preview_pane.dart';

/// The note this was reported against: the project's own Markdown demo, 1012
/// lines. Read rather than inlined so the test cannot drift from that file.
String demoSource() =>
    File('docs/verification/markdown_demo_all_features.md').readAsStringSync();

/// Paragraph lines, so the parser really does make a block of each. A generated
/// note of `# heading` repeats would make one enormous block and prove nothing.
String linesOfBody(int count) => List<String>.generate(
      count,
      (int i) => 'Paragraph $i with enough words to occupy a line or two of a '
          'monospace source pane at the editor font size.',
    ).join('\n\n');

Future<void> pumpPreview(
  WidgetTester tester,
  String source, {
  double height = 600,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWinNotesTheme(brightness: Brightness.light, highContrast: false),
      home: Scaffold(
        body: SizedBox(
          width: 700,
          height: height,
          child: PreviewPane(
            note: Note(
              id: 'n1',
              title: 'Scale',
              body: source,
              markdown: true,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
            previewSource: ValueNotifier<String>(source),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition positionOf(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

int builtBlocks(WidgetTester tester) =>
    tester.widgetList(find.byType(MarkdownBlock)).length;

void main() {
  group('the preview has a scrollbar you can trust', () {
    // The regression that mattered. A lazy list estimates its extent, and the
    // estimate changes as children are laid out, so the thumb moves under the
    // user and the scrollbar cannot show where they are.
    testWidgets('the scroll extent does not change while scrolling',
        (WidgetTester tester) async {
      await pumpPreview(tester, demoSource());
      final ScrollPosition c = positionOf(tester);

      expect(c.maxScrollExtent, greaterThan(0),
          reason: 'a document longer than the pane must be scrollable');

      final Set<int> seen = <int>{c.maxScrollExtent.round()};
      for (int i = 0; i < 20; i++) {
        c.jumpTo((c.pixels + 400).clamp(0.0, c.maxScrollExtent));
        await tester.pump();
        seen.add(c.maxScrollExtent.round());
      }

      expect(seen, hasLength(1),
          reason: 'the extent drifted across $seen as the user scrolled; a '
              'scrollbar drawn from a moving extent cannot hold its position');
    });

    testWidgets('scrolling reaches the end of a note far longer than the pane',
        (WidgetTester tester) async {
      await pumpPreview(tester, linesOfBody(400));

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200000));
      await tester.pumpAndSettle();

      expect(find.textContaining('Paragraph 399'), findsWidgets,
          reason: 'the end of the note has to be reachable by scrolling');
    });

    testWidgets('the last paragraph of the demo note is reachable',
        (WidgetTester tester) async {
      await pumpPreview(tester, demoSource());
      final ScrollPosition c = positionOf(tester);
      c.jumpTo(c.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(c.pixels, greaterThan(c.maxScrollExtent - 1),
          reason: 'the last jump should land on the end, not short of it');
    });
  });

  group('the preview still renders the document it is given', () {
    testWidgets('the first blocks of a long note are rendered, not skipped',
        (WidgetTester tester) async {
      await pumpPreview(tester, linesOfBody(400));
      expect(find.textContaining('Paragraph 0'), findsWidgets);
      expect(find.textContaining('Paragraph 1'), findsWidgets);
    });

    testWidgets('the demo note renders as blocks, not as one blob',
        (WidgetTester tester) async {
      await pumpPreview(tester, demoSource());
      // A lazy list would build far fewer than this; a whole-document render
      // builds them all, which is what makes the extent exact.
      expect(builtBlocks(tester), greaterThan(100));
    });

    testWidgets('an empty note says so rather than showing nothing',
        (WidgetTester tester) async {
      await pumpPreview(tester, '   ');
      expect(find.text('Nothing to preview yet.'), findsOneWidget);
    });
  });
}