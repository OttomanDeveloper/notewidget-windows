import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/src/data/note.dart';

void main() {
  Note make({String id = 'n1', String title = 't', String body = 'b'}) => Note(
        id: id,
        title: title,
        body: body,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );

  group('Note', () {
    test('a note with nothing in it still exists', () {
      final note = make(title: '', body: '');
      expect(note.isEmpty, isTrue);
      // isEmpty is informational only. Nothing in the app deletes a note
      // because of it, because clearing the last character of a body is not the
      // same as deleting the note.
    });

    test('displayTitle falls back rather than showing a blank', () {
      expect(make(title: '').displayTitle, 'Untitled note');
      expect(make(title: '   ').displayTitle, 'Untitled note');
      expect(make(title: ' Shopping ').displayTitle, 'Shopping');
    });

    test('search matches title and body, case-insensitively', () {
      final note = make(title: 'Groceries', body: 'Milk and bread');
      expect(note.contains('groc'), isTrue);
      expect(note.contains('MILK'), isTrue);
      expect(note.contains('and br'), isTrue);
      expect(note.contains('shoes'), isFalse);
    });

    test('an empty query matches everything', () {
      expect(make().contains(''), isTrue);
      expect(make().contains('   '), isTrue);
    });

    test('survives a JSON round trip', () {
      final original = make(title: 'Line\nbreak', body: 'tab\there');
      final restored = Note.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.body, original.body);
      expect(restored.createdAt.toUtc(), original.createdAt.toUtc());
      expect(restored.updatedAt.toUtc(), original.updatedAt.toUtc());
    });

    test('timestamps are stored in UTC and read back as local', () {
      final note = make();
      final json = note.toJson();
      expect(json['updatedAt'], endsWith('Z'));
      expect(Note.fromJson(json).updatedAt.isUtc, isFalse);
    });

    test('a note missing its id is rejected rather than half-read', () {
      expect(
        () => Note.fromJson({'title': 'x', 'body': 'y'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('missing or malformed fields fall back to empty, not a crash', () {
      final note = Note.fromJson({'id': 'n9'});
      expect(note.title, '');
      expect(note.body, '');
    });

    test('copy is a deep enough copy to restore an undo', () {
      final original = make();
      final duplicate = original.copy();
      duplicate.title = 'changed';
      duplicate.body = 'changed';
      expect(original.title, 't');
      expect(original.body, 'b');
    });
  });

  group('NoteIdFactory', () {
    test('ids are unique', () {
      final factory = NoteIdFactory();
      final ids = <String>{};
      for (var i = 0; i < 5000; i++) {
        ids.add(factory.next());
      }
      expect(ids.length, 5000);
    });

    test('ids do not contain characters that break a path or a JSON string',
        () {
      final factory = NoteIdFactory();
      for (var i = 0; i < 200; i++) {
        expect(factory.next(), matches(RegExp(r'^[a-z0-9-]+$')));
      }
    });
  });
}