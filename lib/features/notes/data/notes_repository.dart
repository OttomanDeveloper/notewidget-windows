import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/utils/atomic_json_file.dart';
import '../domain/note.dart';
import '../domain/repositories.dart';

export '../domain/repositories.dart'
    show NotesLoadResult, NotesLoaded, NotesCorrupt;

/// Owns `notes.json` and is the only writer of it.
///
/// The widget surface only reads, so no two isolates race to clobber keystrokes.
class NotesRepository implements INotesRepository {
  NotesRepository(this._file);

  final AtomicJsonFile _file;

  static const String _formatTag = 'winnotes';
  static const int _formatVersion = 1;

  CorruptDataFile? get blocked => _file.blocked;

  @override
  Future<NotesLoadResult> load() async {
    try {
      final Map<String, dynamic> json = await _file.read();
      // A file that is valid JSON but not ours is still a file the app did not
      // write and cannot vouch for, so it is treated the same as unparseable.
      if (json.isEmpty) return const NotesLoaded(<Note>[]);
      final Object? format = json['format'];
      if (format != _formatTag) {
        throw CorruptDataFile(
          path: _file.path,
          reason: 'The file is not a WinNotes document (expected format "$_formatTag").',
        );
      }
      final Object? rawNotes = json['notes'];
      if (rawNotes is! List) {
        throw CorruptDataFile(
          path: _file.path,
          reason: 'The "notes" entry is missing or is not a list.',
        );
      }
      final List<Note> notes = <Note>[];
      for (final Object? entry in rawNotes) {
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
      return NotesCorrupt(_toError(error));
    }
  }

  /// The `dart:io` error in domain clothing, built once at the detection site so
  /// nothing above this layer meets the file system face to face.
  static CorruptDataFileError _toError(CorruptDataFile error) =>
      CorruptDataFileError(error.path, error.reason,
          transient: error.transient);

  /// Newest first, always, with no sorting options to get wrong.
  static List<Note> sorted(Iterable<Note> notes) {
    final List<Note> list = notes.toList();
    list.sort((Note a, Note b) {
      final int byRecency = b.updatedAt.compareTo(a.updatedAt);
      // Ids break ties so the order does not shuffle between two writes of the
      // same millisecond.
      return byRecency != 0 ? byRecency : b.id.compareTo(a.id);
    });
    return list;
  }

  @override
  void save(List<Note> notes) {
    if (_file.blocked != null) return;
    _file.write(<String, dynamic>{
      'format': _formatTag,
      'version': _formatVersion,
      'notes': notes.map((Note n) => n.toJson()).toList(),
    });
  }

  @override
  Future<void> saveNow(List<Note> notes) => _file.writeNow(<String, dynamic>{
        'format': _formatTag,
        'version': _formatVersion,
        'notes': notes.map((Note n) => n.toJson()).toList(),
      });

  /// Watches for a document written by the other surface. Only the widget
  /// surface uses this; the editor is the writer.
  @override
  void watch(void Function() onChanged) => _file.watch(onChanged);

  /// Lets a restore clear the block, so a hand-chosen backup can replace a
  /// file the app refused to overwrite on its own.
  @override
  void unblock() {
    _file.blocked = null;
  }

  /// Where the rolling backup lives, or null. Checked, not assumed: restore is
  /// offered only when it would actually do something.
  @override
  String? get backupPath {
    final String candidate = AtomicJsonFile.backupPathFor(_file.path);
    return File(candidate).existsSync() ? candidate : null;
  }

  /// Replaces the unreadable file with the rolling backup: the recovery route
  /// asking nothing of the person; null (block stays) when unusable.
  @override
  Future<int?> restoreBackup() async {
    final String? backup = backupPath;
    if (backup == null) return null;

    final NotesLoadResult result = await loadFrom(File(backup));
    switch (result) {
      case NotesLoaded(:final List<Note> notes):
        _file.blocked = null;
        // Copied rather than re-serialised: a normal write would first back up
        // the corrupt file over the only good copy. Both files then hold the
        // recovered version, so the net survives a second incident.
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

  /// Moves the unreadable file aside and lets the app start over. Renames, never
  /// deletes (timestamped); returns where it went, or null when held open.
  @override
  Future<String?> setAsideAndStartFresh() async {
    final File source = File(_file.path);
    if (!source.existsSync()) {
      // Nothing to move. The file has already gone, which is the case the app
      // already treats as a first run, so just unblock.
      _file.blocked = null;
      return null;
    }
    final String stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final String kept = '${_file.path}.broken-$stamp';
    try {
      await source.rename(kept);
    } on FileSystemException {
      return null;
    }
    _file.blocked = null;
    return kept;
  }

  /// Size and last-changed time of a data file, or null. Behind this seam (not a
  /// `File(...)` in the UI); swallows every failure, since this runs on the
  /// screen shown *because* a file could not be read.
  static FileDescription? describeFile(String path) {
    try {
      final File file = File(path);
      if (!file.existsSync()) return null;
      return (
        bytes: file.lengthSync(),
        changed: file.lastModifiedSync(),
      );
    } on FileSystemException {
      return null;
    }
  }

  /// Loads from an arbitrary file, so recovery can be read before it is trusted.
  @override
  Future<NotesLoadResult> loadFrom(File file) async {
    try {
      final String raw = await file.readAsString();
      if (raw.trim().isEmpty) return const NotesLoaded(<Note>[]);
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const NotesLoaded(<Note>[]);
      if (decoded['format'] != _formatTag) return const NotesLoaded(<Note>[]);
      final Object? rawNotes = decoded['notes'];
      if (rawNotes is! List) return const NotesLoaded(<Note>[]);
      final List<Note> notes = <Note>[];
      for (final Object? entry in rawNotes) {
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
      return NotesCorrupt(CorruptDataFileError(file.path, 'unreadable'));
    } on FormatException {
      return NotesCorrupt(CorruptDataFileError(file.path, 'not JSON'));
    }
  }

  @override
  Future<void> flush() => _file.flushPending();
  @override
  Future<void> dispose() => _file.dispose();

  @override
  String get path => _file.path;
}

/// Exports and imports notes as plain text. Deliberately boring (title line,
/// body, dash divider) so a backup stays readable without this app.
class BackupService implements IBackupService {
  const BackupService();

  /// A markdown horizontal rule: the divider a person hand-writing a backup
  /// would most likely use inside a body, so the importer never matches it
  /// exactly — it splits on any line of three-plus dashes and restores verbatim.
  static const String separator =
      '----------------------------------------';

  /// True for a note boundary: an unindented line of three or more dashes,
  /// asterisks or underscores, which is the one thing the exporter never writes
  /// inside a body.
  static bool _isDivider(String line) {
    if (line.startsWith(bodyIndent)) return false;
    final String trimmed = line.trimRight();
    if (trimmed.length < 3) return false;
    for (final int unit in trimmed.codeUnits) {
      if (unit != 0x2D && unit != 0x2A && unit != 0x5F) return false;
    }
    return true;
  }

  /// Exports notes as plain text. Bodies are space-indented (not tabs) so a
  /// body dash-line never looks like a boundary; import strips the indent.
  static const String bodyIndent = '    ';

  @override
  String export(List<Note> notes) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('WinNotes backup')
      ..writeln('Exported: ${DateTime.now().toIso8601String()}')
      ..writeln('Notes: ${notes.length}')
      ..writeln();

    // Written in the order the user sees them, which is already newest first,
    // so an import produces the same list a person was looking at.
    for (final Note note in NotesRepository.sorted(notes)) {
      buffer
        ..writeln(separator)
        ..writeln(note.title.trim())
        ..writeln();
      for (final String line in note.body.split('\n')) {
        // A blank body line is written as a bare indent rather than an empty
        // line, so the reader can tell "blank line in the body" from "blank
        // line that ends the body".
        buffer.writeln(line.isEmpty ? bodyIndent : '$bodyIndent$line');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Writes [notes] to [path] as plain text, atomically. An export is the file
  /// reached for when everything failed, so a truncated one is the worst outcome.
  @override
  Future<String> exportTo(String path, List<Note> notes) async {
    final String text = export(notes);
    await AtomicJsonFile.writeTextAtomically(path, text);
    return text;
  }

  /// Reads a backup from [path], or null. Null, not an exception: the caller
  /// tells the person "that did not work", and an empty file is not a backup.
  @override
  Future<List<Note>?> readFrom(String path) async {
    try {
      final String text = await File(path).readAsString();
      final List<Note> notes = import(text);
      return notes.isEmpty ? null : notes;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Parses the plain-text backup format. Deliberately forgiving (Notepad edits
  /// still count); a title-less block is a note with an empty title.
  @override
  List<Note> import(String text) {
    // Normalised first so a file saved or edited on Windows reads the same as
    // one written anywhere else. Splitting on \r\n alone would leave a stray \r
    // glued to the end of every body line.
    final List<String> lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final List<Note> notes = <Note>[];
    final NoteIdFactory factory = NoteIdFactory();

    int index = 0;
    // Skip the header up to the first divider.
    while (index < lines.length && !_isDivider(lines[index])) {
      index++;
    }

    // Each iteration consumes one divider, title and body, leaving `index` on
    // the next divider or the end — never on spacing, which is what used to
    // mint phantom empty notes.
    while (index < lines.length) {
      while (index < lines.length && _isDivider(lines[index])) {
        index++;
      }

      // A divider with nothing after it is a divider, not a note.
      if (!_hasContent(lines, index)) break;

      // The title is taken verbatim, blanks included: skipping them would eat
      // the one legitimate empty title a block can have.
      final String title = lines[index].trim();
      index++;

      // The exporter writes one blank line between the title and the body.
      // Exactly one, so a hand-written note with a deliberate blank line there
      // is not disturbed.
      if (index < lines.length && lines[index].isEmpty) index++;

      // Only indented lines are body; the blank run before the next divider is
      // exporter spacing, and treating it as content minted a phantom empty
      // note between every pair of real ones.
      final List<String> body = <String>[];
      bool indentStops = false;
      while (index < lines.length && !_isDivider(lines[index])) {
        final String line = lines[index];
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

      final DateTime now = DateTime.now();
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
    for (int i = from; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) return true;
    }
    return false;
  }

  static List<String> _trimTrailingBlanks(List<String> lines) {
    int end = lines.length;
    while (end > 0 && lines[end - 1].trim().isEmpty) {
      end--;
    }
    return lines.sublist(0, end);
  }
}