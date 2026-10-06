import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/utils/atomic_json_file.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/notes/domain/repositories.dart';
import 'package:win_notes/features/notes/data/notes_repository.dart';
import 'package:win_notes/features/notes/presentation/providers/notes_controller.dart';

import 'helpers/provider_harness.dart';

void main() {
  late TestHarness harness;

  // Containers are drained and disposed before their temp directory is deleted,
  // because a queued write outlives the test that made it and `AtomicJsonFile`
  // creates its parent directory before every write. Deleting the directory first
  // raced the pending write, which recreated the directory and left it behind -
  // hundreds of them, in the developer's %TEMP%, with every test still green.
  // See `provider_harness.dart`.
  setUp(() => harness = TestHarness.build());

  tearDown(() async {
    // `dispose` drains the writers itself, in the order that matters - see
    // `TestHarness.dispose`. Flushing here as well was two writes racing the same
    // teardown.
    await harness.dispose();
  });

  /// The notes surface, with the first load already awaited.
  ///
  /// Awaiting here rather than at each call site: the old tests called `c.load()`
  /// themselves, and one that forgot it asserted against an empty list and passed.
  Future<Notes> controller() async {
    await harness.notes();
    return Notes(harness);
  }

  group('creating and editing', () {
    test('the first launch has a note ready to type into', () async {
      final Notes c = await controller();
      await c.load();
      expect(c.notes, isEmpty);

      c.ensureAtLeastOneNote();
      expect(c.notes, hasLength(1));
      expect(c.selectedNote, isNotNull);
      expect(c.selectedNote!.body, '');
    });

    test('ensureAtLeastOneNote does not add a second note', () async {
      final Notes c = await controller();
      await c.load();
      c.ensureAtLeastOneNote();
      c.ensureAtLeastOneNote();
      expect(c.notes, hasLength(1));
    });

    test('editing moves a note to the top of the list', () async {
      final Notes c = await controller();
      await c.load();
      final Note first = c.createNote()!;
      c.updateNote(first.id, body: 'first');
      final Note second = c.createNote()!;
      expect(c.notes.first.id, second.id);

      // Editing the older note brings it back to the front.
      c.updateNote(first.id, body: 'touched');
      expect(c.notes.first.id, first.id);
    });

    test('editing wins even when two notes share a timestamp', () async {
      // No delay anywhere on purpose. The clock has millisecond resolution, so
      // these three notes are very likely to land in the same one, and the
      // ordering tie-break is by id - which is random. Before the controller
      // guaranteed a strictly increasing stamp, this was a coin flip.
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      final Note b = c.createNote()!;
      final Note d = c.createNote()!;

      int edit = 0;

      for (final Note target in <Note>[a, b, d, a, b, d]) {
        // Each edit must actually change something: updateNote deliberately
        // ignores an edit that alters nothing, so a repeated body would leave
        // the note exactly where it was and prove nothing.
        edit++;
        c.updateNote(target.id, body: 'edit $edit');
        expect(c.notes.first.id, target.id,
            reason: 'the note just edited must sort first, ties or not');
      }
    });

    test('an edit that changes nothing does not reorder anything', () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.updateNote(a.id, title: 'A');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note b = c.createNote()!;
      c.updateNote(b.id, title: 'B');

      final List<String> orderBefore = c.notes.map((Note n) => n.id).toList();
      c.updateNote(a.id, title: 'A', body: '');
      expect(c.notes.map((Note n) => n.id).toList(), orderBefore);
    });
    test('a note whose body is emptied still exists', () async {
      final Notes c = await controller();
      await c.load();
      final Note n = c.createNote()!;
      c.updateNote(n.id, body: 'something');
      expect(c.notes, hasLength(1));

      c.updateNote(n.id, body: '');
      expect(c.notes, hasLength(1),
          reason: 'deleting the last character is not deleting the note');
      expect(c.selectedNote!.isEmpty, isTrue);
    });

      test('produces a new state on every change that matters', () async {
        final Notes c = await controller();
        await c.load();
        final int before = c.changes;

        c.createNote();
        final Note n = c.selectedNote!;
        c.updateNote(n.id, body: 'x');
        c.setQuery('x');
        // Create, edit and search each produce one new state. Nothing here should
        // produce more than one per action, so the count is exact rather than a
        // floor.
        expect(c.changes - before, 3);
      });

      test('setting the same query twice does not produce a new state', () async {
        final Notes c = await controller();
        await c.load();
        c.setQuery('milk');
        final int before = c.changes;
        c.setQuery('milk');
        expect(c.changes - before, 0);
      });
  });

  group('marking a task finished', () {
    test('a note toggles both ways', () async {
      final Notes c = await controller();
      await c.load();
      final Note note = c.createNote()!;

      expect(note.isCompleted, isFalse);

      // Re-read after each toggle: notes are immutable, so the held object
      // never changes - only the state does.
      c.toggleCompleted(note.id);
      expect(c.selectedNote!.isCompleted, isTrue);
      expect(c.selectedNote!.completedAt, isNotNull);

      c.toggleCompleted(note.id);
      expect(c.selectedNote!.isCompleted, isFalse);
      expect(c.selectedNote!.completedAt, isNull);
    });

    test('finishing a note does not reorder the list', () async {
      // The reason toggleCompleted exists in the shape it does. Notes sort by
      // most recently edited, so bumping the timestamp would send the note to
      // the top every time it is ticked off, and working through a list would
      // become a shuffle with the finished task landing back in front of you.
      final Notes c = await controller();
      await c.load();
      final Note first = c.createNote()!;
      c.updateNote(first.id, title: 'older');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note second = c.createNote()!;
      c.updateNote(second.id, title: 'newer');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note third = c.createNote()!;
      c.updateNote(third.id, title: 'newest');

      expect(c.notes.map((Note n) => n.title), <String>['newest', 'newer', 'older']);
      final Map<String, DateTime> stampsBefore = <String, DateTime>{for (final Note n in c.notes) n.id: n.updatedAt};

      c.toggleCompleted(second.id);

      expect(c.notes.map((Note n) => n.title), <String>['newest', 'newer', 'older'],
          reason: 'the list must not move under the pointer');
      for (final Note note in c.notes) {
        expect(note.updatedAt, stampsBefore[note.id],
            reason: 'finishing a task is a state change, not an edit');
      }
    });

    test('undo brings a finished note back finished', () async {
      final Notes c = await controller();
      await c.load();
      final Note note = c.createNote()!;
      c.toggleCompleted(note.id);
      await c.flush();

      c.deleteNote(note.id);
      expect(c.undoDelete(), isTrue);

      expect(c.selectedNote!.isCompleted, isTrue,
          reason: 'a restored note that lost its finished state would be a bug '
              'nobody could explain');
    });

    test('the finished state is written to disk', () async {
      final Notes c = await controller();
      await c.load();
      final Note note = c.createNote()!;
      c.toggleCompleted(note.id);
      await c.flush();

      final NotesRepository reread = NotesRepository(
        AtomicJsonFile(harness.notesFile),
      );
      final NotesLoadResult result = await reread.load();
      final Note restored = (result as NotesLoaded).notes.single;
      expect(restored.isCompleted, isTrue);
      await reread.dispose();
    });

    test('the big card skips finished notes so it is never a struck-through task',
        () async {
      final Notes c = await controller();
      await c.load();
      final Note older = c.createNote()!;
      c.updateNote(older.id, title: 'older');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note newer = c.createNote()!;
      c.updateNote(newer.id, title: 'newer');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note newest = c.createNote()!;
      c.updateNote(newest.id, title: 'newest');

      // With nothing picked. createNote selects what it makes, and that is a
      // deliberate choice the preference must not override - see the test below.
      c.select(null);

      expect(c.focusedNote!.title, 'newest');

      c.toggleCompleted(newest.id);

      expect(c.focusedNote!.title, 'newer',
          reason: 'ticking the top task off should reveal the next one');
    });

    test('with everything finished the big card falls back to the most recent',
        () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.updateNote(a.id, title: 'a');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note b = c.createNote()!;
      c.updateNote(b.id, title: 'b');

      c.toggleCompleted(a.id);
      c.toggleCompleted(b.id);

      expect(c.focusedNote, isNotNull,
          reason: 'the card must not go missing while notes exist');
    });

    test('an explicit selection still wins over the unfinished preference',
        () async {
      // The preference is a default, not a rule. If someone has picked a note,
      // moving the selection out from under them would be worse than showing a
      // finished note large.
      final Notes c = await controller();
      await c.load();
      final Note older = c.createNote()!;
      c.updateNote(older.id, title: 'older');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note newer = c.createNote()!;
      c.updateNote(newer.id, title: 'newer');
      c.toggleCompleted(newer.id);

      c.select(older.id);
      expect(c.focusedNote!.title, 'older');
    });

    test('nothing is marked finished while the file cannot be read', () async {
      // Every other mutation is refused in this state, and this one has to be too:
      // a note flipped to finished in memory that never reaches disk is a note
      // that comes back unfinished, which is worse than the toggle doing nothing.
      final Notes c = await controller();
      await c.load();
      final Note note = c.createNote()!;

      File(harness.notesFile).writeAsStringSync('{ not json');
      await c.load();
      expect(c.corrupt, isNotNull);

      c.toggleCompleted(note.id);
      expect(c.notes, isEmpty, reason: 'the file was unreadable, so nothing loaded');
    });

    test('toggling a note that is not there does nothing', () async {
      final Notes c = await controller();
      await c.load();
      c.createNote();
      c.toggleCompleted('no-such-note');
      expect(c.notes.single.isCompleted, isFalse);
    });
  });

  group('recovering from an unreadable notes file', () {
    test('a file that cannot be opened is reported as transient, not damaged',
        () async {
      // The bug this guards, and it was found by holding the file open the way
      // antivirus does and watching a valid 968-byte document get declared
      // corrupt. The write path had a retry ladder for exactly this; the read
      // path had none, so a scanner passing over the file could stop the app
      // from starting until it was restarted - while telling the user their
      // notes were damaged, which they were not.
      final Notes c = await controller();
      File(harness.notesFile)
          .writeAsStringSync('{"format":"winnotes","version":1,"notes":[]}');
      final _ExclusiveLock lock = _ExclusiveLock.acquire(harness.notesFile);
      addTearDown(lock.release);

      await c.load();
      expect(c.corrupt, isNotNull);
      expect(c.corrupt!.transient, isTrue,
          reason: 'a file that will not open is held, not broken, and the screen '
              'has to say so rather than suggest starting over');
      expect(c.corrupt!.reason, isNot(contains('Unexpected end of input')),
          reason: 'it must not be reported as a parse failure');

      // And the important half: it clears by itself once whatever was holding it
      // lets go, without a restart.
      lock.release();
      await c.retryLoad();
      expect(c.corrupt, isNull);
    });

    test('a read that opens fine is not made to wait on the retry ladder',
        () async {
      // The ladder costs two and a half seconds, and it must only ever be paid
      // when something is actually in the way - otherwise every cold start
      // would be that much slower.
      final Notes c = await controller();
      await c.load();
      final DateTime started = DateTime.now();
      c.createNote();
      expect(DateTime.now().difference(started).inSeconds, lessThan(2));
    });

    test('a file that opens but does not parse is not transient', () async {
      // Waiting cannot make the content change, so this must not be dressed up
      // as a lock - that would send someone round looking for antivirus instead
      // of telling them their file needs attention.
      final Notes c = await controller();
      File(harness.notesFile).writeAsStringSync('{ "format": "winnotes"');
      await c.load();
      expect(c.corrupt, isNotNull);
      expect(c.corrupt!.transient, isFalse);
    });

    test('a missing file is a first run, not a problem to report', () async {
      // The antivirus-quarantine case. There is nothing to lose and nothing to
      // explain, so refusing to start would be the wrong answer entirely.
      final Notes c = await controller();
      await c.load();
      expect(c.corrupt, isNull);
      expect(c.notes, isEmpty);
      c.ensureAtLeastOneNote();
      expect(c.notes, hasLength(1));
    });

    test('a zero-length file is a leftover temp, not corruption', () async {
      final Notes c = await controller();
      File(harness.notesFile).writeAsStringSync('');
      await c.load();
      expect(c.corrupt, isNull);
    });

    test('each write leaves the previous version behind', () async {
      // The recovery route that asks nothing of the person holding the problem.
      // Because writes are atomic, WinNotes can never produce a file it cannot
      // read, so corruption is always external - and this is the only copy that
      // survives that.
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.updateNote(a.id, body: 'first version');
      await c.flush();

      final Note note = c.notes.single;
      c.updateNote(note.id, body: 'second version');
      await c.flush();

      final File backup = File(harness.backupFile);
      expect(backup.existsSync(), isTrue);
      expect(backup.readAsStringSync(), contains('first version'),
          reason: 'the backup is one write behind, which costs at most the '
              'debounce window of typing');
      expect(File(harness.notesFile).readAsStringSync(),
          contains('second version'));
    });

    test('the previous version restores the notes', () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.updateNote(a.id, body: 'the note worth keeping');
      await c.flush();
      c.updateNote(a.id, body: 'the note that got damaged');
      await c.flush();

      // Now break the file the way something external would.
      File(harness.notesFile).writeAsStringSync('{{{ truncated');
      await c.load();
      expect(c.corrupt, isNotNull);
      expect(c.hasBackup, isTrue);

      expect(await c.restoreBackup(), RecoveryOutcome.restoredBackup);

      expect(c.corrupt, isNull);
      expect(c.notes.single.body, 'the note worth keeping');
      // The safety net must survive the recovery. Routing the restore through
      // the ordinary write path would copy the corrupt file over the backup on
      // its way past, so the one good copy would be gone the moment it was used.
      expect(File(harness.backupFile).readAsStringSync(),
          contains('the note worth keeping'),
          reason: 'recovering must not consume the thing it recovered from');
    });

    test('restoring reports when there is nothing to restore', () async {
      // One write means no previous version, and the screen must not offer a
      // button that quietly does nothing.
      final Notes c = await controller();
      await c.load();
      c.createNote();
      await c.flush();
      File(harness.notesFile).writeAsStringSync('nonsense');
      await c.load();

      expect(c.hasBackup, isFalse);
      expect(await c.restoreBackup(), RecoveryOutcome.nothingToRecover);
      expect(c.corrupt, isNotNull,
          reason: 'a failed restore must leave the file alone, not half-replace it');
    });

    test('starting fresh keeps the unreadable file', () async {
      // The escape hatch. A refusal with no way out is a trap, and someone in it
      // is already stressed. Nothing is deleted: the damaged file is renamed with
      // the time on the end, because it may still be readable by hand.
      final Notes c = await controller();
      await c.load();
      File(harness.notesFile).writeAsStringSync('{{{ truncated');

      final ({String? keptAt, RecoveryOutcome outcome}) result = await c.startFresh();
      expect(result.outcome, RecoveryOutcome.startedFresh);
      expect(result.keptAt, isNotNull);

      expect(File(result.keptAt!).existsSync(), isTrue);
      expect(File(result.keptAt!).readAsStringSync(), '{{{ truncated',
          reason: 'the damaged file is evidence, not rubbish');
      expect(c.corrupt, isNull);
      expect(c.notes, hasLength(1), reason: 'and something to type into');
    });

    test('a second incident does not overwrite the first one', () async {
      // Timestamped names specifically so this holds.
      final Notes c = await controller();
      await c.load();

      File(harness.notesFile).writeAsStringSync('first damage');
      final ({String? keptAt, RecoveryOutcome outcome}) first = await c.startFresh();

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      File(harness.notesFile).writeAsStringSync('second damage');
      final ({String? keptAt, RecoveryOutcome outcome}) second = await c.startFresh();

      expect(first.keptAt, isNot(second.keptAt));
      expect(File(first.keptAt!).readAsStringSync(), 'first damage');
      expect(File(second.keptAt!).readAsStringSync(), 'second damage');
    });

    test('starting fresh writes a valid file, so it does not refuse again',
        () async {
      final Notes c = await controller();
      await c.load();
      File(harness.notesFile).writeAsStringSync('{{{ truncated');
      await c.startFresh();
      await c.flush();

      // The whole point of the escape hatch: the app is usable afterwards, which
      // is checked by reading the folder with a controller that has never seen
      // the damaged file.
      final Notes reloaded = await controller();
      await reloaded.load();
      expect(reloaded.corrupt, isNull);
      expect(reloaded.notes, isNotEmpty);
    });
  });

  group('search', () {
    test('filters on title and body as the user types', () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.updateNote(a.id, title: 'Groceries', body: 'Milk');
      final Note b = c.createNote()!;
      c.updateNote(b.id, title: 'Ideas', body: 'Widgets');

      expect(c.visibleNotes, hasLength(2));
      c.setQuery('milk');
      expect(c.visibleNotes.map((Note n) => n.id), <String>[a.id]);
      c.setQuery('widget');
      expect(c.visibleNotes.map((Note n) => n.id), <String>[b.id]);
      c.setQuery('zzz');
      expect(c.visibleNotes, isEmpty);
    });

    test('a whitespace-only query shows everything', () async {
      final Notes c = await controller();
      await c.load();
      final Note first0 = c.createNote()!;
      c.updateNote(first0.id, title: 'A');
      final Note second0 = c.createNote()!;
      c.updateNote(second0.id, title: 'B');
      c.setQuery('   ');
      expect(c.visibleNotes, hasLength(2));
    });

    test('clearing the query restores the full list', () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.updateNote(a.id, title: 'Groceries');
      final Note other = c.createNote()!;
      c.updateNote(other.id, title: 'Other');
      c.setQuery('groceries');
      expect(c.visibleNotes, hasLength(1));
      c.setQuery('');
      expect(c.visibleNotes, hasLength(2));
    });
  });

  group('selection', () {
    test('falls back to the most recent note when nothing is picked', () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.updateNote(a.id, title: 'older');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note b = c.createNote()!;
      c.updateNote(b.id, title: 'newer');

      c.select(null);
      expect(c.selectedNote!.id, b.id);
      c.select(a.id);
      expect(c.selectedNote!.id, a.id);
    });

    test('deleting the selected note moves the selection on', () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note b = c.createNote()!;
      expect(c.selectedId, b.id);

      c.deleteNote(b.id);
      expect(c.selectedId, a.id);
      expect(c.selectedNote!.id, a.id);
    });

    test('deleting the last note leaves nothing selected, not a crash', () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.deleteNote(a.id);
      expect(c.notes, isEmpty);
      expect(c.selectedNote, isNull);
      expect(c.focusedNote, isNull);
    });

    test('a selection pointing at a missing note resolves to something real',
        () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.select(a.id);
      // As happens when the other surface deletes a note.
      c.deleteNote(a.id);
      c.select(a.id);
      expect(c.selectedNote, isNull);
    });
  });

  group('delete and undo', () {
    test('undo restores the note', () async {
      final Notes c = await controller();
      await c.load();
      final Note n = c.createNote()!;
      c.updateNote(n.id, title: 'Groceries', body: 'Milk');

      c.deleteNote(n.id);
      expect(c.notes, isEmpty);
      expect(c.pendingUndo, isNotNull);

      expect(c.undoDelete(), isTrue);
      expect(c.notes, hasLength(1));
      expect(c.notes.single.title, 'Groceries');
      expect(c.notes.single.body, 'Milk');
    });

    test('undo puts the note back in its original position, not on top',
        () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.updateNote(a.id, title: 'A', body: 'old');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note b = c.createNote()!;
      c.updateNote(b.id, title: 'B', body: 'old');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final Note d = c.createNote()!;
      c.updateNote(d.id, title: 'D', body: 'old');

      final List<String> order = c.notes.map((Note n) => n.title).toList();
      final String middle = order[1];
      final Note victim = c.notes.firstWhere((Note n) => n.title == middle);
      c.deleteNote(victim.id);
      c.undoDelete();

      expect(c.notes.map((Note n) => n.title).toList(), order);
    });

    test('undo is offered once and then expires', () async {
      final Notes c = await controller();
      await c.load();
      final Note n = c.createNote()!;
      c.deleteNote(n.id);
      expect(c.pendingUndo, isNotNull);

      c.clearPendingUndo();
      expect(c.pendingUndo, isNull);
      expect(c.undoDelete(), isFalse);
    });

    test('deleting again replaces the pending undo rather than queueing',
        () async {
      final Notes c = await controller();
      await c.load();
      final Note a = c.createNote()!;
      c.updateNote(a.id, title: 'A');
      final Note b = c.createNote()!;
      c.updateNote(b.id, title: 'B');

      c.deleteNote(a.id);
      final PendingUndo? first = c.pendingUndo;
      c.deleteNote(b.id);

      expect(c.pendingUndo, isNot(first),
          reason: 'undo always applies to the most recent action');
      // Undo restores the most recent deletion, which is B. A is still gone:
      // there is one undo slot, and holding two would make the toast ambiguous.
      c.undoDelete();
      expect(c.notes.map((Note n) => n.title), <String>['B']);
      expect(c.notes, hasLength(1));
    });

    test('the undo window closes on its own', () async {
      final Notes c = await controller();
      await c.load();
      final Note n = c.createNote()!;
      c.deleteNote(n.id);

      // Uses the real timer rather than fake async so the assertion covers the
      // duration the UI actually shows.
      await Future<void>.delayed(NotesNotifier.undoWindow + const Duration(seconds: 1));
      expect(c.pendingUndo, isNull);
      expect(c.undoDelete(), isFalse);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('corrupt file', () {
    test('blocks every mutation instead of starting empty', () async {
      File(harness.notesFile).writeAsStringSync('{ not json');
      final Notes c = await controller();
      await c.load();

      expect(c.corrupt, isNotNull);
      expect(c.notes, isEmpty);

      // These must all be no-ops. The point is that nothing reaches the file.
      c.createNote();
      c.setQuery('x');
      c.notes.isEmpty;
      final int created = c.notes.length;

      await c.flush();
      expect(File(harness.notesFile).readAsStringSync(), '{ not json');
      expect(created, 0);
    });

    test('a valid file loads normally and clears the error', () async {
      final Notes c = await controller();
      await c.load();
      final Note n = c.createNote()!;
      c.updateNote(n.id, title: 'Fine');
      // Writes are debounced, so without this the second controller reads a
      // file that does not exist yet.
      await c.flush();

      final Notes fresh = await controller();
      await fresh.load();
      expect(fresh.corrupt, isNull);
      expect(fresh.notes.single.title, 'Fine');
    });
  });

  group('import and export', () {
    test('replaceAll swaps the whole library', () async {
      final Notes c = await controller();
      await c.load();
      final Note old = c.createNote()!;
      c.updateNote(old.id, title: 'old');

      final List<Note> incoming = <Note>[
        Note(
          id: 'i1',
          title: 'One',
          body: 'a',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
      c.replaceAll(incoming);
      expect(c.notes.map((Note n) => n.title), <String>['One']);
      expect(c.selectedId, 'i1');
    });

    test('merge keeps existing notes and selects the new one', () async {
      final Notes c = await controller();
      await c.load();
      final Note existing = c.createNote()!;
      c.updateNote(existing.id, title: 'existing');

      c.merge(<Note>[
        Note(
          id: 'i2',
          title: 'imported',
          body: 'b',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ]);
      expect(c.notes.map((Note n) => n.title), containsAll(<dynamic>['existing', 'imported']));
      expect(c.selectedId, 'i2');
    });

    test('merging nothing does nothing', () async {
      final Notes c = await controller();
      await c.load();
      final Note only = c.createNote()!;
      c.updateNote(only.id, title: 'only');
      c.merge(<Note>[]);
      expect(c.notes, hasLength(1));
    });
  });
}

/// Holds a file open the way antivirus does, so a reader cannot open it at all.
///
/// Needed because pure Dart cannot reproduce the bug it guards: `dart:io` opens
/// files with `FILE_SHARE_READ | FILE_SHARE_WRITE`, so a handle taken from Dart
/// never blocks a reader. Calling `CreateFileW` with a share mode of zero is the
/// only way to make a read genuinely fail the way it does on a live desktop,
/// which is the whole point - the defect was invisible until the file was
/// actually held.
///
/// Windows only, and a no-op elsewhere so the rest of the suite still runs.
class _ExclusiveLock {
  _ExclusiveLock(this._handle);

  final Pointer<Void> _handle;

  static const int _genericRead = 0x80000000;
  static const int _openExisting = 3;
  static const int _fileAttributeNormal = 0x80;
  static const int _invalidHandleValue = -1;

  static bool get _supported => Platform.isWindows;

  /// Allocated through the C runtime already in the process, rather than through
  /// package:ffi, which this project does not depend on and should not start
  /// depending on for a test helper.
  static final Pointer<Void> Function(int) _malloc =
      DynamicLibrary.process().lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
  static final void Function(Pointer<Void>) _free =
      DynamicLibrary.process().lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');

  static Pointer<Uint16> _allocateUtf16(List<int> units) {
    final Pointer<Void> raw = _malloc((units.length + 1) * 2);
    final Pointer<Uint16> typed = raw.cast<Uint16>();
    for (int i = 0; i < units.length; i++) {
      typed[i] = units[i];
    }
    typed[units.length] = 0;
    return typed;
  }

  static _ExclusiveLock acquire(String path) {
    if (!_supported) return _ExclusiveLock(Pointer<Void>.fromAddress(0));
    final DynamicLibrary kernel32 = DynamicLibrary.process();
    final Pointer<Void> Function(Pointer<Uint16>, int, Pointer<Void>, Pointer<Void>, int, int, Pointer<Void>) createFile = kernel32.lookupFunction<
        Pointer<Void> Function(
            Pointer<Uint16>, Uint32, Pointer<Void>, Pointer<Void>, Uint32, Uint32, Pointer<Void>),
        Pointer<Void> Function(Pointer<Uint16>, int, Pointer<Void>, Pointer<Void>, int, int,
            Pointer<Void>)>('CreateFileW');

    final Pointer<Uint16> buffer = _allocateUtf16(path.codeUnits);

    // Share mode 0 is the whole point: nobody else may open the file, for
    // reading or writing, until this handle is closed.
    final Pointer<Void> handle = createFile(
      buffer,
      _genericRead,
      nullptr,
      nullptr,
      _openExisting,
      _fileAttributeNormal,
      nullptr,
    );
    _free(buffer.cast<Void>());
    expect(handle.address, isNot(_invalidHandleValue),
        reason: 'the test could not take the exclusive lock it depends on');
    return _ExclusiveLock(handle);
  }

  void release() {
    if (!_supported || _handle.address == 0) return;
    DynamicLibrary.process()
        .lookupFunction<Uint32 Function(Pointer<Void>), int Function(Pointer<Void>)>('CloseHandle')
        .call(_handle);
  }
}
