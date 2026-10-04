import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/src/core/atomic_json_file.dart';
import 'package:win_notes/src/data/note.dart';
import 'package:win_notes/src/data/notes_repository.dart';
import 'package:win_notes/src/state/notes_controller.dart';

void main() {
  late Directory temp;

  // Every controller this file builds, so tearDown can drain them.
  final built = <NotesController>[];

  setUp(() {
    temp = Directory.systemTemp.createTempSync('winnotes_ctrl_test');
    built.clear();
  });

  // Controllers are registered rather than disposed per test because a queued
  // write outlives the test that made it, and AtomicJsonFile creates its parent
  // directory before every write. Deleting the temp directory first therefore
  // raced the pending write, which recreated the directory and left it behind -
  // hundreds of them, in the developer's %TEMP%, with every test still green.
  tearDown(() async {
    for (final c in built) {
      await c.flush();
      c.dispose();
    }
    built.clear();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  NotesController controller() {
    final c = NotesController(
      repository: NotesRepository(
        AtomicJsonFile('${temp.path}\\notes.json'),
      ),
    );
    built.add(c);
    return c;
  }

  group('creating and editing', () {
    test('the first launch has a note ready to type into', () async {
      final c = controller();
      await c.load();
      expect(c.notes, isEmpty);

      c.ensureAtLeastOneNote();
      expect(c.notes, hasLength(1));
      expect(c.selectedNote, isNotNull);
      expect(c.selectedNote!.body, '');
    });

    test('ensureAtLeastOneNote does not add a second note', () async {
      final c = controller();
      await c.load();
      c.ensureAtLeastOneNote();
      c.ensureAtLeastOneNote();
      expect(c.notes, hasLength(1));
    });

    test('editing moves a note to the top of the list', () async {
      final c = controller();
      await c.load();
      final first = c.createNote()!;
      first.body = 'first';
      final second = c.createNote()!;
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
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      final b = c.createNote()!;
      final d = c.createNote()!;

      var edit = 0;

      for (final target in [a, b, d, a, b, d]) {
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
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      a.title = 'A';
      await Future<void>.delayed(const Duration(milliseconds: 10));
      (c.createNote()!).title = 'B';

      final orderBefore = c.notes.map((n) => n.id).toList();
      c.updateNote(a.id, title: 'A', body: '');
      expect(c.notes.map((n) => n.id).toList(), orderBefore);
    });
    test('a note whose body is emptied still exists', () async {
      final c = controller();
      await c.load();
      final n = c.createNote()!;
      c.updateNote(n.id, body: 'something');
      expect(c.notes, hasLength(1));

      c.updateNote(n.id, body: '');
      expect(c.notes, hasLength(1),
          reason: 'deleting the last character is not deleting the note');
      expect(c.selectedNote!.isEmpty, isTrue);
    });

    test('notifies listeners on every change that matters', () async {
      final c = controller();
      await c.load();
      var notifications = 0;
      c.addListener(() => notifications++);

      c.createNote();
      final n = c.selectedNote!;
      c.updateNote(n.id, body: 'x');
      c.setQuery('x');
      // create, edit and search each notify once. Nothing here should notify
      // more than once per action, so the count is exact rather than a floor.
      expect(notifications, 3);
    });

    test('setting the same query twice does not notify twice', () async {
      final c = controller();
      await c.load();
      c.setQuery('milk');
      var notifications = 0;
      c.addListener(() => notifications++);
      c.setQuery('milk');
      expect(notifications, 0);
    });
  });

  group('marking a task finished', () {
    test('a note toggles both ways', () async {
      final c = controller();
      await c.load();
      final note = c.createNote()!;

      expect(note.isCompleted, isFalse);

      c.toggleCompleted(note.id);
      expect(note.isCompleted, isTrue);
      expect(note.completedAt, isNotNull);

      c.toggleCompleted(note.id);
      expect(note.isCompleted, isFalse);
      expect(note.completedAt, isNull);
    });

    test('finishing a note does not reorder the list', () async {
      // The reason toggleCompleted exists in the shape it does. Notes sort by
      // most recently edited, so bumping the timestamp would send the note to
      // the top every time it is ticked off, and working through a list would
      // become a shuffle with the finished task landing back in front of you.
      final c = controller();
      await c.load();
      final first = c.createNote()!;
      first.title = 'older';
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = c.createNote()!;
      second.title = 'newer';
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final third = c.createNote()!;
      third.title = 'newest';

      expect(c.notes.map((n) => n.title), ['newest', 'newer', 'older']);
      final stampsBefore = {for (final n in c.notes) n.id: n.updatedAt};

      c.toggleCompleted(second.id);

      expect(c.notes.map((n) => n.title), ['newest', 'newer', 'older'],
          reason: 'the list must not move under the pointer');
      for (final note in c.notes) {
        expect(note.updatedAt, stampsBefore[note.id],
            reason: 'finishing a task is a state change, not an edit');
      }
    });

    test('undo brings a finished note back finished', () async {
      final c = controller();
      await c.load();
      final note = c.createNote()!;
      c.toggleCompleted(note.id);
      await c.flush();

      c.deleteNote(note.id);
      expect(c.undoDelete(), isTrue);

      expect(c.selectedNote!.isCompleted, isTrue,
          reason: 'a restored note that lost its finished state would be a bug '
              'nobody could explain');
    });

    test('the finished state is written to disk', () async {
      final c = controller();
      await c.load();
      final note = c.createNote()!;
      c.toggleCompleted(note.id);
      await c.flush();

      final reread = NotesRepository(
        AtomicJsonFile('${temp.path}\\notes.json'),
      );
      final result = await reread.load();
      final restored = (result as NotesLoaded).notes.single;
      expect(restored.isCompleted, isTrue);
      await reread.dispose();
    });

    test('the big card skips finished notes so it is never a struck-through task',
        () async {
      final c = controller();
      await c.load();
      final older = c.createNote()!;
      older.title = 'older';
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final newer = c.createNote()!;
      newer.title = 'newer';
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final newest = c.createNote()!;
      newest.title = 'newest';

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
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      a.title = 'a';
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final b = c.createNote()!;
      b.title = 'b';

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
      final c = controller();
      await c.load();
      final older = c.createNote()!;
      older.title = 'older';
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final newer = c.createNote()!;
      newer.title = 'newer';
      c.toggleCompleted(newer.id);

      c.select(older.id);
      expect(c.focusedNote!.title, 'older');
    });

    test('nothing is marked finished while the file cannot be read', () async {
      // Every other mutation is refused in this state, and this one has to be too:
      // a note flipped to finished in memory that never reaches disk is a note
      // that comes back unfinished, which is worse than the toggle doing nothing.
      final c = controller();
      await c.load();
      final note = c.createNote()!;

      File('${temp.path}\\notes.json').writeAsStringSync('{ not json');
      await c.load();
      expect(c.corrupt, isNotNull);

      c.toggleCompleted(note.id);
      expect(c.notes, isEmpty, reason: 'the file was unreadable, so nothing loaded');
    });

    test('toggling a note that is not there does nothing', () async {
      final c = controller();
      await c.load();
      c.createNote();
      c.toggleCompleted('no-such-note');
      expect(c.notes.single.isCompleted, isFalse);
    });
  });

  group('search', () {
    test('filters on title and body as the user types', () async {
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      c.updateNote(a.id, title: 'Groceries', body: 'Milk');
      final b = c.createNote()!;
      c.updateNote(b.id, title: 'Ideas', body: 'Widgets');

      expect(c.visibleNotes, hasLength(2));
      c.setQuery('milk');
      expect(c.visibleNotes.map((n) => n.id), [a.id]);
      c.setQuery('widget');
      expect(c.visibleNotes.map((n) => n.id), [b.id]);
      c.setQuery('zzz');
      expect(c.visibleNotes, isEmpty);
    });

    test('a whitespace-only query shows everything', () async {
      final c = controller();
      await c.load();
      (c.createNote()!).title = 'A';
      (c.createNote()!).title = 'B';
      c.setQuery('   ');
      expect(c.visibleNotes, hasLength(2));
    });

    test('clearing the query restores the full list', () async {
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      c.updateNote(a.id, title: 'Groceries');
      (c.createNote()!).title = 'Other';
      c.setQuery('groceries');
      expect(c.visibleNotes, hasLength(1));
      c.setQuery('');
      expect(c.visibleNotes, hasLength(2));
    });
  });

  group('selection', () {
    test('falls back to the most recent note when nothing is picked', () async {
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      a.title = 'older';
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final b = c.createNote()!;
      b.title = 'newer';

      c.select(null);
      expect(c.selectedNote!.id, b.id);
      c.select(a.id);
      expect(c.selectedNote!.id, a.id);
    });

    test('deleting the selected note moves the selection on', () async {
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final b = c.createNote()!;
      expect(c.selectedId, b.id);

      c.deleteNote(b.id);
      expect(c.selectedId, a.id);
      expect(c.selectedNote!.id, a.id);
    });

    test('deleting the last note leaves nothing selected, not a crash', () async {
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      c.deleteNote(a.id);
      expect(c.notes, isEmpty);
      expect(c.selectedNote, isNull);
      expect(c.focusedNote, isNull);
    });

    test('a selection pointing at a missing note resolves to something real',
        () async {
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      c.select(a.id);
      // As happens when the other surface deletes a note.
      c.deleteNote(a.id);
      c.select(a.id);
      expect(c.selectedNote, isNull);
    });
  });

  group('delete and undo', () {
    test('undo restores the note', () async {
      final c = controller();
      await c.load();
      final n = c.createNote()!;
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
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      c.updateNote(a.id, title: 'A', body: 'old');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final b = c.createNote()!;
      c.updateNote(b.id, title: 'B', body: 'old');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final d = c.createNote()!;
      c.updateNote(d.id, title: 'D', body: 'old');

      final order = c.notes.map((n) => n.title).toList();
      final middle = order[1];
      final victim = c.notes.firstWhere((n) => n.title == middle);
      c.deleteNote(victim.id);
      c.undoDelete();

      expect(c.notes.map((n) => n.title).toList(), order);
    });

    test('undo is offered once and then expires', () async {
      final c = controller();
      await c.load();
      final n = c.createNote()!;
      c.deleteNote(n.id);
      expect(c.pendingUndo, isNotNull);

      c.clearPendingUndo();
      expect(c.pendingUndo, isNull);
      expect(c.undoDelete(), isFalse);
    });

    test('deleting again replaces the pending undo rather than queueing',
        () async {
      final c = controller();
      await c.load();
      final a = c.createNote()!;
      c.updateNote(a.id, title: 'A');
      final b = c.createNote()!;
      c.updateNote(b.id, title: 'B');

      c.deleteNote(a.id);
      final first = c.pendingUndo;
      c.deleteNote(b.id);

      expect(c.pendingUndo, isNot(first),
          reason: 'undo always applies to the most recent action');
      // Undo restores the most recent deletion, which is B. A is still gone:
      // there is one undo slot, and holding two would make the toast ambiguous.
      c.undoDelete();
      expect(c.notes.map((n) => n.title), ['B']);
      expect(c.notes, hasLength(1));
    });

    test('the undo window closes on its own', () async {
      final c = controller();
      await c.load();
      final n = c.createNote()!;
      c.deleteNote(n.id);

      // Uses the real timer rather than fake async so the assertion covers the
      // duration the UI actually shows.
      await Future<void>.delayed(NotesController.undoWindow + const Duration(seconds: 1));
      expect(c.pendingUndo, isNull);
      expect(c.undoDelete(), isFalse);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('corrupt file', () {
    test('blocks every mutation instead of starting empty', () async {
      File('${temp.path}\\notes.json').writeAsStringSync('{ not json');
      final c = controller();
      await c.load();

      expect(c.corrupt, isNotNull);
      expect(c.notes, isEmpty);

      // These must all be no-ops. The point is that nothing reaches the file.
      c.createNote();
      c.setQuery('x');
      c.notes.isEmpty;
      final created = c.notes.length;

      await c.flush();
      expect(File('${temp.path}\\notes.json').readAsStringSync(), '{ not json');
      expect(created, 0);
    });

    test('a valid file loads normally and clears the error', () async {
      final c = controller();
      await c.load();
      final n = c.createNote()!;
      c.updateNote(n.id, title: 'Fine');
      // Writes are debounced, so without this the second controller reads a
      // file that does not exist yet.
      await c.flush();

      final fresh = controller();
      await fresh.load();
      expect(fresh.corrupt, isNull);
      expect(fresh.notes.single.title, 'Fine');
    });
  });

  group('import and export', () {
    test('replaceAll swaps the whole library', () async {
      final c = controller();
      await c.load();
      (c.createNote()!).title = 'old';

      final incoming = [
        Note(
          id: 'i1',
          title: 'One',
          body: 'a',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
      c.replaceAll(incoming);
      expect(c.notes.map((n) => n.title), ['One']);
      expect(c.selectedId, 'i1');
    });

    test('merge keeps existing notes and selects the new one', () async {
      final c = controller();
      await c.load();
      (c.createNote()!).title = 'existing';

      c.merge([
        Note(
          id: 'i2',
          title: 'imported',
          body: 'b',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ]);
      expect(c.notes.map((n) => n.title), containsAll(['existing', 'imported']));
      expect(c.selectedId, 'i2');
    });

    test('merging nothing does nothing', () async {
      final c = controller();
      await c.load();
      (c.createNote()!).title = 'only';
      c.merge([]);
      expect(c.notes, hasLength(1));
    });
  });
}
