import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/atomic_json_file.dart';
import 'note.dart';

/// Result of loading the notes document.
sealed class NotesLoadResult {
  const NotesLoadResult();
}

class NotesLoaded extends NotesLoadResult {
  const NotesLoaded(this.notes);
  final List<Note> notes;
}

/// The file exists but could not be read.
///
/// Carries the path so the UI can offer it as an import target later, which is
/// how a backup gets restored by hand without this app having to parse it.
class NotesCorrupt extends NotesLoadResult {
  const NotesCorrupt(this.error);
  final CorruptDataFile error;
}

/// Owns `notes.json` and is the only writer of it.
///
/// The widget surface reads this file and never writes it, so there is exactly
/// one writer in the whole app and no possibility of two isolates racing to
/// clobber each other's keystrokes.
class NotesRepository {
  NotesRepository(this._file);

  final AtomicJsonFile _file;

  static const String _formatTag = 'winnotes';
  static const int _formatVersion = 1;

  CorruptDataFile? get blocked => _file.blocked;

  Future<NotesLoadResult> load() async {
    try {
      final json = await _file.read();
      // A file that is valid JSON but not ours is still a file the app did not
      // write and cannot vouch for, so it is treated the same as unparseable.
      if (json.isEmpty) return const NotesLoaded([]);
      final format = json['format'];
      if (format != _formatTag) {
        throw CorruptDataFile(
          path: _file.path,
          reason: 'The file is not a WinNotes document (expected format "$_formatTag").',
        );
      }
      final rawNotes = json['notes'];
      if (rawNotes is! List) {
        throw CorruptDataFile(
          path: _file.path,
          reason: 'The "notes" entry is missing or is not a list.',
        );
      }
      final notes = <Note>[];
      for (final entry in rawNotes) {
        if (entry is! Map) {
          throw CorruptDataFile(
            path: _file.path,
            reason: 'A note entry is not an object.',
          );
        }
        try {
          notes.add(Note.fromJson(Map<String, dynamic>.from(entry)));
        } on FormatException catch (error) {
          throw CorruptDataFile(
            path: _file.path,
            reason: error.message,
            underlying: error,
          );
        }
      }
      return NotesLoaded(notes);
    } on CorruptDataFile catch (error) {
      _file.blocked = error;
      return NotesCorrupt(error);
    }
  }

  /// Newest first, always, with no sorting options to get wrong.
  static List<Note> sorted(Iterable<Note> notes) {
    final list = notes.toList();
    list.sort((a, b) {
      final byRecency = b.updatedAt.compareTo(a.updatedAt);
      // Ids break ties so the order does not shuffle between two writes of the
      // same millisecond.
      return byRecency != 0 ? byRecency : b.id.compareTo(a.id);
    });
    return list;
  }

  void save(List<Note> notes) {
    if (_file.blocked != null) return;
    _file.write({
      'format': _formatTag,
      'version': _formatVersion,
      'notes': notes.map((n) => n.toJson()).toList(),
    });
  }

  Future<void> saveNow(List<Note> notes) => _file.writeNow({
        'format': _formatTag,
        'version': _formatVersion,
        'notes': notes.map((n) => n.toJson()).toList(),
      });

  /// Watches for a document written by the other surface. Only the widget
  /// surface uses this; the editor is the writer.
  void watch(void Function() onChanged) => _file.watch(onChanged);

  /// Lets a restore clear the block, so a hand-chosen backup can replace a
  /// file the app refused to overwrite on its own.
  void unblock() {
    _file.blocked = null;
  }

  /// Where the rolling backup lives, or null when there is not one yet.
  ///
  /// Checked rather than assumed, because "restore the previous version" has to
  /// be offered only when it would actually do something. On a first run, or
  /// after a single write, there is no previous version to restore.
  String? get backupPath {
    final candidate = AtomicJsonFile.backupPathFor(_file.path);
    return File(candidate).existsSync() ? candidate : null;
  }

  /// Replaces the unreadable file with the rolling backup.
  ///
  /// The one recovery route that asks nothing of the person holding the problem:
  /// no backup they had to remember to make, no file to go and find. Returns the
  /// number of notes recovered, or null if there was no backup or it could not be
  /// used - in which case the block stays, because a half-applied recovery that
  /// loses the notes it read would be the worst outcome available.
  Future<int?> restoreBackup() async {
    final backup = backupPath;
    if (backup == null) return null;

    final result = await loadFrom(File(backup));
    switch (result) {
      case NotesLoaded(:final notes):
        _file.blocked = null;
        // Copied rather than re-serialised through the normal write, and that
        // detail matters. A normal write would first copy the file it is
        // replacing - the corrupt one - over the backup, so recovering would
        // destroy the only good copy you had. Copying leaves notes.json and
        // notes.json.bak both holding the recovered version, so the net is still
        // there if the file is damaged a second time.
        try {
          await File(backup).copy(_file.path);
        } on FileSystemException {
          // Held by whatever was holding it a moment ago. Falling back to the
          // write path still recovers the notes; it just costs the safety net.
          await saveNow(notes);
        }
        return notes.length;
      case NotesCorrupt():
        // The backup is damaged too, which is worth knowing but not worth
        // reporting as a crash. The caller falls back to the other options.
        return null;
    }
  }

