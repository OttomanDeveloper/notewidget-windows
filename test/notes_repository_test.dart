import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/src/core/atomic_json_file.dart';
import 'package:win_notes/src/data/note.dart';
import 'package:win_notes/src/data/notes_repository.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('winnotes_repo_test');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  String notesPath() => '${temp.path}\\notes.json';

  NotesRepository repo() => NotesRepository(AtomicJsonFile(notesPath()));

  void writeFile(String contents) {
    File(notesPath()).writeAsStringSync(contents);
  }

  Note note(String id, {String title = 't', String body = 'b', int minute = 0}) =>
      Note(
        id: id,
        title: title,
        body: body,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1, 12, minute),
      );

  group('loading', () {
    test('a missing file is a first run, not an error', () async {
      final result = await repo().load();
      expect(result, isA<NotesLoaded>());
      expect((result as NotesLoaded).notes, isEmpty);
    });

    test('a file with only whitespace is treated as empty', () async {
      writeFile('   \n  ');
      final result = await repo().load();
      expect((result as NotesLoaded).notes, isEmpty);
    });

    test('round trips notes through the file', () async {
      final repository = repo();
      repository.save([note('a', title: 'Groceries'), note('b', title: 'Ideas')]);
      await repository.saveNow([note('a', title: 'Groceries'), note('b', title: 'Ideas')]);

      final result = await repo().load();
      expect((result as NotesLoaded).notes.map((n) => n.title), ['Groceries', 'Ideas']);
    });

    test('the written file is valid JSON with the format tag', () async {
      final repository = repo();
      await repository.saveNow([note('a')]);
      final decoded = jsonDecode(File(notesPath()).readAsStringSync());
      expect(decoded['format'], 'winnotes');
      expect(decoded['version'], 1);
      expect(decoded['notes'], hasLength(1));
    });
  });

  group('refusing to overwrite notes that were never read', () {
    // This is the behaviour the whole project is built around: overwriting
    // unreadable notes is the one failure it will not risk.

    test('invalid JSON is reported as corrupt, not as an empty library',
        () async {
      writeFile('{ this is not json');
      final result = await repo().load();
      expect(result, isA<NotesCorrupt>());
    });

    test('valid JSON that is not a WinNotes document is also refused', () async {
      writeFile('{"hello": "world"}');
      final result = await repo().load();
      expect(result, isA<NotesCorrupt>());
      // Left exactly as it was: a file the app did not write is not one the
      // app is willing to guess about.
      expect(File(notesPath()).readAsStringSync(), '{"hello": "world"}');
    });

    test('a notes entry that is not a list is refused', () async {
      writeFile('{"format":"winnotes","version":1,"notes":{"a":1}}');
      expect(await repo().load(), isA<NotesCorrupt>());
    });

    test('a note entry that is not an object is refused', () async {
      writeFile('{"format":"winnotes","version":1,"notes":["hello"]}');
      expect(await repo().load(), isA<NotesCorrupt>());
    });

    test('a note missing its id is refused rather than skipped', () async {
      // Skipping would silently drop a note that was written by hand.
      writeFile('{"format":"winnotes","version":1,"notes":[{"title":"x"}]}');
      expect(await repo().load(), isA<NotesCorrupt>());
    });

    test('while blocked, every write is a no-op and the file is untouched',
        () async {
      writeFile('{ broken');
      final repository = repo();
      await repository.load();

      repository.save([note('new')]);
      await repository.saveNow([note('new')]);
      await repository.flush();

      expect(File(notesPath()).readAsStringSync(), '{ broken');
    });

    test('a restore can lift the block and write for real', () async {
      writeFile('{ broken');
      final repository = repo();
      await repository.load();

      repository.unblock();
      await repository.saveNow([note('restored')]);

      final reloaded = await repo().load();
      expect((reloaded as NotesLoaded).notes.single.id, 'restored');
    });
  });

  group('ordering', () {
    test('most recently edited comes first', () {
      final sorted = NotesRepository.sorted([
        note('old', minute: 1),
        note('newest', minute: 9),
        note('mid', minute: 5),
      ]);
      expect(sorted.map((n) => n.id), ['newest', 'mid', 'old']);
    });

    test('equal timestamps still produce a stable order', () {
      final sorted = NotesRepository.sorted([
        note('a', minute: 3),
        note('b', minute: 3),
        note('c', minute: 3),
      ]);
      expect(sorted.map((n) => n.id), ['c', 'b', 'a']);
      // Deterministic, so two writes of the same set never shuffle the list.
      final again = NotesRepository.sorted(sorted.reversed);
      expect(again.map((n) => n.id), ['c', 'b', 'a']);
    });
  });

  group('AtomicJsonFile', () {
    test('a burst of writes coalesces into one file change', () async {
      final file = AtomicJsonFile(notesPath(), debounce: const Duration(milliseconds: 80));
      for (var i = 0; i < 50; i++) {
        file.write({'n': i});
      }
      await file.flushPending();

      final decoded = jsonDecode(File(notesPath()).readAsStringSync());
      expect(decoded['n'], 49, reason: 'the last write is the one that lands');
      await file.dispose();
    });

    test('a continuous burst still reaches disk before the process dies',
        () async {
      // The ceiling is what stops someone typing a long sentence from never
      // writing anything at all. Each write arrives well inside the 250ms
      // debounce, so the trailing edge never fires and only the ceiling can.
      final file = AtomicJsonFile(notesPath());
      final ceiling = const Duration(milliseconds: 1500);

      for (var i = 0; i < 40; i++) {
        file.write({'i': i});
        await Future<void>.delayed(const Duration(milliseconds: 60));
        // Past the ceiling, the queued write has to have landed without anyone
        // calling flushPending.
        if ((i + 1) * 60 > ceiling.inMilliseconds) {
          expect(File(notesPath()).existsSync(), isTrue,
              reason: 'nothing was written after ${(i + 1) * 60}ms of typing');
        }
      }
      await file.dispose();
    });

    test('the ceiling fires even while writes keep arriving', () async {
      final file = AtomicJsonFile(notesPath());
      for (var i = 0; i < 30; i++) {
        file.write({'i': i});
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      // 30 * 60ms is 1800ms, comfortably past the 1500ms ceiling, so the file
      // must exist even though no write was ever allowed to settle.
      expect(File(notesPath()).existsSync(), isTrue);
      await file.dispose();
    });

    test('writes replace the file rather than appending to it', () async {
      final file = AtomicJsonFile(notesPath());
      await file.writeNow({'a': 1});
      await file.writeNow({'b': 2});
      expect(jsonDecode(File(notesPath()).readAsStringSync()), {'b': 2});
      await file.dispose();
    });

    test('no temp file is left behind after a successful write', () async {
      final file = AtomicJsonFile(notesPath());
      await file.writeNow({'a': 1});
      expect(File('$notesPath.tmp').existsSync(), isFalse);
      await file.dispose();
    });

    test('a concurrent reader never observes a partially written file', () async {
      // Two different things can go wrong when reading while a replace happens,
      // and only one of them is a bug:
      //
      //  * ERROR_SHARING_VIOLATION: the replace has the destination open for a
      //    moment. Windows does this to any reader and every app on the machine
      //    has to live with it. Not a defect.
      //  * Partially written content: the write is not atomic. That would mean a
      //    kill could leave a broken file, which is exactly what the temp-file
      //    dance exists to prevent.
      final file = AtomicJsonFile(notesPath());
      await file.writeNow({'pad': 'x' * 4000, 'i': -1});

      var reads = 0;
      var busy = 0;
      String? partial;
      final reader = Timer.periodic(const Duration(milliseconds: 1), (_) {
        try {
          final decoded = jsonDecode(File(notesPath()).readAsStringSync());
          reads++;
          if (decoded is! Map || decoded['pad'] == null) {
            partial ??= 'read succeeded but the document was not intact';
          }
        } on PathAccessException {
          busy++;
        } catch (error) {
          partial ??= '$error';
        }
      });

      for (var i = 0; i < 25; i++) {
        await file.writeNow({'pad': 'y' * 4000, 'i': i});
      }
      reader.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(partial, isNull, reason: 'a reader observed a half-written document');
      expect(reads, greaterThan(0));
      expect(busy, greaterThanOrEqualTo(0));
      await file.dispose();
    });

    test('the file is readable again immediately after the last write',
        () async {
      // The other surface reads this file on every change event, so it has to
      // settle rather than staying transiently locked.
      final file = AtomicJsonFile(notesPath());
      for (var i = 0; i < 10; i++) {
        await file.writeNow({'i': i});
      }
      expect(jsonDecode(File(notesPath()).readAsStringSync()), {'i': 9});
      await file.dispose();
    });
  });
}