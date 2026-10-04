import 'dart:math';

/// A stored note: a title, a body, and the timestamps nothing displays.
///
/// The timestamps exist because notes sort by most recently edited, because undo
/// has to put a deleted note back where it was, and because [completedAt] is the
/// only record of when a task was actually finished. None of them are shown.
class Note {
  Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String id;
  String title;
  String body;
  final DateTime createdAt;
  DateTime updatedAt;

  /// When the note was marked finished, or null while it is still open.
  ///
  /// A timestamp rather than a flag, because "when did I finish this" is the
  /// question worth being able to answer later, and because absence is already
  /// an unambiguous "not finished" without needing a second field.
  DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  /// A note exists even with nothing in it. Deleting the last character of a
  /// body is not the same as deleting the note, so emptiness is never a reason
  /// to drop one.
  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  /// What the widget shows. The title is a separate line because the widget
  /// has room for exactly one of the two, and which one matters changes with
  /// how much has been written.
  String get displayTitle {
    final trimmed = title.trim();
    return trimmed.isEmpty ? 'Untitled note' : trimmed;
  }

  bool contains(String query) {
    final needle = query.trim().toLowerCase();
    // A query of only spaces is a query for nothing in particular, not a
    // request to find notes containing three spaces. Trimmed here as well as in
    // the caller so the rule holds wherever this is used.
    if (needle.isEmpty) return true;
    return title.toLowerCase().contains(needle) || body.toLowerCase().contains(needle);
  }

  Note copy() => Note(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        updatedAt: updatedAt,
        // Carried by copy because undo restores a note wholesale. A restored
        // note that silently lost its finished state would be a bug report
        // nobody could explain.
        completedAt: completedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        // Omitted rather than written as null while the note is open, so a file
        // of ordinary notes stays exactly as it was before this field existed.
        if (completedAt != null)
          'completedAt': completedAt!.toUtc().toIso8601String(),
      };

  static Note fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('A note is missing its id.');
    }
    return Note(
      id: id,
      title: json['title'] is String ? json['title'] as String : '',
      body: json['body'] is String ? json['body'] as String : '',
      createdAt: _parseTime(json['createdAt']),
      updatedAt: _parseTime(json['updatedAt']),
      // Absent in every file written before this field existed, and absent again
      // for an open note. Both mean the same thing, which is the point of making
      // it nullable rather than defaulting it to a sentinel date.
      completedAt: _parseOptionalTime(json['completedAt']),
    );
  }

  static DateTime _parseTime(Object? value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Like [_parseTime] but keeps "absent" as absent, rather than inventing the
  /// epoch for a note that was never finished.
  static DateTime? _parseOptionalTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}

/// Creates note ids without pulling in a uuid package.
///
/// Ids only need to be unique within one profile folder and never leave the
/// machine, so a timestamp, a counter and a little entropy is enough.
class NoteIdFactory {
  NoteIdFactory() : _counter = 0;

  int _counter;

  String next() {
    _counter++;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final seq = _counter.toRadixString(36);
    final entropy = _randomBits();
    return '$stamp-$seq-$entropy';
  }

  String _randomBits() {
    // Random.secure() rather than Random(): ids are written to a file that a
    // user may sync, and a predictable id invites collisions after a restore.
    final random = Random.secure();
    final value = random.nextInt(1 << 32);
    return value.toRadixString(36).padLeft(7, '0');
  }
}