import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/src/core/app_paths.dart';
import 'package:win_notes/src/platform/shell_channel.dart';
import 'package:win_notes/src/ui/editor/editor_app.dart';
import 'package:win_notes/src/ui/settings/settings_dialog.dart';

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
  late Directory temp;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.winnotes/shell'),
      (call) async => null,
    );
    temp = Directory.systemTemp.createTempSync('winnotes_editor_test');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  LaunchInfo launchInfo() => LaunchInfo(
        role: 'editor',
        launchMode: 'plain',
        isWidgetSurface: false,
        dataDirectory: temp.path,
        executablePath: r'E:\app\win_notes.exe',
        isSystemDark: false,
        animationsEnabled: true,
        highContrast: false,
        acrylicSupported: false,
        buildNumber: 1,
        monitors: const [],
        autostartEnabled: false,
        autostartCommand: '',
        defaultWidgetBounds:
            const NativeBounds(left: 0, top: 0, width: 360, height: 420),
      );

  Future<void> pumpEditor(WidgetTester tester) async {
    final paths = AppPaths(
      dataDirectory: temp.path,
      executablePath: r'E:\app\win_notes.exe',
    );
    File(paths.notesFile).writeAsStringSync(
      '{"format":"winnotes","version":1,"notes":['
      '{"id":"a","title":"Groceries","body":"Milk",'
      '"createdAt":"2026-01-01T09:00:00.000Z",'
      '"updatedAt":"2026-01-01T09:00:00.000Z"}]}',
    );

    await tester.pumpWidget(
      EditorApp(shell: ShellChannel(), launch: launchInfo(), paths: paths),
    );
    // The bootstrap reads notes and settings off disk before the first frame
    // settles, and those are real file reads.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
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