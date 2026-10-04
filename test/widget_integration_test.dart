import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/src/core/atomic_json_file.dart';
import 'package:win_notes/src/data/note.dart';
import 'package:win_notes/src/data/notes_repository.dart';
import 'package:win_notes/src/data/settings_repository.dart';
import 'package:win_notes/src/platform/shell_channel.dart';
import 'package:win_notes/src/state/settings_controller.dart';
import 'package:win_notes/src/state/widget_controller.dart' as wn;
import 'package:win_notes/src/ui/theme.dart';
import 'package:win_notes/src/ui/widget/widget_note_card.dart';
import 'package:win_notes/src/ui/widget/widget_surface.dart';

/// Integration tests for the widget surface itself.
///
/// These exist because of a specific past failure. [WidgetSurface] decides
/// whether the focused card renders large, and the original version answered
/// that by reading `ScrollPosition.maxScrollExtent` from inside the
/// `ListView.separated` itemBuilder. That read happens during sliver layout,
/// before a ScrollPosition has a viewport, so it threw "Null check operator used
/// on a null value" and replaced the widget with a red error screen over the
/// desktop.
///
/// The unit tests for [WidgetNoteCard] never caught it, because they exercise
/// the card alone and the crash was in the list above it. These build the real
/// [WidgetSurface] over a real file-backed controller so the whole subtree is
/// actually laid out.
void main() {
  late Directory temp;

  setUp(() {
    // Required, not cosmetic. WidgetController.load() awaits its window
    // configuration call, and a MethodChannel with nothing behind it returns a
    // Future that never completes - which under flutter_test is not a failure
    // but a test that hangs forever.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.winnotes/shell'),
      (call) async => null,
    );
    temp = Directory.systemTemp.createTempSync('winnotes_widget_test');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Note note(String id, String title, String body, {int minute = 0}) => Note(
        id: id,
        title: title,
        body: body,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1, 12, minute),
      );

  /// Builds a controller over real files, the way the widget isolate does.
  ///
  /// Must be called inside [WidgetTester.runAsync]: these are real file writes,
  /// and a widget test's fake clock never advances the real event loop, so
  /// awaiting them outside it hangs.
  ///
  /// [watchExternal] is false because the real directory watchers use real
  /// timers. The watchers themselves are covered by the repository tests, which
  /// run outside the fake clock.
  Future<wn.WidgetController> makeController(
    WidgetTester tester,
    List<Note> notes, {
    Future<void> Function(SettingsController)? tweakSettings,
  }) async {
    final shell = ShellChannel();

    final notesRepo = NotesRepository(
      AtomicJsonFile('${temp.path}\\notes.json'),
    );
    await notesRepo.saveNow(notes);

    final settings = SettingsController(
      repository: SettingsRepository(
        AtomicJsonFile('${temp.path}\\settings.json'),
        shell,
      ),
      shell: shell,
    );
    await settings.load(animationsEnabled: true, acrylicSupported: false);
    // Applied before the widget controller attaches its listener, so the first
    // configure it sends already reflects the change.
    await tweakSettings?.call(settings);

    final controller = wn.WidgetController(
      shell: shell,
      settings: settings,
      notesRepo: notesRepo,
      widgetRepo: WidgetStateRepository(
        AtomicJsonFile('${temp.path}\\widget_state.json'),
      ),
      selectionRepo: SelectionRepository(
        AtomicJsonFile('${temp.path}\\selection.json'),
      ),
      isAutostartLaunch: false,
      animationsEnabled: true,
      acrylicSupported: false,
      isSystemDark: false,
      watchExternal: false,
    );
    await controller.load();
    return controller;
  }

  /// Releases a controller's file handles under the real clock.
  ///
  /// Registered as a tearDown rather than left to [wn.WidgetController.dispose],
  /// because flushing is async and dispose cannot await. Safe to call twice: a
  /// test that already released inside its own runAsync block gets a no-op.
  void addRelease(WidgetTester tester, wn.WidgetController controller) {
    addTearDown(() async {
      await tester.runAsync(controller.release);
      controller.dispose();
    });
  }

  Future<void> pumpSurface(
    WidgetTester tester,
    wn.WidgetController controller, {
    required double width,
    required double height,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme:
            buildWinNotesTheme(brightness: Brightness.light, highContrast: false),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: height,
              child: WidgetSurface(
                controller: controller,
                brightness: Brightness.light,
                acrylicAvailable: false,
                onOpenEditor: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders a scrolling list of every note without throwing',
      (tester) async {
    final controller = await tester.runAsync(
      () => makeController(tester, [
        note('a', 'Groceries', 'Milk, sourdough\nCheck the bike light'),
        note('b', 'Reading list', 'The Design of Everyday Things', minute: -5),
        note('c', 'Ideas', 'Widget per monitor?', minute: -12),
      ]),
    );
    addRelease(tester, controller!);

    // The regression this guards: building this subtree used to throw during
    // sliver layout and paint a red error screen over the desktop.
    await pumpSurface(tester, controller, width: 360, height: 420);

    expect(tester.takeException(), isNull);
    expect(find.byType(WidgetNoteCard), findsNWidgets(3));
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Reading list'), findsOneWidget);
    expect(find.text('Ideas'), findsOneWidget);
  });

  testWidgets('the most recent note is the focused, large card',
      (tester) async {
    final controller = await tester.runAsync(
      () => makeController(tester, [
        note('old', 'Older note', 'written earlier', minute: -30),
        note('new', 'Newest note', 'written last', minute: 0),
      ]),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);

    expect(controller.focusedNote!.id, 'new');
    final cards =
        tester.widgetList<WidgetNoteCard>(find.byType(WidgetNoteCard));
    expect(cards.first.focused, isTrue);
    expect(cards.first.roomy, isTrue);
    expect(cards.first.note.id, 'new');
    expect(cards.skip(1).every((c) => !c.roomy || !c.focused), isTrue);
  });

  testWidgets('selecting an older note from the widget makes it focused',
      (tester) async {
    final controller = await tester.runAsync(
      () => makeController(tester, [
        note('old', 'Older note', 'written earlier', minute: -30),
        note('new', 'Newest note', 'written last', minute: 0),
      ]),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);
    expect(controller.focusedNote!.id, 'new');

    // Tapping a compact card focuses it, which is the point of showing every
    // note in the widget rather than just the current one.
    await tester.tap(find.text('Older note'));
    await tester.pump();

    // The tap writes selection.json through the debounced writer, so the pending
    // 250ms timer has to be let run. Without this the test ends with a pending
    // timer and fails for a reason that has nothing to do with the assertion
    // below it.
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.focusedNote!.id, 'old');
    final cards =
        tester.widgetList<WidgetNoteCard>(find.byType(WidgetNoteCard));
    expect(cards.first.note.id, 'old');
    expect(cards.first.focused, isTrue);
  });

  testWidgets('falls back to compact cards when the widget is small',
      (tester) async {
    final controller = await tester.runAsync(
      () => makeController(tester, [
        note('a', 'Groceries', 'a body long enough to need several lines'),
      ]),
    );
    addRelease(tester, controller!);

    // Below the threshold there is no room for a large card.
    await pumpSurface(tester, controller, width: 150, height: 140);

    expect(tester.takeException(), isNull);
    final cards =
        tester.widgetList<WidgetNoteCard>(find.byType(WidgetNoteCard));
    expect(cards.single.roomy, isFalse);
  });

  testWidgets('shows a quiet line rather than crashing when notes vanish',
      (tester) async {
    final controller = await tester.runAsync(
      () => makeController(tester, [note('a', 'Only note', 'text')]),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);
    expect(find.byType(WidgetNoteCard), findsOneWidget);

    // The last note is deleted while the widget is on screen.
    File('${temp.path}\\notes.json').writeAsStringSync(
      '{"format":"winnotes","version":1,"notes":[]}',
    );
    await tester.runAsync(() => controller.load());

    await pumpSurface(tester, controller, width: 360, height: 420);
    expect(tester.takeException(), isNull);
    expect(find.text('No notes'), findsOneWidget);
  });

  testWidgets('a list too long for the widget scrolls', (tester) async {
    final controller = await tester.runAsync(
      () => makeController(tester, [
        for (var i = 0; i < 30; i++)
          note('n$i', 'Note $i', 'body $i', minute: -i),
      ]),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);
    expect(tester.takeException(), isNull);

    // The newest is on screen; the oldest is not, because the widget is short.
    expect(find.text('Note 0'), findsOneWidget);
    expect(find.text('Note 29'), findsNothing);

    // Scroll to the end. Dragging a fixed distance would depend on the content
    // height, which changes with every title length, so this targets the maximum
    // extent instead and then lets a second pump build the children it exposes.
    // Scrolling flushes on the platform thread, and the writes are file I/O that
    // cannot run under this test's fake clock. Everything from here to the end
    // of the test happens inside one real-async block so those writes can
    // actually complete; pumping inside it would use the fake clock again.
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    await tester.runAsync(() async {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      // Past both the 250ms trailing debounce and the 1500ms write ceiling.
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      await controller.release();
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Note 29'), findsOneWidget);
    // The list really did move, rather than Note 29 having been on screen all
    // along.
    expect(find.text('Note 0'), findsNothing);
  });

  testWidgets('the position lock reaches the runner', (tester) async {
    // The switch is only worth having if it changes what the native window
    // does, so this checks the payload the runner actually receives rather than
    // the Dart field that produced it.
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.winnotes/shell'),
      (call) async {
        if (call.method == 'widget.configure') calls.add(call);
        return null;
      },
    );

    final locked = await tester.runAsync(
      () => makeController(tester, [note('a', 'Groceries', 'milk')]),
    );
    addRelease(tester, locked!);

    expect(calls, isNotEmpty, reason: 'the widget never configured itself');
    expect(
      (calls.first.arguments as Map)['positionLocked'],
      isFalse,
      reason: 'a fresh install must not ship a widget that cannot be moved',
    );

    // Turning the lock off has to reach the runner as a live change, not need a
    // restart.
    final unlocked = await tester.runAsync(
      () => makeController(
        tester,
        [note('a', 'Groceries', 'milk')],
        tweakSettings: (s) =>
            s.update((v) => v.copyWith(widgetPositionLocked: false)),
      ),
    );
    addRelease(tester, unlocked!);

    final configures = calls.where((c) => c.method == 'widget.configure').toList();
    expect(
      (configures.last.arguments as Map)['positionLocked'],
      isFalse,
      reason: 'unlocking must be pushed, not merely stored',
    );
  });

  testWidgets('a refused drag explains itself instead of doing nothing',
      (tester) async {
    // The bug this guards: locked, the native window reports HTCLIENT, the drag
    // never starts, and nothing at all happens. Someone dragging a locked
    // widget has no way to tell the lock is why.
    final controller = await tester.runAsync(
      () => makeController(
        tester,
        [note('a', 'Groceries', 'milk')],
        tweakSettings: (s) =>
            s.update((v) => v.copyWith(widgetPositionLocked: true)),
      ),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);
    expect(find.textContaining('Locked in place'), findsNothing,
        reason: 'the hint must not appear before anyone has tried to drag');

    final gesture = await tester.startGesture(const Offset(180, 120));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      find.textContaining('Locked in place'),
      findsOneWidget,
      reason: 'a refused drag has to say so, and say where to change it',
    );
    expect(find.textContaining('Settings'), findsOneWidget,
        reason: 'naming the place to change it is the point');

    // And it goes away again rather than sitting there for good.
    await tester.pump(const Duration(milliseconds: 2800));
    expect(find.textContaining('Locked in place'), findsNothing);
  });

  testWidgets('an unlocked widget does not nag about dragging', (tester) async {
    final controller = await tester.runAsync(
      () => makeController(tester, [note('a', 'Groceries', 'milk')]),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);
    final gesture = await tester.startGesture(const Offset(180, 120));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(find.textContaining('Locked in place'), findsNothing,
        reason: 'dragging works by default, so there is nothing to explain');
  });

  /// Records the drag hand-offs the surface makes, and nothing else.
  ///
  /// The hand-off is the whole contract with the runner: Dart decides what the
  /// gesture is, the runner tracks the cursor in screen space. So "did a
  /// hand-off happen, and with what anchor" is exactly the observable that
  /// matters, and it is observable without a live window.
  List<MethodCall> recordHandOffs() {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.winnotes/shell'),
      (call) async {
        if (call.method == 'widget.beginMove' || call.method == 'widget.beginResize') {
          calls.add(call);
        }
        return null;
      },
    );
    return calls;
  }

  Future<void> dragBody(WidgetTester tester, {double dy = 12}) async {
    final gesture = await tester.startGesture(const Offset(180, 120));
    // Four steps past the 8px threshold, the way a real drag arrives.
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(0, dy));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a drag is handed to the runner with its anchor', (tester) async {
    // The bug this guards: the widget reported HTCAPTION for its body and
    // waited for Windows to run a move loop. There was no loop - the window is a
    // borderless WS_POPUP with neither WS_CAPTION nor WS_THICKFRAME - and the
    // Flutter view covered the client area, so the hit test was never consulted
    // either. The widget could not be moved or resized at all.
    final calls = recordHandOffs();
    final controller = await tester.runAsync(
      () => makeController(tester, [note('a', 'Groceries', 'milk')]),
    );
    addRelease(tester, controller!);

    // One note, so the list has nothing to scroll and the drag is unambiguous.
    await pumpSurface(tester, controller, width: 360, height: 420);
    await dragBody(tester);

    final moves = calls.where((c) => c.method == 'widget.beginMove').toList();
    expect(moves, hasLength(1),
        reason: 'an unlocked widget with nothing to scroll must hand the drag '
            'to the runner exactly once');
    // The anchor travels with it: the runner is told about a drag only after the
    // pointer has already travelled, so anchoring on the cursor at that moment
    // would throw away the whole first hop.
    final anchor = moves.single.arguments as Map;
    expect(anchor['anchorX'], 180.0);
    expect(anchor['anchorY'], 120.0);
  });

  testWidgets('a scroll wins over a drag while there is more list to read',
      (tester) async {
    // Drags and scrolls are the same gesture shape. Deciding by the scroll
    // extent rather than by whichever notification arrives first is what makes
    // this reliable; getting the direction backwards hands every upward drag to
    // the window, which is the direction people most often use to scroll.
    final calls = recordHandOffs();
    final controller = await tester.runAsync(
      () => makeController(tester, [
        for (var i = 0; i < 30; i++)
          note('n$i', 'Note $i', 'body $i', minute: -i),
      ]),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0),
        reason: 'the test is meaningless unless the list really does overflow');

    // At the top of the list, dragging up has to scroll.
    await dragBody(tester, dy: -12);
    expect(calls.where((c) => c.method == 'widget.beginMove'), isEmpty,
        reason: 'stealing the scroll would make a long list unreadable');

    // Once there is nothing left below, the same gesture brings the window.
    // Jumping the scroll position arms the debounced writer, so the flush has to
    // happen under the real clock: a widget test's fake clock never advances the
    // real event loop, and the pending timer fails the test on the way out.
    await tester.runAsync(() async {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      // Past both the 250ms trailing debounce and the 1500ms write ceiling.
      await Future<void>.delayed(const Duration(milliseconds: 1600));
    });
    await tester.pump();

    await dragBody(tester, dy: -12);
    expect(calls.where((c) => c.method == 'widget.beginMove'), hasLength(1),
        reason: 'at the end of the list, the widget should come with the drag');
  });

  testWidgets('at the top of the list, dragging down moves the widget',
      (tester) async {
    // The other half of the same rule: dragging down at the top has nothing to
    // scroll, so it belongs to the window rather than being swallowed.
    final calls = recordHandOffs();
    final controller = await tester.runAsync(
      () => makeController(tester, [
        for (var i = 0; i < 30; i++)
          note('n$i', 'Note $i', 'body $i', minute: -i),
      ]),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);
    await dragBody(tester, dy: 12);

    expect(calls.where((c) => c.method == 'widget.beginMove'), hasLength(1));
  });

  testWidgets('a locked widget is not handed to the runner', (tester) async {
    final calls = recordHandOffs();
    final controller = await tester.runAsync(
      () => makeController(
        tester,
        [note('a', 'Groceries', 'milk')],
        tweakSettings: (s) =>
            s.update((v) => v.copyWith(widgetPositionLocked: true)),
      ),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);
    await dragBody(tester);

    expect(calls, isEmpty,
        reason: 'a locked widget must not start a drag the runner would act on');
  });

  testWidgets('grabbing an edge hands a resize to the runner, with the edge',
      (tester) async {
    final calls = recordHandOffs();
    final controller = await tester.runAsync(
      () => makeController(tester, [
        for (var i = 0; i < 30; i++)
          note('n$i', 'Note $i', 'body $i', minute: -i),
      ]),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);

    // Bottom edge, well clear of the corners. The band has to be wider than the
    // window's rounded corner, because the native region clips those pixels away
    // and a grab aimed at the literal corner arrives at nothing.
    final gesture = await tester.startGesture(const Offset(180, 415));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    final resizes = calls.where((c) => c.method == 'widget.beginResize').toList();
    expect(resizes, hasLength(1), reason: 'an edge grab is a resize');
    expect((resizes.single.arguments as Map)['edge'], 4,
        reason: "4 is the runner's code for the bottom edge");
    expect(calls.where((c) => c.method == 'widget.beginMove'), isEmpty);
  });

  testWidgets('a press that does not move is not a drag', (tester) async {
    // Cards have to stay tappable, so a press and a release with no travel must
    // never turn into a drag.
    final calls = recordHandOffs();
    final controller = await tester.runAsync(
      () => makeController(tester, [note('a', 'Groceries', 'milk')]),
    );
    addRelease(tester, controller!);

    await pumpSurface(tester, controller, width: 360, height: 420);

    final gesture = await tester.startGesture(const Offset(180, 120));
    await gesture.moveBy(const Offset(2, 3));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(calls, isEmpty, reason: 'below the threshold this is just a tap');
  });
}