import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/src/data/note.dart';
import 'package:win_notes/src/data/notes_repository.dart';

void main() {
  const backup = BackupService();
  final now = DateTime(2026, 3, 4);

  Note note(String id, String title, String body) => Note(
        id: id,
        title: title,
        body: body,
        createdAt: now,
        updatedAt: now,
      );

  group('round trip', () {
    test('keeps titles and bodies intact', () {
      final original = [
        note('a', 'Groceries', 'Milk, sourdough\nCheck the bike light'),
        note('b', 'Ideas', 'Widget per monitor?'),
        note('c', 'Single line', 'Just one line'),
      ];

      final restored = backup.import(backup.export(original));

      expect(restored, hasLength(3));
      // Export writes newest first, so all three notes share a timestamp and
      // the order is decided by the id tie-break. Comparing as a set keeps this
      // about the round trip rather than about tie-breaking.
      expect(restored.map((n) => n.title).toSet(),
          {'Groceries', 'Ideas', 'Single line'});
      // Looked up by title rather than by index, because the export order for
      // notes sharing a timestamp is decided by the id tie-break and is not
      // what this test is about.
      Note named(String title) => restored.firstWhere((n) => n.title == title);
      expect(named('Groceries').body, 'Milk, sourdough\nCheck the bike light');
      expect(named('Ideas').body, 'Widget per monitor?');
      expect(named('Single line').body, 'Just one line');
    });

    test('restored notes get fresh ids, because the old ones may be taken',
        () {
      final restored = backup.import(backup.export([note('a', 'T', 'B')]));
      expect(restored.single.id, isNot('a'));
      expect(restored.single.id, isNotEmpty);
    });

    test('an empty library round trips to an empty library', () {
      expect(backup.import(backup.export(const [])), isEmpty);
    });

    test('the exported text is readable without this app', () {
      final text = backup.export([note('a', 'Groceries', 'Milk')]);
      expect(text, contains('WinNotes backup'));
      expect(text, contains('Groceries'));
      expect(text, contains('Milk'));
      expect(text, contains('Notes: 1'));
    });

    test('a whitespace-only body comes back empty, not as blank lines', () {
      // Deliberate, and previously only asserted in prose. A body of nothing but
      // spaces or newlines is not text, and the importer cannot tell it from the
      // blank line the exporter writes after the title - so it trims to empty
      // rather than inventing content. Pinned so the normalisation is a decision
      // someone can rely on, not a surprise found in a backup years later.
      for (final body in ['', ' ', '   ', '\n', '  \n  ']) {
        final restored =
            backup.import(backup.export([note('a', 'T', body)])).single;
        expect(restored.body, '',
            reason: 'body ${body.replaceAll('\n', r'\n')} should normalise '
                'to empty');
      }
      // And a body with real text in it keeps its own whitespace, so this is a
      // whitespace rule and not a "short bodies are dropped" rule.
      expect(
        backup.import(backup.export([note('a', 'T', '  a  ')])).single.body,
        '  a  ',
      );
    });
  });

  group('bodies containing a divider', () {
    // Rows of dashes are exactly what someone writing notes by hand would type,
    // and a markdown rule inside a body is entirely ordinary. Splitting on one
    // exact string would truncate the note at that line.
    test('a row of dashes inside a body survives the round trip', () {
      const rule = '----------------------------------------';
      final original = note('a', 'Rules', 'before\n$rule\nafter');

      final restored = backup.import(backup.export([original]));
      expect(restored, hasLength(1), reason: 'the body did not split the note in two');
      expect(restored.single.body, 'before\n$rule\nafter');
    });

    test('a body containing the exact separator survives too', () {
      const line = BackupService.separator;
      final original = note('a', 'Rules', 'before\n$line\nafter');

      final restored = backup.import(backup.export([original]));
      expect(restored, hasLength(1));
      expect(restored.single.body, 'before\n$line\nafter');
    });

    test('a short run of dashes is a hyphen, not a divider', () {
      final original = note('a', 'Range', 'from 10--20\nto 30--40');

      final restored = backup.import(backup.export([original]));
      expect(restored, hasLength(1));
      expect(restored.single.body, 'from 10--20\nto 30--40');
    });
  });

  group('being forgiving about hand-edited backups', () {
    test('a hand-written backup with no indent imports unchanged', () {
      // The indent is what makes the exporter's own format unambiguous. A person
      // writing a backup by hand does not know about it, so unindented bodies
      // are still accepted, with no blank line between title and body.
      final restored = backup.import(
        '${BackupService.separator}\nTitle only\nBody here',
      );
      expect(restored.single.title, 'Title only');
      expect(restored.single.body, 'Body here');
    });

    test('an unindented multi-line body is kept whole', () {
      final restored = backup.import(
        '${BackupService.separator}\nT\nline one\nline two',
      );
      expect(restored.single.body, 'line one\nline two');
    });

    test('a note with no body is still a note', () {
      final restored = backup.import('${BackupService.separator}\nJust a title');
      expect(restored, hasLength(1));
      expect(restored.single.title, 'Just a title');
      expect(restored.single.body, '');
    });

    test('an empty title with an indented body is still a note', () {
      final text = '${BackupService.separator}\n\n'
          '    No title but has a body';
      final restored = backup.import(text);
      expect(restored.single.title, '');
      expect(restored.single.body, 'No title but has a body');
    });

    test('CRLF line endings are handled', () {
      final text = '${BackupService.separator}\r\nTitle\r\n\r\n'
          '    Body line one\r\n    Body line two';
      final restored = backup.import(text);
      expect(restored.single.title, 'Title');
      expect(restored.single.body, 'Body line one\nBody line two');
    });

    test('trailing blank lines never become a phantom note', () {
      final text = '${BackupService.separator}\nT\n\n    line\n\n\n\n\n';
      final restored = backup.import(text);
      expect(restored, hasLength(1),
          reason: 'the file\'s trailing spacing is not a note');
      expect(restored.single.body, 'line');
    });

    test('blank lines inside a body survive', () {
      final original = note('a', 'Poem', 'line one\n\nline three');
      final restored = backup.import(backup.export([original]));
      expect(restored.single.body, 'line one\n\nline three');
    });

    test('text with no divider at all imports as empty, not a crash', () {
      expect(backup.import('just some random text\nwith no structure'), isEmpty);
      expect(backup.import(''), isEmpty);
    });
  });

  group('note ids from the factory in the importer', () {
    test('are unique across a large import', () {
      // Built through export() rather than by hand, so the input is guaranteed to
      // be in the format the exporter actually produces.
      final original = [
        for (var i = 0; i < 300; i++) note('id$i', 'Note $i', 'body $i'),
      ];
      final restored = backup.import(backup.export(original));
      expect(restored, hasLength(300));
      expect(restored.map((n) => n.id).toSet(), hasLength(300));
    });
  });
}