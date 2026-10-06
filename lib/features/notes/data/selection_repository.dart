import 'dart:convert';
import 'dart:io';

import '../../../core/utils/atomic_json_file.dart';
import '../domain/repositories.dart';

/// Which note is focused, shared by both surfaces. Its own tiny file: neither
/// surface owns it, so neither carries it as a field.
class SelectionRepository implements ISelectionRepository {
  SelectionRepository(this._file);

  final AtomicJsonFile _file;

  String? _cached;

  @override
  String? get cached => _cached;

  /// Read synchronously at startup so the first widget frame already shows the
  /// right card, rather than flashing the most recent note and then correcting.
  @override
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

  @override
  void setSelection(String? noteId) {
    _cached = noteId;
    _file.write({'noteId': noteId ?? ''});
  }

  @override
  void watch(void Function() onChanged) => _file.watch(onChanged);

  @override
  Future<void> flush() => _file.flushPending();
  @override
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
