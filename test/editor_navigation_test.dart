import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/features/notes/presentation/providers/editor_layout_provider.dart';
import 'package:win_notes/features/notes/presentation/screens/editor_app/editor_app.dart';

import 'package:win_notes/features/notes/presentation/widgets/list_drawer_handle/list_drawer_handle.dart';
import 'package:win_notes/features/notes/presentation/widgets/note_list_pane/note_list_pane.dart';
import 'package:win_notes/features/notes/presentation/widgets/pane_divider/pane_divider.dart';
import 'helpers/provider_harness.dart';
import 'package:win_notes/features/settings/presentation/screens/settings_dialog/settings_dialog.dart';

/// Tests for the editor surface's own navigation.
///
/// These exist because of a real bug that no amount of clicking would have
/// explained. `EditorApp.build` returns a `MaterialApp`, which makes this
/// State's own `context` sit *above* the Navigator it creates. Every call of
/// the form `showDialog(context: context, ...)` from this State therefore had no
/// Navigator ancestor and threw instead of showing anything.
///
/// The visible result was silence: the overflow menu opened, the Settings row
/// was clicked, the menu closed, and no dialog appeared. Export still worked,
/// because it reached for a native file dialog first and only fell over on the
/// snackbar afterwards - so the bug looked like "Settings does nothing" rather
/// than "a context is in the wrong place".
///
/// Nothing else in the codebase was affected, because every other caller is a
/// descendant widget whose context is genuinely below the MaterialApp. These
/// tests pin that distinction down by driving the real menu.
void main() {
  // The container behind the editor, so the surface's providers resolve to a temp
  // profile and the test can read them back.
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
      await harness.drain();
      await harness.dispose();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    File(harness.notesFile).writeAsStringSync(
      '{"format":"winnotes","version":1,"notes":['
      '{"id":"a","title":"Groceries","body":"Milk",'
      '"createdAt":"2026-01-01T09:00:00.000Z",'
      '"updatedAt":"2026-01-01T09:00:00.000Z"}]}',
    );

    // **Warm the providers inside `runAsync`, before the first `pumpWidget`.**
    //
    // This is the trap that makes the whole migration look broken, and it is worth
    // stating plainly: a provider is built the first time it is *read*, and reading it
    // for the first time during `pumpWidget` means its file I/O is issued under the
    // test's fake clock. That clock never advances, so the read never completes, the
    // provider stays in `isLoading`, and the editor renders the empty frame forever.
    // Nothing throws, nothing logs - the app simply looks like it is stuck.
    //
    // Awaiting `notesProvider.future` under `runAsync` lets the real event loop run, so
    // by the time the widget tree is pumped the state is already there. See
    // `docs/testing_pattern.md` §4 and the same shape in `palette_test`.
    await tester.runAsync(() async {
      await harness.notes();
      await harness.settings();
    });

    await tester.pumpWidget(harness.wrap(const EditorApp()));
    await tester.pumpAndSettle();
  }

  /// Opens the overflow menu and picks a row by its visible label.
  Future<void> chooseFromMenu(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('the note list is a drawer, not a fixture', () {
    // The list is something the user hides *to write*, and at that moment they
    // are looking at the editor rather than up at the toolbar. So there is an
    // edge handle as well as the bar button, and the handle is the way back.
    testWidgets('it opens wide, and the bar button closes it',
        (WidgetTester tester) async {
      await pumpEditor(tester);

      expect(find.byType(NoteListPane), findsOneWidget);
      expect(find.byType(ListDrawerHandle), findsNothing);

      await tester.tap(find.byTooltip('Hide notes'));
      await tester.pumpAndSettle();

      expect(find.byType(NoteListPane), findsNothing,
          reason: 'the whole point: the space goes to the editor');
      expect(find.byType(ListDrawerHandle), findsOneWidget,
          reason: 'and something is left on the edge to open it again');
    });

    testWidgets('the edge handle opens it again',
        (WidgetTester tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Hide notes'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ListDrawerHandle));
      await tester.pumpAndSettle();

      expect(find.byType(NoteListPane), findsOneWidget);
      expect(find.byType(ListDrawerHandle), findsNothing);
    });

    testWidgets('the handle has a hit area, not just an icon',
        (WidgetTester tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Hide notes'));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(ListDrawerHandle)).width,
          greaterThanOrEqualTo(12),
          reason: 'a 16px strip is a target; a 16px icon in a 2px strip is not');
    });

    testWidgets('the list divider resizes the list', (WidgetTester tester) async {
      await pumpEditor(tester);

      final double before = tester.getSize(find.byType(NoteListPane)).width;
      expect(before, closeTo(300, 1), reason: 'precondition: the design width');

      await tester.dragFrom(
        tester.getCenter(find.byType(PaneDivider).first),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(NoteListPane)).width, greaterThan(before));
    });

    testWidgets('collapsing is session state, not a stored preference',
        (WidgetTester tester) async {
      // Session state on purpose, so this is the honest shape of it: the
      // container keeps it for as long as it lives, and a *new* container starts
      // with the list open because nothing wrote it to settings.json.
      await pumpEditor(tester);
      await tester.tap(find.byTooltip('Hide notes'));
      await tester.pumpAndSettle();

      expect(harness.container.read(editorLayoutProvider).listCollapsed, isTrue,
          reason: 'the session remembers');

      // A fresh container is a fresh session. `harness.wrap` hands the tree the
      // harness's own container, so this is built directly rather than pumped.
      final ProviderContainer next = ProviderContainer();
      addTearDown(next.dispose);
      expect(next.read(editorLayoutProvider).listCollapsed, isFalse);
      expect(next.read(editorLayoutProvider).listWidth,
          EditorLayout.defaultListWidth,
          reason: 'and the width is not remembered either');
    });
  });

  testWidgets('Settings opens from the overflow menu', (WidgetTester tester) async {
    await pumpEditor(tester);

    // The menu opens and closes; that part always worked, which is exactly why
    // the bug was reported as "the button does nothing".
    await chooseFromMenu(tester, 'Settings');

    expect(find.byType(SettingsDialog), findsOneWidget,
        reason: 'clicking Settings must actually show the dialog');
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('Settings can be opened twice in a row', (WidgetTester tester) async {
    await pumpEditor(tester);

    await chooseFromMenu(tester, 'Settings');
    expect(find.byType(SettingsDialog), findsOneWidget);

    // Close it again.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing,
        reason: 'the dialog has to close, or the second open is blocked by the '
            '_settingsOpen guard and Settings stops working again');

    await chooseFromMenu(tester, 'Settings');
    expect(find.byType(SettingsDialog), findsOneWidget,
        reason: 'the re-open guard has to be released when the dialog closes');
  });

  testWidgets('opening Settings throws nothing', (WidgetTester tester) async {
    await pumpEditor(tester);

    await chooseFromMenu(tester, 'Settings');

    // A failed showDialog surfaces here rather than as a silent no-op, so this
    // is the assertion that would have caught the original bug directly.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the editor is mounted and can still take input', (WidgetTester tester) async {
    await pumpEditor(tester);

    // Proves the editor is really built, so the tests above are failing or
    // passing for real reasons rather than against an empty tree.
    expect(find.text('Search notes'), findsOneWidget);
    expect(find.text('Everything lives on this PC'), findsOneWidget);

    await tester.tap(find.text('New note').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('New note').first, findsOneWidget);
  });
}
