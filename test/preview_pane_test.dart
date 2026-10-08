import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/notes/presentation/widgets/preview_pane/preview_pane.dart';

/// The scrollbar crash: scrolling the Markdown preview threw
/// "The Scrollbar's ScrollController has no ScrollPosition attached"
/// because the [Scrollbar] had no controller and fell back to the
/// [PrimaryScrollController], which this scroll view never attached to.
/// Fixed by giving both widgets one shared controller owned by the pane.
void main() {
  Note note(String body) => Note(
        id: 'n1',
        title: 'Note',
        body: body,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  Future<void> pumpPreview(
    WidgetTester tester,
    String source, {
    double height = 200,
  }) async {
    final ValueNotifier<String> previewSource = ValueNotifier<String>(source);
    addTearDown(previewSource.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: height,
            child: PreviewPane(
              note: note(source),
              previewSource: previewSource,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('scrolling the preview does not throw', (WidgetTester tester) async {
    // Long enough to overflow a 200px box, so there is somewhere to scroll to.
    final String source = List<String>.generate(
      40,
      (int i) => 'Line $i of a long note.',
    ).join('\n\n');
    await pumpPreview(tester, source);

    expect(tester.takeException(), isNull);

    // The reported crash came from scrolling the preview: a scroll notification
    // reaches the scrollbar's fade animation, which asserts on its controller.
    // (The exact assertion only fires on real-device animation timing, so the
    // structural test below is the pin — this is the smoke.)
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Offset center = tester.getCenter(find.byType(SingleChildScrollView));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the scrollbar and the scroll view share one controller', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester, 'Short note.');

    final Scrollbar scrollbar = tester.widget(find.byType(Scrollbar).first);
    final SingleChildScrollView view =
        tester.widget(find.byType(SingleChildScrollView));

    expect(scrollbar.controller, isNotNull);
    expect(view.controller, isNotNull);
    expect(identical(scrollbar.controller, view.controller), isTrue);
  });
}
