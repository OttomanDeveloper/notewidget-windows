import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/features/notes/presentation/screens/editor_app/editor_app.dart';

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
      (call) async => null,
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

  testWidgets('Settings opens from the overflow menu', (tester) async {
    await pumpEditor(tester);

    // The menu opens and closes; that part always worked, which is exactly why
    // the bug was reported as "the button does nothing".
    await chooseFromMenu(tester, 'Settings');

    expect(find.byType(SettingsDialog), findsOneWidget,
        reason: 'clicking Settings must actually show the dialog');
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('Settings can be opened twice in a row', (tester) async {
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

  testWidgets('opening Settings throws nothing', (tester) async {
    await pumpEditor(tester);

    await chooseFromMenu(tester, 'Settings');

    // A failed showDialog surfaces here rather than as a silent no-op, so this
    // is the assertion that would have caught the original bug directly.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the editor is mounted and can still take input', (tester) async {
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
