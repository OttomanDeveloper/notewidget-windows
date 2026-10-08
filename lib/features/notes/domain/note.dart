import 'dart:math';

/// A stored note: title, body, and undisplayed timestamps for sort order, undo
/// placement and [completedAt].
class Note {
  Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.markdown = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

    /// When the note was marked finished, or null while open. A timestamp, not a
    /// flag: absence already means "not finished", and the date answers "when".
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  /// Whether this note renders as Markdown. Per note, off by default (`PROJECT.md`).
  ///
  /// Source is presented, never rewritten; `- [x]` is an inert box. See `docs/storage_pattern.md`.
  final bool markdown;

  /// A note exists even with nothing in it. Deleting the last character of a
  /// body is not the same as deleting the note, so emptiness is never a reason
  /// to drop one.
  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  /// What the widget shows. The title is a separate line because the widget
  /// has room for exactly one of the two, and which one matters changes with
  /// how much has been written.
  String get displayTitle {
    final String trimmed = title.trim();
    return trimmed.isEmpty ? 'Untitled note' : trimmed;
  }

  bool contains(String query) {
    final String needle = query.trim().toLowerCase();
    // A query of only spaces is a query for nothing in particular, not a
    // request to find notes containing three spaces. Trimmed here as well as in
    // the caller so the rule holds wherever this is used.
    if (needle.isEmpty) return true;
    return title.toLowerCase().contains(needle) || body.toLowerCase().contains(needle);
  }

  // Value equality over every field, so `ref.select` on a note rebuilds only
  // when its content actually changed. Safe because notes are immutable: an
  // edit produces a new object rather than mutating in place.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note &&
          id == other.id &&
          title == other.title &&
          body == other.body &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          completedAt == other.completedAt &&
          markdown == other.markdown;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        body,
        createdAt,
        updatedAt,
        completedAt,
        markdown,
      );

  Note copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    bool? markdown,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
        markdown: markdown ?? this.markdown,
      );

  Note copy() => copyWith();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        // Omitted rather than written as null while the note is open, so a file
        // of ordinary notes stays exactly as it was before this field existed.
        if (completedAt != null)
          'completedAt': completedAt!.toUtc().toIso8601String(),
        // Same rule, same reason. False is the default, so writing it would put
        // a field in every existing note's JSON to record the absence of a
        // feature.
        if (markdown) 'markdown': true,
      };

  static Note fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
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
      // Same shape of answer: absent means plain text. Anything that is not
      // literally true is false, so a hand-edited `"markdown": "yes"` cannot
      // turn a note into something the renderer has never been asked to handle.
      markdown: json['markdown'] == true,
    );
  }

  static DateTime _parseTime(Object? value) {
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
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
/// Unique within one local profile folder only: timestamp, counter, entropy.
class NoteIdFactory {
  NoteIdFactory() : _counter = 0;

  int _counter;

  String next() {
    _counter++;
    final String stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final String seq = _counter.toRadixString(36);
    final String entropy = _randomBits();
    return '$stamp-$seq-$entropy';
  }

  String _randomBits() {
    // Random.secure() rather than Random(): ids are written to a file that a
    // user may sync, and a predictable id invites collisions after a restore.
    final Random random = Random.secure();
    final int value = random.nextInt(1 << 32);
    return value.toRadixString(36).padLeft(7, '0');
  }
}