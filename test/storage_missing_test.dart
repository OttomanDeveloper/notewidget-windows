/// When the folder you chose is not there, the app says so.
///
/// This is a regression test for a bug that had no error message at all. The
/// chosen folder was on a drive; the machine rebooted; the drive was slow to
/// come back; `StorageLocation.followPointer` treats an unreachable folder as
/// "no folder chosen" — correctly, because recreating a missing drive as an
/// empty library is total loss. But it hands the *default* folder to the
/// repositories as well, so the editor opened on a library nobody had chosen
/// and every keystroke went there. The notes were not deleted. They were simply
/// not the ones on screen, and nothing said so.
///
/// Two surfaces made it stranger: they are separate processes, so the editor
/// and the widget could each resolve the pointer at a different moment and end
/// up in different folders on the same machine.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/utils/app_paths.dart';
import 'package:win_notes/core/utils/app_providers.dart';
import 'package:win_notes/features/notes/presentation/screens/editor_app/editor_app.dart';
import 'package:win_notes/features/notes/presentation/widgets/note_editor_pane/note_editor_pane.dart';
import 'package:win_notes/features/notes/presentation/widgets/note_list_pane/note_list_pane.dart';
import 'package:win_notes/features/notes/presentation/widgets/storage_missing_screen/storage_missing_screen.dart';
import 'package:win_notes/features/settings/data/storage_location.dart';
import 'package:win_notes/core/platform/shell_channel.dart' show NativeBounds;

import 'helpers/provider_harness.dart';

void main() {
  late TestHarness harness;
  late String missing;

  setUp(() {
    missing = '${Directory.systemTemp.path}\\wn-not-connected';
    harness = TestHarness.build();
  });

  tearDown(() async {
    await harness.dispose();
  });

  /// The editor over a profile whose chosen folder is not reachable, built the
  /// way `main()` builds it after such a launch.
  Future<void> pumpUnreachable(WidgetTester tester) async {
    final TestHarness unreachable =
        TestHarness.unreachableStorage(chosen: missing, at: harness.path);
    addTearDown(unreachable.dispose);

    await tester.runAsync(() async {
      await unreachable.notes();
      await unreachable.settings();
    });
    await tester.pumpWidget(unreachable.wrap(const EditorApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('the editor says where the notes are instead of opening the wrong ones',
      (WidgetTester tester) async {
    await pumpUnreachable(tester);

    expect(find.byType(StorageMissingScreen), findsOneWidget);
    expect(
      find.textContaining('cannot be opened'),
      findsOneWidget,
      reason: 'the sentence has to say the folder could not be opened, not merely '
          'that there is nothing here',
    );
  });

  testWidgets('it names the folder that was chosen', (WidgetTester tester) async {
    await pumpUnreachable(tester);

    expect(find.textContaining(missing), findsOneWidget);
  });

  testWidgets('nothing is editable, so nothing can be written to the wrong folder',
      (WidgetTester tester) async {
    // The claim is about the absence of the editor, not about a message. An
    // unreachable folder with a working text field is a bug that only loses data
    // the next time somebody types.
    //
    // Asserted on the panes rather than on `EditableText`, which `SelectableText`
    // builds for the path above - it is read-only, and asserting it absent would
    // be asserting that the folder cannot be copied out.
    await pumpUnreachable(tester);

    expect(find.byType(NoteListPane), findsNothing);
    expect(find.byType(NoteEditorPane), findsNothing);
  });

  testWidgets('the way out is the control that chose the folder',
      (WidgetTester tester) async {
    await pumpUnreachable(tester);

    expect(
      find.widgetWithText(FilledButton, 'Change the notes folder'),
      findsOneWidget,
      reason: 'telling somebody their notes are elsewhere without offering to move '
          'them is a dead end',
    );
  });

  test('a reachable chosen folder raises nothing', () {
    // The normal case must be untouched, or every ordinary launch shows this.
    expect(harness.container.read(appPathsProvider).unreachableDirectory, isNull);
  });

  test('the missing folder is not created by asking about it', () {
    // §3.0a: a reachability check that creates what it tests answers "yes" to
    // every path ever pointed at, and `main()` would then write an empty library
    // into a drive that is not plugged in.
    File('${harness.path}\\settings.json').writeAsStringSync(jsonEncode(<String, Object>{
          'format': 'winnotes',
          'version': 1,
          'storageDirectory': missing,
        }));
    expect(Directory(missing).existsSync(), isFalse, reason: 'precondition');

    expect(
      StorageLocation.unreachableChoice(AppPaths(
        dataDirectory: harness.path,
        executablePath: harness.path,
        reportedDirectory: harness.path,
      )),
      missing,
    );

    expect(Directory(missing).existsSync(), isFalse, reason: 'still not created');
  });

  test('the editor is not opened on the default folder when the choice is unreachable',
      () async {
    // The write side of the same fact, read back from the resolver `main()` uses.
    // The screen is the visible half; this is the half that decides where a
    // keystroke lands.
    File('${harness.path}\\settings.json').writeAsStringSync(jsonEncode(<String, Object>{
          'format': 'winnotes',
          'version': 1,
          'storageDirectory': missing,
        }));
    final AppPaths reported = AppPaths(
      dataDirectory: harness.path,
      executablePath: harness.path,
      reportedDirectory: harness.path,
    );

    expect(StorageLocation.resolveDataDirectory(reported), harness.path);
    expect(StorageLocation.unreachableChoice(reported), missing);
  });

  group('the widget surface, which is the writer when no editor is running', () {
    late TestHarness widget;

    setUp(() {
      widget = TestHarness.unreachableWidget(
        chosen: missing,
        at: harness.path,
      );
    });

    tearDown(() async {
      await widget.dispose();
    });

    test('it reads nothing and shows nothing', () async {
      await widget.widgetState();
      final WidgetNotes surface = WidgetNotes(widget);

      expect(surface.notes, isEmpty);
      expect(
        surface.widgetVisible,
        isFalse,
        reason: 'showing the default folder\'s notes would be the same bug wearing '
            'a smaller hat',
      );
    });

    test('it writes no notes, so nothing lands in the default folder', () async {
      await widget.widgetState();

      expect(
        await widget.addNote(title: 'Typed at the wrong moment', body: ''),
        isFalse,
      );
      await widget.notesFacade().flush();

      expect(
        File(widget.notesFile).existsSync(),
        isFalse,
        reason: 'this surface writes notes.json when no editor is running, so it is '
            'the half that would actually lose them. Not even an empty library is '
            'created in a folder nobody chose.',
      );
    });

    test('a geometry change is not written either', () async {
      // `widget_state.json` is not notes, but it is the same wrong folder and the
      // same cause, so it is checked rather than excused.
      await widget.widgetState();
      await widget.onGeometryChanged(
        const NativeBounds(left: 10, top: 20, width: 300, height: 400),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        File('${widget.path}\\widget_state.json').existsSync(),
        isFalse,
      );
    });
  });
}