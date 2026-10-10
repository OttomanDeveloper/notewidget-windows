// Ctrl+wheel font resizing in the narrow, one-pane-at-a-time layout.
//
// `font_step_test.dart` pins the coalescing rule and says outright that the
// wiring has never been tested. This drives the real widget.
//
// The reported case: in the narrow editor the wheel did nothing. The narrow
// branch passes `narrowShowsPreview: shows`, and the listener resolves the pane
// from that flag rather than from the pointer's x. So the question is whether
// the step is delivered at all when the editor pane is the one showing.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/features/notes/presentation/widgets/text_size_wheel_listener/text_size_wheel_listener.dart';

void main() {
  late List<String> steps;

  setUp(() => steps = <String>[]);

  Future<void> pump(
    WidgetTester tester, {
    required bool narrowShowsPreview,
    required double width,
    bool editor = true,
    bool preview = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 400,
            child: TextSizeWheelListener(
              narrowShowsPreview: narrowShowsPreview,
              onEditorStep: editor ? (int d) => steps.add('editor $d') : null,
              onPreviewStep: preview ? (int d) => steps.add('preview $d') : null,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> wheel(WidgetTester tester) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(SizedBox).first),
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pump();
  }

  group('the narrow layout, where one pane shows at a time', () {
    testWidgets('ctrl+wheel over the editor pane resizes the editor',
        (WidgetTester tester) async {
      // `narrowShowsPreview: false` is the editor showing. This is the reported
      // bug: the wheel is over the editor, so the editor must be what resizes.
      await pump(tester, narrowShowsPreview: false, width: 380);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await wheel(tester);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(steps, <String>['editor 1']);
    });

    testWidgets('ctrl+wheel over the preview pane resizes the preview',
        (WidgetTester tester) async {
      await pump(tester, narrowShowsPreview: true, width: 380);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await wheel(tester);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(steps, <String>['preview 1']);
    });

    testWidgets('wheel up is larger, matching every other application',
        (WidgetTester tester) async {
      await pump(tester, narrowShowsPreview: false, width: 380);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(SizedBox).first),
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(steps, <String>['editor -1']);
    });
  });

  group('the wide layout, where the pointer decides', () {
    testWidgets('left of the split is the editor', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 400,
              child: TextSizeWheelListener(
                onEditorStep: (int d) => steps.add('editor $d'),
                onPreviewStep: (int d) => steps.add('preview $d'),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(100, 200),
          scrollDelta: Offset(0, -120),
        ),
      );
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(steps, <String>['editor 1']);
    });

    testWidgets('right of the split is the preview', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 400,
              child: TextSizeWheelListener(
                onEditorStep: (int d) => steps.add('editor $d'),
                onPreviewStep: (int d) => steps.add('preview $d'),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          // Inside the 800x600 test surface: the split of a 900-wide listener
          // sits at 450, and the default screen is only 800 across.
          position: Offset(700, 200),
          scrollDelta: Offset(0, -120),
        ),
      );
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(steps, <String>['preview 1']);
    });
  });

  testWidgets('without ctrl the wheel is left alone', (WidgetTester tester) async {
    await pump(tester, narrowShowsPreview: false, width: 380);

    await wheel(tester);

    expect(steps, isEmpty, reason: 'plain scrolling must still scroll');
  });
}