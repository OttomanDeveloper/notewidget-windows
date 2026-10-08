/// Choosing a different folder: that it works, and that it cannot lose notes.
///
/// The setting existed long before it did anything. `Settings` had a picker, it saved
/// a path, the dialog displayed it — and every file went to `%APPDATA%\WinNotes`
/// regardless, verified on a release build. So these tests are not only about the new
/// behaviour; several of them exist because the old behaviour passed everything.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/utils/app_paths.dart';
import 'package:win_notes/features/settings/domain/settings.dart';
import 'package:win_notes/features/settings/data/storage_location.dart';
import 'package:win_notes/features/settings/data/storage_transfer.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('wn_storage_location');
  });

  tearDown(() {
    if (!root.existsSync()) return;
    // The same bounded retry `TestHarness.dispose` uses. A file still held open by a
    // reader would otherwise fail the cleanup and look like a product bug.
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
    while (root.existsSync()) {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) return;
        sleep(const Duration(milliseconds: 50));
      }
    }
  });

  String dir(String name) => '${root.path}\\$name';
  File file(String directory, String name) => File('$directory\\$name');

  AppPaths paths(String dataDirectory, {String? reported}) => AppPaths(
        dataDirectory: dataDirectory,
        executablePath: r'C:\app\win_notes.exe',
        reportedDirectory: reported ?? dataDirectory,
      );

  void writeJson(String directory, String name, Map<String, dynamic> value) {
    Directory(directory).createSync(recursive: true);
    file(directory, name).writeAsStringSync(jsonEncode(value));
  }

  String notesDocument({int count = 1}) => jsonEncode(<String, Object>{
        'format': 'winnotes',
        'version': 1,
        'notes': List<Map<String, String>>.generate(
          count,
          (int i) => <String, String>{
            'id': 'note-$i',
            'title': 'Note $i',
            'body': 'Body $i',
            'createdAt': '2026-10-05T00:00:00.000Z',
            'updatedAt': '2026-10-05T00:00:00.000Z',
          },
        ),
      });

  group('AppPaths: which directory is the real one', () {
    test('with nothing chosen, files go where the runner said', () {
      final AppPaths p = AppPaths.resolve(
        reported: r'C:\Users\someone\AppData\Roaming\WinNotes',
        executablePath: r'C:\app\win_notes.exe',
      );
      expect(p.dataDirectory, r'C:\Users\someone\AppData\Roaming\WinNotes');
    });

    test('with a folder chosen, files go there', () {
      final AppPaths p = AppPaths.resolve(
        reported: r'C:\Users\someone\AppData\Roaming\WinNotes',
        executablePath: r'C:\app\win_notes.exe',
        configured: r'D:\Notes',
      );
      expect(p.dataDirectory, r'D:\Notes');
      expect(
        p.reportedDirectory,
        r'C:\Users\someone\AppData\Roaming\WinNotes',
        reason: 'the reported directory is still needed - it is where the pointer to '
            'the chosen folder is read from',
      );
    });

    test('a chosen folder that is not a usable path is ignored, not obeyed', () {
      for (final String bad in <String>[r'relative\path', r'D:\..\elsewhere', 'C:', '', '   ', r'//server/share']) {
        final AppPaths p = AppPaths.resolve(
          reported: r'C:\Users\someone\AppData\Roaming\WinNotes',
          executablePath: r'C:\app\win_notes.exe',
          configured: bad.isEmpty ? null : bad,
        );
        expect(
          p.dataDirectory,
          r'C:\Users\someone\AppData\Roaming\WinNotes',
          reason: '"$bad" must not be where notes are written',
        );
      }
    });

    test('a run override outranks a chosen folder', () {
      // It is the person running the program saying where to work for this run, which
      // beats a preference saved months ago - and it is what makes a verification run
      // independent of whatever the real profile says.
      final AppPaths p = AppPaths.resolve(
        reported: r'C:\real\WinNotes',
        executablePath: r'C:\app\win_notes.exe',
        configured: r'D:\ChosenByPreference',
        environment: <String, String>{AppPaths.overrideVariable: r'C:\temp\verify'},
      );
      expect(p.dataDirectory, r'C:\temp\verify');
    });

    test('the pointer file is always in the reported directory', () {
      final AppPaths p = AppPaths.resolve(
        reported: r'C:\real\WinNotes',
        executablePath: r'C:\app\win_notes.exe',
        configured: r'D:\Notes',
      );
      expect(p.settingsPointerFile, r'C:\real\WinNotes\settings.json');
      expect(
        p.settingsFile,
        r'D:\Notes\settings.json',
        reason: 'and the live copy lives with the library',
      );
    });
  });

  group('the pointer: how a chosen folder is found at startup', () {
    test('no pointer means no chosen folder', () {
      final String reported = dir('default');
      Directory(reported).createSync(recursive: true);
      expect(StorageLocation.readPointer(paths(reported)), isNull);
      expect(StorageLocation.resolveDataDirectory(paths(reported)), reported);
    });

    test('a pointer names the folder, and files go there', () {
      final String reported = dir('default');
      final String chosen = dir('chosen');
      Directory(chosen).createSync(recursive: true);
      writeJson(reported, 'settings.json', <String, dynamic>{
        'format': 'winnotes',
        'version': 1,
        'storageDirectory': chosen,
      });

      final AppPaths p = paths(reported);
      expect(StorageLocation.readPointer(p), chosen);
      expect(
        StorageLocation.resolveDataDirectory(p),
        chosen,
        reason: 'this is the assertion that was impossible before: the setting was '
            'saved and displayed and every file still went to the default folder',
      );
    });

    test('a chosen folder that has gone is not silently replaced by an empty one', () {
      // An unplugged drive. The pointer still names it, and the folder is not there.
      // Falling back to the default folder is the only safe answer - it is where the
      // notes still are. Silently using the named-but-absent folder would create an
      // empty library that looks exactly like total loss.
      final String reported = dir('default');
      writeJson(reported, 'settings.json', <String, dynamic>{
        'format': 'winnotes',
        'version': 1,
        'storageDirectory': dir('unplugged'),
      });

      expect(
        StorageLocation.resolveDataDirectory(paths(reported)),
        reported,
        reason: 'an unreachable chosen folder must not become an empty library',
      );
    });

    test('a corrupt settings file is treated as no choice at all', () {
      final String reported = dir('default');
      Directory(reported).createSync(recursive: true);
      file(reported, 'settings.json').writeAsStringSync('{ this is not json');

      expect(StorageLocation.readPointer(paths(reported)), isNull);
      expect(
        StorageLocation.resolveDataDirectory(paths(reported)),
        reported,
        reason: 'losing preferences is a nuisance; refusing to start would leave '
            'somebody unable to reach their notes to fix it',
      );
    });

    test('the chosen folder\'s own settings.json wins when the two disagree', () {
      // Two copies exist by design. A chosen folder is self-contained, so if it is
      // moved or handed over it keeps working - which means its copy is the live one.
      final String reported = dir('default');
      final String chosen = dir('chosen');
      final String moved = dir('moved');
      Directory(moved).createSync(recursive: true);

      writeJson(reported, 'settings.json', <String, dynamic>{
        'format': 'winnotes',
        'version': 1,
        'storageDirectory': chosen,
      });
      // The chosen folder was itself moved, and says so.
      writeJson(chosen, 'settings.json', <String, dynamic>{
        'format': 'winnotes',
        'version': 1,
        'storageDirectory': moved,
      });

      expect(
        StorageLocation.resolveDataDirectory(paths(reported)),
        moved,
        reason: 'a folder that carries its own pointer keeps working after being moved',
      );
    });

    test('a settings.json with no storageDirectory key is not a pointer', () {
      final String reported = dir('default');
      writeJson(reported, 'settings.json', <String, dynamic>{'format': 'winnotes', 'version': 1});
      expect(StorageLocation.readPointer(paths(reported)), isNull);
    });

    test('a settings.json holding the wrong shape is not a pointer', () {
      final String reported = dir('default');
      for (final Object value in <Object>[42, true, <String>[], <String, String>{'a': 'b'}]) {
        writeJson(reported, 'settings.json', <String, dynamic>{
          'format': 'winnotes',
          'version': 1,
          StorageLocation.storageDirectoryKey: value,
        });
        expect(
          StorageLocation.readPointer(paths(reported)),
          isNull,
          reason: 'a ${value.runtimeType} is not a folder',
        );
      }
    });
  });

  group('copying a library to a chosen folder', () {
    test('every file arrives, and the original is left alone', () async {
      final String from = dir('from');
      final String to = dir('to');
      Directory(from).createSync(recursive: true);
      file(from, 'notes.json').writeAsStringSync(notesDocument(count: 3));
      writeJson(from, 'widget_state.json', <String, dynamic>{'left': 10, 'width': 360});
      writeJson(from, 'selection.json', <String, dynamic>{'noteId': 'note-1'});
      writeJson(from, 'settings.json', <String, dynamic>{'format': 'winnotes', 'version': 1});

      final StorageTransferOutcome outcome = await StorageTransfer.copyLibrary(
        from: paths(from),
        to: paths(to),
        settings: WinNotesSettings(storageDirectory: to),
      );

      expect(outcome, StorageTransferOutcome.done);
      expect(file(to, 'notes.json').existsSync(), isTrue);
      expect(
        jsonDecode(file(to, 'notes.json').readAsStringSync())['notes'],
        hasLength(3),
      );
      expect(file(to, 'widget_state.json').existsSync(), isTrue);
      expect(file(to, 'selection.json').existsSync(), isTrue);

      expect(
        file(from, 'notes.json').existsSync(),
        isTrue,
        reason: 'copy, never move - the person deletes the old copy themselves, having '
            'seen for themselves that the notes arrived',
      );
      expect(
        jsonDecode(file(from, 'notes.json').readAsStringSync())['notes'],
        hasLength(3),
      );
    });

    test('the destination settings.json names the destination', () async {
      final String from = dir('from');
      final String to = dir('to');
      Directory(from).createSync(recursive: true);
      file(from, 'notes.json').writeAsStringSync(notesDocument());

      await StorageTransfer.copyLibrary(
        from: paths(from),
        to: paths(to),
        settings: WinNotesSettings(storageDirectory: to),
      );

      final WinNotesSettings written = WinNotesSettings.fromJson(
        jsonDecode(file(to, 'settings.json').readAsStringSync()),
      );
      expect(
        written.storageDirectory,
        to,
        reason: 'the chosen folder is self-contained: copied on its own it still works',
      );
    });

    test('a destination that already has notes is refused, and nothing is touched',
        () async {
      final String from = dir('from');
      final String to = dir('to');
      Directory(from).createSync(recursive: true);
      Directory(to).createSync(recursive: true);
      file(from, 'notes.json').writeAsStringSync(notesDocument(count: 5));
      const String theirs = '{"format":"winnotes","version":1,"notes":[{"id":"theirs"}]}';
      file(to, 'notes.json').writeAsStringSync(theirs);

      final StorageTransferOutcome outcome = await StorageTransfer.copyLibrary(
        from: paths(from),
        to: paths(to),
        settings: WinNotesSettings(storageDirectory: to),
      );

      expect(outcome, StorageTransferOutcome.destinationNotEmpty);
      expect(
        file(to, 'notes.json').readAsStringSync(),
        theirs,
        reason: 'notes that were never read are the one thing that must not be '
            'replaced. This is what stops "point at the wrong folder" destroying a '
            'library.',
      );
      expect(file(from, 'notes.json').existsSync(), isTrue);
    });

    test('a destination holding an empty notes.json is not a library', () async {
      // Somebody opened the app in that folder once and closed it again. Refusing
      // would make the folder permanently unusable for no reason at all.
      final String from = dir('from');
      final String to = dir('to');
      Directory(from).createSync(recursive: true);
      Directory(to).createSync(recursive: true);
      file(from, 'notes.json').writeAsStringSync(notesDocument());
      file(to, 'notes.json').writeAsStringSync('{"format":"winnotes","notes":[]}');

      final StorageTransferOutcome outcome = await StorageTransfer.copyLibrary(
        from: paths(from),
        to: paths(to),
        settings: WinNotesSettings(storageDirectory: to),
      );
      expect(outcome, StorageTransferOutcome.done);
    });

    test('the same folder is reported rather than copied onto itself', () async {
      final String here = dir('here');
      Directory(here).createSync(recursive: true);
      file(here, 'notes.json').writeAsStringSync(notesDocument());

      final StorageTransferOutcome outcome = await StorageTransfer.copyLibrary(
        from: paths(here),
        // A trailing slash and different case: the same folder, spelled two ways.
        to: paths('$here\\'),
        settings: WinNotesSettings(),
      );
      expect(outcome, StorageTransferOutcome.alreadyThere);
    });

    test('a path that is not usable is refused', () async {
      final String from = dir('from');
      Directory(from).createSync(recursive: true);
      final StorageTransferOutcome outcome = await StorageTransfer.copyLibrary(
        from: paths(from),
        to: paths(r'relative\folder'),
        settings: WinNotesSettings(),
      );
      expect(outcome, StorageTransferOutcome.notUsable);
    });

    test('no half-written file is left behind', () async {
      final String from = dir('from');
      final String to = dir('to');
      Directory(from).createSync(recursive: true);
      file(from, 'notes.json').writeAsStringSync(notesDocument());

      await StorageTransfer.copyLibrary(
        from: paths(from),
        to: paths(to),
        settings: WinNotesSettings(storageDirectory: to),
      );

      final List<File> leftovers = Directory(to)
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.copying'))
          .toList();
      expect(leftovers, isEmpty, reason: 'copies go via a temporary name and rename');
    });
  });

  group('reaching a folder', () {
    test('a folder that exists and accepts writes is reachable', () {
      Directory(dir('here')).createSync(recursive: true);
      expect(StorageLocation.isReachable(dir('here')), isTrue);
    });

    test('a folder that is not there is not', () {
      expect(StorageLocation.isReachable(dir('never-existed')), isFalse);
    });

    test('a malformed path is not', () {
      expect(StorageLocation.isReachable(r'relative'), isFalse);
    });

    test('asking does not create the folder', () {
      // The regression this whole guard exists for. main() creates the data
      // directory, so a reachability check that also created it would answer 'yes'
      // to a drive that is not plugged in - and the app would then recreate the
      // folder locally and write an empty library into it.
      final String gone = dir('not-plugged-in');
      expect(Directory(gone).existsSync(), isFalse, reason: 'precondition');

      expect(StorageLocation.isReachable(gone), isFalse);

      expect(
        Directory(gone).existsSync(),
        isFalse,
        reason: 'checking must not make the answer true',
      );
    });
  });
}