  /// Moves the unreadable file aside and lets the app start over.
  ///
  /// Renames, never deletes. The file on disk may be recoverable by hand, or by
  /// someone better at JSON than the person staring at the screen, and throwing
  /// away the only copy of a damaged file to make a button feel better would be
  /// the opposite of what this project is for. The name carries a timestamp so
  /// a second incident cannot overwrite the first one's evidence.
  ///
  /// Returns where the old file went, or null if it could not be moved - most
  /// likely because something else is holding it open, in which case the caller
  /// should say so rather than pretend it worked.
  Future<String?> setAsideAndStartFresh() async {
    final source = File(_file.path);
    if (!source.existsSync()) {
      // Nothing to move. The file has already gone, which is the case the app
      // already treats as a first run, so just unblock.
      _file.blocked = null;
      return null;
    }
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final kept = '${_file.path}.broken-$stamp';
    try {
      await source.rename(kept);
    } on FileSystemException {
      return null;
    }
    _file.blocked = null;
    return kept;
  }

  /// Loads from an arbitrary file, so recovery can be read before it is trusted.
  Future<NotesLoadResult> loadFrom(File file) async {
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const NotesLoaded([]);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const NotesLoaded([]);
      if (decoded['format'] != _formatTag) return const NotesLoaded([]);
      final rawNotes = decoded['notes'];
      if (rawNotes is! List) return const NotesLoaded([]);
      final notes = <Note>[];
      for (final entry in rawNotes) {
        if (entry is! Map) continue;
        try {
          notes.add(Note.fromJson(Map<String, dynamic>.from(entry)));
        } on FormatException {
          // One unreadable note does not condemn the rest. Refusing the whole
          // backup would throw away the notes that are perfectly fine, which is
          // the opposite of what someone recovering from corruption needs.
        }
      }
      return NotesLoaded(notes);
    } on FileSystemException {
      return NotesCorrupt(CorruptDataFile(path: file.path, reason: 'unreadable'));
    } on FormatException {
      return NotesCorrupt(CorruptDataFile(path: file.path, reason: 'not JSON'));
    }
  }

  Future<void> flush() => _file.flushPending();
  Future<void> dispose() => _file.dispose();

  String get path => _file.path;
}

/// Exports and imports notes as plain text.
///
/// The format is deliberately boring: one note per block, the title on the
/// first line, then the body, separated by a line of dashes. A backup taken
/// years from now has to be readable without this app.
class BackupService {
  const BackupService();

  /// A markdown horizontal rule, chosen because it is the one divider a person
  /// hand-writing a backup would reach for - which makes it exactly the string
  /// most likely to turn up inside a note body.
  ///
  /// The importer does not use this as a delimiter at all. It splits on any line
  /// of three or more dashes and re-inserts the body verbatim, so a body
  /// containing a rule of any length survives the round trip. Treating the
  /// delimiter as "a line of dashes" rather than "this exact string" is what
  /// makes that true.
  static const String separator =
      '----------------------------------------';

  /// True for a note boundary: an unindented line of three or more dashes,
  /// asterisks or underscores, which is the one thing the exporter never writes
  /// inside a body.
  static bool _isDivider(String line) {
    if (line.startsWith(bodyIndent)) return false;
    final trimmed = line.trimRight();
    if (trimmed.length < 3) return false;
    for (final unit in trimmed.codeUnits) {
      if (unit != 0x2D && unit != 0x2A && unit != 0x5F) return false;
    }
    return true;
  }

  /// Exports notes as plain text.
  ///
  /// Bodies are indented so the shape of a note survives the round trip. A body
  /// containing a row of dashes is indistinguishable from a note boundary
  /// otherwise, and the only honest way to stop that is to stop the body from
  /// ever looking like one. Import strips the indent again, and tolerates
  /// unindented bodies so a hand-written backup still reads.
  ///
  /// The indent is deliberately spaces rather than a tab: a tab renders as
  /// eight columns in some editors and one in others, and a backup has to look
  /// the same in whatever opens it.
  static const String bodyIndent = '    ';

