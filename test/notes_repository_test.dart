import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/utils/atomic_json_file.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/notes/data/notes_repository.dart';

import 'helpers/file_io.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('winnotes_repo_test');
  });

  tearDown(() {
    // Retried rather than deleted outright: several of these tests leave a
    // watch, a lock or an in-flight debounced write behind, and whether the last
    // handle is closed by the time the body returns is a race. See the helper.
    deleteTempDir(temp);
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

  /// Waits for a queued write to reach disk, up to a few seconds.
  ///
  /// Polling rather than asserting on the first millisecond is deliberate.
  /// Replacing a file on Windows is itself allowed to fail transiently - Search
  /// Indexer or antivirus holding the destination open - and AtomicJsonFile
  /// retries that, so asserting immediately would be testing the filesystem
  /// instead of the thing under test. Never calls flushPending, because the
  /// tests that use this exist to prove the debounce ceiling alone is enough.
  Future<bool> landed() async {
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(deadline)) {
      if (File(notesPath()).existsSync()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return File(notesPath()).existsSync();
  }

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

    test('loadFrom keeps the notes it can read when one entry is broken', () async {
      // §3.13, and the asymmetry with load() above is the whole point. load()
      // refuses anything it did not write, because that is your only copy and
      // guessing at it is unacceptable. loadFrom() is reading a *candidate*
      // backup chosen by a person who is already in trouble - and refusing the
      // whole file because one entry is malformed would throw away notes that
      // are perfectly fine. That is the opposite of what someone recovering from
      // corruption needs.
      writeFile(
        '{"format":"winnotes","version":1,"notes":['
        '{"id":"good1","title":"Fine","body":"","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"},'
        '{"title":"No id at all"},'
        '{"id":"good2","title":"Also fine","body":"","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"}'
        ']}',
      );

      final result = await repo().loadFrom(File(notesPath()));

      expect(result, isA<NotesLoaded>());
      expect(
        (result as NotesLoaded).notes.map((n) => n.id).toSet(),
        {'good1', 'good2'},
        reason: 'one malformed note must not condemn the rest of a backup',
      );
    });

    test('loadFrom returns empty rather than claiming damage on a non-backup',
        () async {
      // Distinct from load(), which reports corruption. Here the caller is
      // deciding whether to offer a file as a recovery source, and "this is not
      // one of ours" is simply "no", not an error to report.
      writeFile('{"hello":"world"}');
      final result = await repo().loadFrom(File(notesPath()));
      expect((result as NotesLoaded).notes, isEmpty);
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
    test('a write that cannot land neither blocks the file nor loses the value',
        () async {
      // A directory sitting where the file belongs makes every rename fail,
      // which is the closest a test can get to antivirus holding the notes open.
      final path = notesPath();
      Directory(path).createSync();
      final file = AtomicJsonFile(path, debounce: const Duration(milliseconds: 20));

      file.write({'a': 1});
      await file.flushPending();

      expect(file.blocked, isNull,
          reason: 'a failed write is not unreadable data, so it must not '
              'trigger the refuse-to-overwrite block');

      // Clear the obstruction. The value queued before the failure must still be
      // there, otherwise the notes on screen have silently stopped saving.
      Directory(path).deleteSync();
      await file.flushPending();
      expect(jsonDecode(File(path).readAsStringSync()), {'a': 1});
      await file.dispose();
    });

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
      // Registered before the assertions so the retry timer is always cleared,
      // even when one of them throws and skips the dispose below.
      addTearDown(file.dispose);

      const ceiling = Duration(milliseconds: 1500);

      for (var i = 0; i < 40; i++) {
        file.write({'i': i});
        await Future<void>.delayed(const Duration(milliseconds: 60));
        // Past the ceiling, the queued write has to have landed without anyone
        // calling flushPending.
        if ((i + 1) * 60 > ceiling.inMilliseconds) {
          expect(await landed(), isTrue,
              reason: 'nothing was written after ${(i + 1) * 60}ms of typing');
        }
      }
    });

    test('the ceiling fires even while writes keep arriving', () async {
      final file = AtomicJsonFile(notesPath());
      addTearDown(file.dispose);
      for (var i = 0; i < 30; i++) {
        file.write({'i': i});
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      // 30 * 60ms is 1800ms, comfortably past the 1500ms ceiling, so the file
      // must exist even though no write was ever allowed to settle.
      expect(await landed(), isTrue);
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

    test('the backup holds the PREVIOUS content, not the new one', () async {
      // The single most damaging thing this file could do wrong, and the easiest
      // to get wrong by accident: extracting the atomic write into a helper and
      // taking the backup afterwards would leave the backup a duplicate of the
      // current file, and the previous version gone for good. So the ordering is
      // pinned rather than trusted.
      final file = AtomicJsonFile(notesPath());
      addTearDown(file.dispose);

      await file.writeNow({'generation': 1});
      await file.writeNow({'generation': 2});

      expect(
        jsonDecode(File('${notesPath()}.bak').readAsStringSync()),
        {'generation': 1},
        reason: 'the backup is taken before the replace, so it is one write '
            'behind - which is the whole point of it',
      );
      expect(jsonDecode(File(notesPath()).readAsStringSync()),
          {'generation': 2});
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