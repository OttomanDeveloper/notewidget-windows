import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/utils/atomic_json_file.dart';
import 'package:win_notes/core/platform/shell_channel.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/notes/data/notes_repository.dart';
import 'package:win_notes/features/settings/domain/settings.dart';
import 'package:win_notes/features/settings/presentation/providers/settings_controller.dart';
import 'package:win_notes/core/widgets/completion_toggle/completion_toggle.dart';
import 'package:win_notes/core/theme/theme.dart';
import 'package:win_notes/features/widget/presentation/widgets/widget_note_card/widget_note_card.dart';
import 'package:win_notes/features/widget/presentation/screens/widget_surface/widget_surface.dart';
import 'package:win_notes/features/widget/presentation/widgets/composer_button/composer_button.dart';
import 'package:win_notes/features/widget/presentation/widgets/composer_field/composer_field.dart';

import 'helpers/provider_harness.dart';
import 'helpers/file_io.dart';

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
  // The bug: `widget_state.json` held the dragged position and the widget still
  // opened in the runner's default corner every time. Saving worked; restoring
  // never happened, because nothing told the runner to move — it placed the
  // window itself and the saved left/top were read back over.
  testWidgets('a saved widget position is pushed back to the runner',
      (WidgetTester tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      ShellChannel.methodChannel,
      (MethodCall call) async {
        calls.add(call);
        return <String, Object>{'left': 1086, 'top': 366, 'width': 360, 'height': 420};
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ShellChannel.methodChannel, null);
    });

    await ShellChannel().setWidgetGeometry(
      const NativeBounds(left: 1086, top: 366, width: 360, height: 420),
    );

    final MethodCall set =
        calls.firstWhere((MethodCall c) => c.method == 'widget.setGeometry');
    expect(set.arguments, <String, Object>{
      'left': 1086,
      'top': 366,
      'width': 360,
      'height': 420,
    });
  });

  group('a saved position survives a restart', () {
    // The whole point, as one round trip rather than two halves. Saving was
    // never the problem: `_saveGeometry` coalesced at 250 ms and wrote every
    // time. Restoring was, because nothing told the runner to move - it read
    // the runner's default back and believed it. Both halves can pass while the
    // round trip fails, which is how this shipped.

    // A plain `test`, not `testWidgets`: `_saveGeometry` coalesces on a real
    // 250 ms Timer, and a widget test's fake clock never advances one. This is
    // about a file appearing on disk, so it wants real elapsed time — the same
    // reasoning `first_launch_test` gives for the debounce.
    test('a position written by one launch is the next launch\'s position', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final TestHarness first = TestHarness.build(isWidgetSurface: true);
      addTearDown(() => first.disposeKeepingProfile());

      // Launch one: drag the widget, and let the coalesced save land.
      await first.widgetState();
      final WidgetNotes one = WidgetNotes(first);
      await one.onGeometryChanged(
        const NativeBounds(left: 1086, top: 366, width: 360, height: 420),
      );
      await waitForContent(File('${first.path}\\widget_state.json'), '1086');
      await first.drain;

      // The evidence is on disk, not in a field: a restart re-reads the file.
      final File state = File('${first.path}\\widget_state.json');
      expect(state.existsSync(), isTrue,
          reason: 'precondition: the drag reached the file');
      expect((state.readAsStringSync()).contains('1086'), isTrue,
          reason: 'and the position it reached is the one that was dragged');

      // Launch two, same directory. `disposeKeepingProfile` is the whole
      // reason this is a restart and not a fresh install - `dispose` deletes
      // the directory, which would silently turn the next half into a first
      // launch that finds nothing and therefore passes for the wrong reason.
      await first.disposeKeepingProfile();
      final TestHarness second =
          TestHarness.build(isWidgetSurface: true, at: first.path);
      addTearDown(() => second.dispose());

      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        ShellChannel.methodChannel,
        (MethodCall call) async {
          calls.add(call);
          // The runner's own default, top-right - what the widget wrongly came
          // back to before, and what a read-back would hand back here too.
          return <String, Object>{'left': 1548, 'top': 12, 'width': 360, 'height': 420};
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ShellChannel.methodChannel, null);
      });

      await second.widgetState();

      final MethodCall? restore = calls
          .where((MethodCall c) => c.method == 'widget.setGeometry')
          .cast<MethodCall?>()
          .firstWhere((MethodCall? c) => true, orElse: () => null);
      expect(restore, isNotNull,
          reason: 'the second launch has a saved position and did not send it');
      expect((restore!.arguments as Map)['left'], 1086);
      expect((restore.arguments as Map)['top'], 366);
    });

    test('the saved position wins over whatever the runner reports', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // The inverse half, stated directly: asking the runner is allowed, but it
      // must not be the source of truth when a position was saved. A read-back
      // returns the default, so believing it is the bug.
      final TestHarness harness = TestHarness.build(isWidgetSurface: true);
      addTearDown(() => harness.dispose());
      File('${harness.path}\\widget_state.json')
          .writeAsStringSync('{"left": 40, "top": 50, "width": 360, "height": 420}');

      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        ShellChannel.methodChannel,
        (MethodCall call) async {
          calls.add(call);
          return <String, Object>{'left': 1548, 'top': 12, 'width': 360, 'height': 420};
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ShellChannel.methodChannel, null);
      });

      await harness.widgetState();
      final WidgetNotes state = WidgetNotes(harness);

      expect(state.window.left, 40, reason: 'the saved position, not the default');
      expect(state.window.top, 50);
      expect(calls.any((MethodCall c) => c.method == 'widget.getBounds'), isFalse,
          reason: 'no read-back: widget.setGeometry only queues the move, so a '
              'read-back issued straight after can be answered before the window '
              'has moved, handing back the default this replaced');
    });
  });

  testWidgets('the runner is asked where the widget is, for a first run',
      (WidgetTester tester) async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      ShellChannel.methodChannel,
      (MethodCall call) async {
        calls.add(call);
        return <String, Object>{'left': 7, 'top': 9, 'width': 360, 'height': 420};
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ShellChannel.methodChannel, null);
    });

    final NativeBounds? live = await ShellChannel().widgetBounds();

    expect(calls.single.method, 'widget.getBounds');
    expect(live, isNotNull);
    expect(live?.left, 7);
    expect(live?.top, 9);
  });

  /// The container behind the widget surface.
  ///
  /// Built with `isWidgetSurface: true` because the graph that serves the desktop
  /// widget differs from the editor's in exactly one way that matters here: the
  /// widget registers the directory watcher on `notes.json`, because the editor is
  /// the writer and this side is the reader.
  late TestHarness harness;

  setUp(() {
    // Required, not cosmetic. `WidgetNotifier.build` awaits its window
    // configuration call, and a MethodChannel with nothing behind it returns a
    // Future that never completes - which under flutter_test is not a failure
    // but a test that hangs forever.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.winnotes/shell'),
      (MethodCall call) async => null,
    );
    harness = TestHarness.build(isWidgetSurface: true);
  });

  tearDown(() async {
    await harness.dispose();
  });

  Note note(String id, String title, String body, {int minute = 0}) => Note(
        id: id,
        title: title,
        body: body,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1, 12, minute),
      );

  /// [WidgetTester.runAsync] with a non-nullable result.
  ///
  /// `runAsync` returns `T?` because its callback is allowed to return null, and
  /// every callback in this file returns something that cannot be. Thirty `!` marks
  /// on the results read as noise and hide where the real assertions are - and, as it
  /// turned out, they do not even silence the analyzer, because a `!` on a local that
  /// is then awaited reads as a precedence question rather than a guarantee.
  ///
  /// One place to say it instead.
  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async {
    final Object? result = await tester.runAsync<T>(body);
    // Tested rather than asserted with `!`, which the analyzer rejects on a `T` that
    // could be instantiated as `void` - and `T` is `void` for any callback whose
    // result nobody reads.
    if (result == null && null is! T) return result as T;
    return result as T;
  }

  /// Seeds [notes] and warms the providers, the way the widget isolate does.
  ///
  /// Must be called inside [WidgetTester.runAsync]: these are real file writes, and
  /// a widget test's fake clock never advances the real event loop, so awaiting
  /// them outside it hangs.
  ///
  /// The warm-up has to happen here rather than at the first widget build, because a
  /// provider built during `pumpWidget` issues its read under the fake clock - which
  /// never completes, so the surface stays in `isLoading` and every finder returns
  /// zero widgets. No exception, no log; the app just looks stuck. See
  /// `docs/testing_pattern.md` §4.
  Future<WidgetNotes> makeController(
    WidgetTester tester,
    List<Note> notes, {
    Future<void> Function(SettingsNotifier)? tweakSettings,
  }) async {
    final NotesRepository repo = NotesRepository(AtomicJsonFile(harness.notesFile));
    await repo.saveNow(notes);

    // Settings first: `widgetPositionLocked` reaches the surface as state, and the
    // window configuration the notifier sends on build has to already reflect it.
    final SettingsNotifier settings = await harness.settings();
    await tweakSettings?.call(settings);

    await harness.widgetState();
    return WidgetNotes(harness);
  }

  Future<void> pumpSurface(
    WidgetTester tester, {
    required double width,
    required double height,
  }) async {
    await tester.pumpWidget(
      harness.wrap(
        MaterialApp(
          theme: buildWinNotesTheme(
            brightness: Brightness.light,
            highContrast: false,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: height,
                // No parameters, and that is the migration's point: the surface
                // reads its notes, palette and acrylic flag from providers.
                child: const WidgetSurface(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders a scrolling list of every note without throwing',
      (WidgetTester tester) async {
    await real(tester,
      () => makeController(tester, <Note>[
        note('a', 'Groceries', 'Milk, sourdough\nCheck the bike light'),
        note('b', 'Reading list', 'The Design of Everyday Things', minute: -5),
        note('c', 'Ideas', 'Widget per monitor?', minute: -12),
      ]),
    );

    // The regression this guards: building this subtree used to throw during
    // sliver layout and paint a red error screen over the desktop.
    await pumpSurface(tester, width: 360, height: 420);

    expect(tester.takeException(), isNull);
    expect(find.byType(WidgetNoteCard), findsNWidgets(3));
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Reading list'), findsOneWidget);
    expect(find.text('Ideas'), findsOneWidget);
  });

  testWidgets('the most recent note is the focused, large card',
      (WidgetTester tester) async {
    final WidgetNotes controller = await real(tester, 
      () => makeController(tester, <Note>[
        note('old', 'Older note', 'written earlier', minute: -30),
        note('new', 'Newest note', 'written last', minute: 0),
      ]),
    );

    await pumpSurface(tester, width: 360, height: 420);

    expect(controller.focusedNote!.id, 'new');
    final Iterable<WidgetNoteCard> cards =
        tester.widgetList<WidgetNoteCard>(find.byType(WidgetNoteCard));
    expect(cards.first.focused, isTrue);
    expect(cards.first.roomy, isTrue);
    expect(cards.first.noteId, 'new');
    expect(cards.skip(1).every((WidgetNoteCard c) => !c.roomy || !c.focused), isTrue);
  });

  testWidgets('selecting an older note from the widget makes it focused',
      (WidgetTester tester) async {
    final WidgetNotes controller = await real(tester, 
      () => makeController(tester, <Note>[
        note('old', 'Older note', 'written earlier', minute: -30),
        note('new', 'Newest note', 'written last', minute: 0),
      ]),
    );

    await pumpSurface(tester, width: 360, height: 420);
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
    final Iterable<WidgetNoteCard> cards =
        tester.widgetList<WidgetNoteCard>(find.byType(WidgetNoteCard));
    expect(cards.first.noteId, 'old');
    expect(cards.first.focused, isTrue);
  });

  testWidgets('falls back to compact cards when the widget is small',
      (WidgetTester tester) async {
    await real(tester,
      () => makeController(tester, <Note>[
        note('a', 'Groceries', 'a body long enough to need several lines'),
      ]),
    );

    // Below the threshold there is no room for a large card.
    await pumpSurface(tester, width: 150, height: 140);

    expect(tester.takeException(), isNull);
    final Iterable<WidgetNoteCard> cards =
        tester.widgetList<WidgetNoteCard>(find.byType(WidgetNoteCard));
    expect(cards.single.roomy, isFalse);
  });

  testWidgets('shows a quiet line rather than crashing when notes vanish',
      (WidgetTester tester) async {
    final WidgetNotes controller = await real(tester, 
      () => makeController(tester, <Note>[note('a', 'Only note', 'text')]),
    );

    await pumpSurface(tester, width: 360, height: 420);
    expect(find.byType(WidgetNoteCard), findsOneWidget);

    // The last note is deleted while the widget is on screen.
    File(harness.notesFile).writeAsStringSync(
      '{"format":"winnotes","version":1,"notes":[]}',
    );
    await tester.runAsync(() => controller.load());

    await pumpSurface(tester, width: 360, height: 420);
    expect(tester.takeException(), isNull);
    expect(find.text('No notes'), findsOneWidget);
  });

  testWidgets('a list too long for the widget scrolls', (WidgetTester tester) async {
    final WidgetNotes controller = await real(tester, 
      () => makeController(tester, <Note>[
        for (int i = 0; i < 30; i++)
          note('n$i', 'Note $i', 'body $i', minute: -i),
      ]),
    );

    await pumpSurface(tester, width: 360, height: 420);
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
    final ScrollableState scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
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

  testWidgets('the position lock reaches the runner', (WidgetTester tester) async {
    // The switch is only worth having if it changes what the native window
    // does, so this checks the payload the runner actually receives rather than
    // the Dart field that produced it.
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.winnotes/shell'),
      (MethodCall call) async {
        if (call.method == 'widget.configure') calls.add(call);
        return null;
      },
    );

    await real(tester,
      () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
    );

    expect(calls, isNotEmpty, reason: 'the widget never configured itself');
    expect(
      (calls.first.arguments as Map)['positionLocked'],
      isFalse,
      reason: 'a fresh install must not ship a widget that cannot be moved',
    );

    // Turning the lock off has to reach the runner as a live change, not need a
    // restart.
    await real(tester,
      () => makeController(
        tester,
        <Note>[note('a', 'Groceries', 'milk')],
        tweakSettings: (SettingsNotifier s) =>
            s.apply((WinNotesSettings v) => v.copyWith(widgetPositionLocked: false)),
      ),
    );

    final List<MethodCall> configures = calls.where((MethodCall c) => c.method == 'widget.configure').toList();
    expect(
      (configures.last.arguments as Map)['positionLocked'],
      isFalse,
      reason: 'unlocking must be pushed, not merely stored',
    );
  });

  testWidgets('a refused drag explains itself instead of doing nothing',
      (WidgetTester tester) async {
    // The bug this guards: locked, the native window reports HTCLIENT, the drag
    // never starts, and nothing at all happens. Someone dragging a locked
    // widget has no way to tell the lock is why.
    await real(tester,
      () => makeController(
        tester,
        <Note>[note('a', 'Groceries', 'milk')],
        tweakSettings: (SettingsNotifier s) =>
            s.apply((WinNotesSettings v) => v.copyWith(widgetPositionLocked: true)),
      ),
    );

    await pumpSurface(tester, width: 360, height: 420);
    expect(find.textContaining('Locked in place'), findsNothing,
        reason: 'the hint must not appear before anyone has tried to drag');

    final TestGesture gesture = await tester.startGesture(const Offset(180, 120));
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

  testWidgets('an unlocked widget does not nag about dragging', (WidgetTester tester) async {
    await real(tester,
      () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
    );

    await pumpSurface(tester, width: 360, height: 420);
    final TestGesture gesture = await tester.startGesture(const Offset(180, 120));
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
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.winnotes/shell'),
      (MethodCall call) async {
        if (call.method == 'widget.beginMove' || call.method == 'widget.beginResize') {
          calls.add(call);
        }
        return null;
      },
    );
    return calls;
  }

  Future<void> dragBody(WidgetTester tester, {double dy = 12}) async {
    final TestGesture gesture = await tester.startGesture(const Offset(180, 120));
    // Four steps past the 8px threshold, the way a real drag arrives.
    for (int i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(0, dy));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a drag is handed to the runner with its anchor', (WidgetTester tester) async {
    // The bug this guards: the widget reported HTCAPTION for its body and
    // waited for Windows to run a move loop. There was no loop - the window is a
    // borderless WS_POPUP with neither WS_CAPTION nor WS_THICKFRAME - and the
    // Flutter view covered the client area, so the hit test was never consulted
    // either. The widget could not be moved or resized at all.
    final List<MethodCall> calls = recordHandOffs();
    await real(tester,
      () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
    );

    // One note, so the list has nothing to scroll and the drag is unambiguous.
    await pumpSurface(tester, width: 360, height: 420);
    await dragBody(tester);

    final List<MethodCall> moves = calls.where((MethodCall c) => c.method == 'widget.beginMove').toList();
    expect(moves, hasLength(1),
        reason: 'an unlocked widget with nothing to scroll must hand the drag '
            'to the runner exactly once');
    // The anchor travels with it: the runner is told about a drag only after the
    // pointer has already travelled, so anchoring on the cursor at that moment
    // would throw away the whole first hop.
    final Map<dynamic, dynamic> anchor = moves.single.arguments as Map;
    expect(anchor['anchorX'], 180.0);
    expect(anchor['anchorY'], 120.0);
  });

  testWidgets('a scroll wins over a drag while there is more list to read',
      (WidgetTester tester) async {
    // Drags and scrolls are the same gesture shape. Deciding by the scroll
    // extent rather than by whichever notification arrives first is what makes
    // this reliable; getting the direction backwards hands every upward drag to
    // the window, which is the direction people most often use to scroll.
    final List<MethodCall> calls = recordHandOffs();
    await real(tester,
      () => makeController(tester, <Note>[
        for (int i = 0; i < 30; i++)
          note('n$i', 'Note $i', 'body $i', minute: -i),
      ]),
    );

    await pumpSurface(tester, width: 360, height: 420);

    final ScrollableState scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0),
        reason: 'the test is meaningless unless the list really does overflow');

    // At the top of the list, dragging up has to scroll.
    await dragBody(tester, dy: -12);
    expect(calls.where((MethodCall c) => c.method == 'widget.beginMove'), isEmpty,
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
    expect(calls.where((MethodCall c) => c.method == 'widget.beginMove'), hasLength(1),
        reason: 'at the end of the list, the widget should come with the drag');
  });

  testWidgets('at the top of the list, dragging down moves the widget',
      (WidgetTester tester) async {
    // The other half of the same rule: dragging down at the top has nothing to
    // scroll, so it belongs to the window rather than being swallowed.
    final List<MethodCall> calls = recordHandOffs();
    await real(tester,
      () => makeController(tester, <Note>[
        for (int i = 0; i < 30; i++)
          note('n$i', 'Note $i', 'body $i', minute: -i),
      ]),
    );

    await pumpSurface(tester, width: 360, height: 420);
    await dragBody(tester, dy: 12);

    expect(calls.where((MethodCall c) => c.method == 'widget.beginMove'), hasLength(1));
  });

  testWidgets('a locked widget is not handed to the runner', (WidgetTester tester) async {
    final List<MethodCall> calls = recordHandOffs();
    await real(tester,
      () => makeController(
        tester,
        <Note>[note('a', 'Groceries', 'milk')],
        tweakSettings: (SettingsNotifier s) =>
            s.apply((WinNotesSettings v) => v.copyWith(widgetPositionLocked: true)),
      ),
    );

    await pumpSurface(tester, width: 360, height: 420);
    await dragBody(tester);

    expect(calls, isEmpty,
        reason: 'a locked widget must not start a drag the runner would act on');
  });

  testWidgets('grabbing an edge hands a resize to the runner, with the edge',
      (WidgetTester tester) async {
    final List<MethodCall> calls = recordHandOffs();
    await real(tester,
      () => makeController(tester, <Note>[
        for (int i = 0; i < 30; i++)
          note('n$i', 'Note $i', 'body $i', minute: -i),
      ]),
    );

    await pumpSurface(tester, width: 360, height: 420);

    // Bottom edge, well clear of the corners. The band has to be wider than the
    // window's rounded corner, because the native region clips those pixels away
    // and a grab aimed at the literal corner arrives at nothing.
    final TestGesture gesture = await tester.startGesture(const Offset(180, 415));
    for (int i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    final List<MethodCall> resizes = calls.where((MethodCall c) => c.method == 'widget.beginResize').toList();
    expect(resizes, hasLength(1), reason: 'an edge grab is a resize');
    expect((resizes.single.arguments as Map)['edge'], 4,
        reason: "4 is the runner's code for the bottom edge");
    expect(calls.where((MethodCall c) => c.method == 'widget.beginMove'), isEmpty);
  });

  testWidgets('a press that does not move is not a drag', (WidgetTester tester) async {
    // Cards have to stay tappable, so a press and a release with no travel must
    // never turn into a drag.
    final List<MethodCall> calls = recordHandOffs();
    await real(tester,
      () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
    );

    await pumpSurface(tester, width: 360, height: 420);

    final TestGesture gesture = await tester.startGesture(const Offset(180, 120));
    await gesture.moveBy(const Offset(2, 3));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(calls, isEmpty, reason: 'below the threshold this is just a tap');
  });

  group('marking a task finished from the widget', () {
    /// Answers `editor.running`, and records who was asked to do the writing.
    List<MethodCall> recordWriter({required bool editorRunning}) {
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.winnotes/shell'),
        (MethodCall call) async {
          if (call.method == 'editor.running') return editorRunning;
          if (call.method == 'note.toggleCompleted') calls.add(call);
          return null;
        },
      );
      return calls;
    }

    testWidgets('with an editor open, the widget asks rather than writes',
        (WidgetTester tester) async {
      // The invariant this whole feature has to respect: notes.json has one
      // writer, and while the editor is open that is the editor. Writing from
      // here would overwrite whatever was typed in the last quarter of a second
      // and before that, silently.
      final List<MethodCall> requests = recordWriter(editorRunning: true);
      final WidgetNotes controller = await real(tester, 
        () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
      );
  
      await tester.runAsync(() => controller.toggleCompleted('a'));
      await tester.pump();

      expect(requests, hasLength(1),
          reason: 'the toggle must be routed to the writer');
      expect((requests.single.arguments as Map)['id'], 'a');
    });

    testWidgets('with no editor, the widget writes the file itself',
        (WidgetTester tester) async {
      // An autostart launch has no editor at all, and refusing to work there
      // would mean the feature only exists for people who opened the app first.
      // With no editor there is no other writer and no buffered edits, so this
      // surface is the only one that can safely do it.
      final List<MethodCall> requests = recordWriter(editorRunning: false);
      final WidgetNotes controller = await real(tester, 
        () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
      );
  
      await tester.runAsync(() async {
        await controller.toggleCompleted('a');
        // The write is queued behind a debounce, exactly as it would be in the
        // app, so the test has to let it out the same way quitting does.
        await controller.flush();
      });
      await tester.pump();

      expect(requests, isEmpty,
          reason: 'nobody to route to, so it must not try');

      final String raw = File(harness.notesFile).readAsStringSync();
      expect(raw, contains('completedAt'),
          reason: 'the change has to reach disk, not just the screen');
      expect(controller.notes.single.isCompleted, isTrue);
    });

    testWidgets('a queued toggle survives quitting inside the debounce window',
        (WidgetTester tester) async {
      // The write this surface makes goes through the debounced queue like every
      // other write. If the surface's flush did not drain notes.json, quitting
      // within a quarter of a second of ticking a task would silently undo it -
      // and only that, and only sometimes, which is the worst way for it to
      // break.
      recordWriter(editorRunning: false);
      final WidgetNotes controller = (await real(tester, 
        () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
      ));

      await tester.runAsync(() async {
        await controller.toggleCompleted('a');
        await controller.flush();
        await controller.release();
      });

      expect(File(harness.notesFile).readAsStringSync(),
          contains('completedAt'));
    });

    testWidgets('the card offers a tick that does not also focus the note',
        (WidgetTester tester) async {
      // Tapping a card means "I am working on this"; ticking it means "this is
      // done". Conflating them would move the editor's selection every time
      // someone worked through a list, which is the one thing this must not do.
      final List<MethodCall> requests = recordWriter(editorRunning: true);
      final WidgetNotes controller = await real(tester, 
        () => makeController(tester, <Note>[
          note('a', 'Task one', 'first'),
          note('b', 'Task two', 'second', minute: -5),
        ]),
      );
  
      await pumpSurface(tester, width: 360, height: 420);
      final String before = controller.focusedNote!.id;

      // The tick sits to the left of the text, clear of the resize band that
      // owns the outer edge of the widget.
      final Finder toggle = find.byType(CompletionToggle).first;
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(controller.focusedNote!.id, before,
          reason: 'ticking a task off must not drag the selection with it');
    });

    testWidgets('a finished card draws a line through its text', (WidgetTester tester) async {
      final WidgetNotes controller = await real(tester, 
        () => makeController(tester, <Note>[note('a', 'Task one', 'first')]),
      );
  
      await pumpSurface(tester, width: 360, height: 420);
      expect(_strikethroughCount(tester), 0);

      await tester.runAsync(() => controller.toggleCompleted('a'));
      await tester.pumpAndSettle();

      expect(_strikethroughCount(tester), greaterThan(0),
          reason: 'the line through the text is the whole signal');
    });
  });

  group('the widget hides rather than showing an empty list', () {
    // §3.12. A widget sitting on the desktop with nothing in it is noise, and
    // the editor is one hotkey away. This also means there is no way to add the
    // first note from the widget - a deliberate trade, recorded as a known
    // consequence in AGENTS.md §4.
    testWidgets('no note with text means the widget is not shown', (WidgetTester tester) async {
      final WidgetNotes controller = await real(tester, 
        () => makeController(tester, <Note>[note('a', '', '')]),
      );
        await tester.runAsync(controller.load);

      expect(controller.hasAnyNoteWithText, isFalse);
      expect(controller.widgetVisible, isFalse);
    });

    testWidgets('one note with text is enough to show it', (WidgetTester tester) async {
      final WidgetNotes controller = await real(tester, 
        () => makeController(tester, <Note>[
          note('a', '', ''),
          note('b', 'Groceries', 'milk'),
        ]),
      );
        await tester.runAsync(controller.load);

      expect(controller.hasAnyNoteWithText, isTrue);
      expect(controller.widgetVisible, isTrue);
    });

    // Not tested here: emptying the last note *from the editor* and watching the
    // widget notice. That path goes through the directory watcher and a debounce,
    // so a test would be asserting on timing rather than on a rule. It is
    // covered by the reload path in notes_controller_test instead.
  });

  group('the startup ladder tells the runner to hide, or to show', () {
    // AGENTS.md §5.1, still open. The rule itself is tested above; what is
    // untested is the ladder that carries it to the runner. `_applyWindowConfiguration`
    // returns early when `settings` has no value yet, and the `ref.listen` that
    // would correct it only fires on a *change* - so if settings were already
    // resolved before `build` ran, nothing ever sends `visible: false`.
    //
    // This asserts the wire, not the state: `widgetVisible` being false in Dart
    // is not the claim, the runner having been told is.

    /// Records every `widget.configure`, and answers everything else.
    List<MethodCall> recordConfigure() {
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        ShellChannel.methodChannel,
        (MethodCall call) async {
          calls.add(call);
          return <String, Object>{'left': 0, 'top': 0, 'width': 360, 'height': 420};
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ShellChannel.methodChannel, null);
      });
      return calls;
    }

    bool? configuredVisible(List<MethodCall> calls) {
      final Iterable<MethodCall> configures =
          calls.where((MethodCall c) => c.method == 'widget.configure');
      if (configures.isEmpty) return null;
      return (configures.last.arguments as Map)['visible'] as bool?;
    }

    testWidgets('a note with text is announced as visible',
        (WidgetTester tester) async {
      final List<MethodCall> calls = recordConfigure();
      await real(tester, () => makeController(tester, <Note>[
            note('a', 'Groceries', 'milk'),
          ]));

      expect(configuredVisible(calls), isTrue,
          reason: 'one note with text means the widget is shown, and the runner '
              'has to be told - a state field it cannot read proves nothing');
    });

    testWidgets('no note with text is announced as hidden',
        (WidgetTester tester) async {
      final List<MethodCall> calls = recordConfigure();
      await real(tester, () => makeController(tester, <Note>[note('a', '', '')]));

      expect(configuredVisible(calls), isFalse,
          reason: 'this is the §5.1 symptom: the widget painting an empty '
              'desktop because nobody sent the runner a visibility decision');
    });

    // OPEN, and deliberately not written as a passing test. `AGENTS.md` §5.1
    // reports the widget painting on a first launch when it should have hidden,
    // and the lead is that `_applyWindowConfiguration` returns early when
    // settings have no value while the surface builds, and the `ref.listen`
    // that would correct it only fires on a change.
    //
    // Driving that ordering here hangs rather than fails: `makeController`
    // resolves settings before the surface on purpose, and building the surface
    // first leaves the settings provider unresolved under `runAsync`. A test
    // that cannot complete teaches nothing, and a test that completes by
    // arranging the order it was worried about would teach the wrong thing.
    //
    // So the rule is pinned from the two sides that do run (above), the
    // reproduction stays a probe in `docs/testing/reporting.md`, and the fix
    // has to bring its own evidence.
    //
    // skip: 'AGENTS.md §5.1 is unrooted; this ordering does not complete under
    // the harness. Wave 1 of diagnostics_plan.md records it as open rather than
    // pinning a pass.'
    testWidgets('hiding survives settings resolving after the surface',
        (WidgetTester tester) async {}, skip: true);
  });

  group('the add-a-note composer', () {
    /// Records compose-mode and note-creation calls.
    List<MethodCall> recordComposer({bool editorRunning = true}) {
      final List<MethodCall> calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.winnotes/shell'),
        (MethodCall call) async {
          if (call.method == 'editor.running') return editorRunning;
          if (call.method == 'widget.setComposeMode' ||
              call.method == 'note.create') {
            calls.add(call);
          }
          return null;
        },
      );
      return calls;
    }

    testWidgets('the field is not there until you ask for it', (WidgetTester tester) async {
      // "Otherwise not" is the point. A text field sitting permanently at the
      // bottom of every widget would cost 36 pixels of a 420px window and read as
      // an input the widget wants something from.
      await real(tester,
        () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
      );
  
      await pumpSurface(tester, width: 360, height: 420);

      expect(find.byKey(addNoteFieldKey), findsNothing);
      expect(find.byKey(addNoteButtonKey), findsOneWidget,
          reason: 'the affordance that opens it does exist');
    });

    testWidgets('opening it asks the runner for the keyboard, closing gives it back',
        (WidgetTester tester) async {
      // The whole feature rests on this. The widget is WS_EX_NOACTIVATE so that
      // clicking it never steals the caret, which is also why it cannot hold a
      // text field at all - so it borrows the keyboard for exactly as long as the
      // composer is open. An always-on-top widget that kept the caret would be
      // the most irritating thing on the desktop.
      final List<MethodCall> calls = recordComposer();
      await real(tester,
        () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
      );
  
      await pumpSurface(tester, width: 360, height: 420);

      await tester.tap(find.byKey(addNoteButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(addNoteFieldKey), findsOneWidget);
      expect(
        calls.where((MethodCall c) => c.method == 'widget.setComposeMode'
            && (c.arguments as Map)['active'] == true),
        hasLength(1),
      );

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byKey(addNoteFieldKey), findsNothing);
      expect(
        calls.where((MethodCall c) => c.method == 'widget.setComposeMode'
            && (c.arguments as Map)['active'] == false),
        hasLength(1),
      );
    });

    testWidgets('a jotted line becomes a note, routed to the editor',
        (WidgetTester tester) async {
      final List<MethodCall> calls = recordComposer();
      await real(tester,
        () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
      );
  
      await pumpSurface(tester, width: 360, height: 420);
      await tester.tap(find.byKey(addNoteButtonKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(addNoteFieldKey), 'Call the dentist');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final List<MethodCall> created =
          calls.where((MethodCall c) => c.method == 'note.create').toList();
      expect(created, hasLength(1));
      final Map<dynamic, dynamic> args = created.single.arguments as Map;
      expect(args['title'], 'Call the dentist');
      expect(args['body'], '');
      // Closed before the write, so the keyboard is on its way back to the user's
      // app rather than sitting in the widget while the round trip happens.
      expect(find.byKey(addNoteFieldKey), findsNothing);
    });

    testWidgets('with no editor, the widget writes the note itself',
        (WidgetTester tester) async {
      final List<MethodCall> calls = recordComposer(editorRunning: false);
      final WidgetNotes controller = await real(tester, 
        () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
      );
  
      await pumpSurface(tester, width: 360, height: 420);
      await tester.tap(find.byKey(addNoteButtonKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(addNoteFieldKey), 'Water the plants');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(calls.where((MethodCall c) => c.method == 'note.create'), isEmpty,
          reason: 'nobody to route to');
      expect(controller.notes.map((Note n) => n.title), contains('Water the plants'));

      // Writing here goes through the debounced queue like every other write, and
      // a widget test's fake clock never advances the real event loop - so the
      // flush has to happen under the real one or the pending timer fails the
      // test on the way out.
      await tester.runAsync(() async {
        await controller.flush();
        await controller.release();
      });

      expect(File(harness.notesFile).readAsStringSync(),
          contains('Water the plants'),
          reason: 'and it has to reach disk, not just the widget');
    });

    testWidgets('saving nothing just closes it', (WidgetTester tester) async {
      // Enter on an empty field must not make an empty note. Deleting the last
      // character of a note is not the same as making one.
      final List<MethodCall> calls = recordComposer();
      final WidgetNotes controller = await real(tester, 
        () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
      );
  
      await pumpSurface(tester, width: 360, height: 420);
      await tester.tap(find.byKey(addNoteButtonKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(addNoteFieldKey), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(calls.where((MethodCall c) => c.method == 'note.create'), isEmpty);
      expect(find.byKey(addNoteFieldKey), findsNothing);
      expect(controller.notes, hasLength(1));
    });

    testWidgets('the widget cannot be dragged while composing', (WidgetTester tester) async {
      // The grab band runs along the bottom of the widget, which is exactly where
      // the field sits. Without this, clicking near the field's edge would resize
      // the window instead of placing the caret.
      final List<MethodCall> calls = recordComposer();
      await real(tester,
        () => makeController(tester, <Note>[note('a', 'Groceries', 'milk')]),
      );
  
      await pumpSurface(tester, width: 360, height: 420);
      await tester.tap(find.byKey(addNoteButtonKey));
      await tester.pumpAndSettle();

      // Bottom edge, mid-width: squarely inside the resize band.
      final TestGesture gesture = await tester.startGesture(const Offset(180, 416));
      for (int i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, -12));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(calls.where((MethodCall c) => c.method == 'widget.beginResize'), isEmpty);
      expect(calls.where((MethodCall c) => c.method == 'widget.beginMove'), isEmpty);
      expect(find.byKey(addNoteFieldKey), findsOneWidget,
          reason: 'the composer should still be open, not disturbed');
    });
  });
}

/// Counts the rendered texts on a card that are struck through.
///
/// Walks the text widgets rather than looking for the decoration on one
/// particular string, because a card has a title and a preview and the test
/// should pass if either of them carries the line.
int _strikethroughCount(WidgetTester tester) {
  int count = 0;
  for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
    if (text.style?.decoration == TextDecoration.lineThrough) count++;
  }
  return count;
}