  String export(List<Note> notes) {
    final buffer = StringBuffer()
      ..writeln('WinNotes backup')
      ..writeln('Exported: ${DateTime.now().toIso8601String()}')
      ..writeln('Notes: ${notes.length}')
      ..writeln();

    // Written in the order the user sees them, which is already newest first,
    // so an import produces the same list a person was looking at.
    for (final note in NotesRepository.sorted(notes)) {
      buffer
        ..writeln(separator)
        ..writeln(note.title.trim())
        ..writeln();
      for (final line in note.body.split('\n')) {
        // A blank body line is written as a bare indent rather than an empty
        // line, so the reader can tell "blank line in the body" from "blank
        // line that ends the body".
        buffer.writeln(line.isEmpty ? bodyIndent : '$bodyIndent$line');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Parses the plain-text backup format.
  ///
  /// Deliberately forgiving: a backup edited in Notepad is still a backup. A
  /// block with no title simply becomes a note with an empty title, which is a
  /// perfectly valid note.
  List<Note> import(String text) {
    // Normalised first so a file saved or edited on Windows reads the same as
    // one written anywhere else. Splitting on \r\n alone would leave a stray \r
    // glued to the end of every body line.
    final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final notes = <Note>[];
    final factory = NoteIdFactory();

    var index = 0;
    // Skip the header up to the first divider.
    while (index < lines.length && !_isDivider(lines[index])) {
      index++;
    }

    // Each iteration consumes exactly one divider, one title line and one body,
    // so the loop runs once per note. The body scan below always leaves `index`
    // on the next divider (or the end), which is what keeps the count exact:
    // any earlier attempt to "skip blank lines to find the next block" turned
    // the spacing the exporter writes between notes into phantom empty notes.
    while (index < lines.length) {
      while (index < lines.length && _isDivider(lines[index])) {
        index++;
      }

      // A divider with nothing after it is a divider, not a note.
      if (!_hasContent(lines, index)) break;

      // The title is the first line after the divider, taken verbatim rather
      // than skipping blanks first. Skipping blanks would swallow the one
      // legitimate empty title a block can have, turning it into the body's
      // first line instead.
      final title = lines[index].trim();
      index++;

      // The exporter writes one blank line between the title and the body.
      // Exactly one, so a hand-written note with a deliberate blank line there
      // is not disturbed.
      if (index < lines.length && lines[index].isEmpty) index++;

      // Only indented lines are body. Everything else after the blank line is
      // the spacing the exporter wrote before the next divider, and treating it
      // as content is what produced an empty phantom note between every pair.
      // Body lines run to the next divider. Indented lines have the indent
      // stripped. Unindented lines are accepted as body too, but only up to the
      // first run of blank lines: that run is the spacing before the next
      // divider, and treating it as content is what produced a phantom empty
      // note between every pair of real ones.
      final body = <String>[];
      var indentStops = false;
      while (index < lines.length && !_isDivider(lines[index])) {
        final line = lines[index];
        if (line.startsWith(bodyIndent)) {
          body.add(line.substring(bodyIndent.length));
        } else if (indentStops && line.trim().isEmpty) {
          // Spacing before the next divider. Consumed here rather than left for
          // the top of the loop, so the next iteration starts on a divider.
          index++;
          break;
        } else {
          if (line.trim().isNotEmpty) indentStops = true;
          body.add(line);
        }
        index++;
      }

      final now = DateTime.now();
      notes.add(Note(
        id: factory.next(),
        title: title,
        body: _trimTrailingBlanks(body).join('\n'),
        createdAt: now,
        updatedAt: now,
      ));
    }
    return notes;
  }

  /// True when anything but blank lines remains.
  static bool _hasContent(List<String> lines, int from) {
    for (var i = from; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) return true;
    }
    return false;
  }

  static List<String> _trimTrailingBlanks(List<String> lines) {
    var end = lines.length;
    while (end > 0 && lines[end - 1].trim().isEmpty) {
      end--;
    }
    return lines.sublist(0, end);
  }
}

/// Which note is focused, shared by both surfaces.
///
/// Its own tiny file rather than a field in either surface's data, because both
/// surfaces read and write it and neither owns it.
class SelectionRepository {
  SelectionRepository(this._file);

  final AtomicJsonFile _file;

  String? _cached;

  String? get cached => _cached;

  /// Read synchronously at startup so the first widget frame already shows the
  /// right card, rather than flashing the most recent note and then correcting.
  String? readSelection() {
    return _cached ??= _readFromDisk(_file.path);
  }

  static String? _readFromDisk(String path) {
    final contents = _syncRead(path);
    if (contents == null) return null;
    try {
      final decoded = jsonDecode(contents);
      if (decoded is Map && decoded['noteId'] is String) {
        final id = decoded['noteId'] as String;
        return id.isEmpty ? null : id;
      }
    } on FormatException {
      // A damaged selection file is not worth refusing to start over; the worst
      // case is that the widget shows the most recent note instead.
    }
    return null;
  }

  void setSelection(String? noteId) {
    _cached = noteId;
    _file.write({'noteId': noteId ?? ''});
  }

  void watch(void Function() onChanged) => _file.watch(onChanged);

  Future<void> flush() => _file.flushPending();
  Future<void> dispose() => _file.dispose();
}

/// Synchronous read, for the handful of values needed before the first frame.
String? _syncRead(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync();
    return text.trim().isEmpty ? null : text;
  } on FileSystemException {
    return null;
  }
}