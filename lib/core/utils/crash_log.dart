import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;

/// Appends uncaught errors to a file, because a release build has nowhere else
/// to put them. `docs/storage_pattern.md` §3.13a has the reasoning.
class CrashLog {
  CrashLog(this.path);

  final String path;

  /// Rotate above this: a crash loop must not fill a disk.
  static const int maxBytes = 256 * 1024;

  /// The previous file's suffix, matching `notes.json.bak`.
  static const String previousSuffix = '.1';

  /// Appends one entry. Never throws: a handler that raises while reporting a
  /// crash replaces a useful stack trace with a useless one.
  void record(Object error, StackTrace stack, {String? source}) {
    try {
      _rotateIfOversized();
      final Map<String, Object?> entry = <String, Object?>{
        'at': DateTime.now().toUtc().toIso8601String(),
        'source': source ?? 'dart',
        'error': error.toString(),
        'stack': stack.toString(),
      }..addAll(_context());
      File(path).writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert(entry)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // Disk full, read-only profile, no permission. Nothing useful to do.
    }
  }

  /// Sizes rather than contents - see §3.13a. Enough to tell "the notes failed
  /// to parse" from "there were no notes", and safe to paste into an issue.
  Map<String, Object?> _context() {
    final Map<String, Object?> context = <String, Object?>{};
    try {
      context['isolate'] = Isolate.current.debugName;
      context['pid'] = pid;
      context['notesBytes'] = _sizeOf(_notesPath);
    } on Object {
      // Diagnostics must not become a second failure.
    }
    return context;
  }

  /// Derived rather than passed in: one less thing for a caller to get wrong,
  /// and the log has to work before anything else has been resolved.
  late final String _notesPath = _directoryOf(path) + r'\notes.json';

  static String _directoryOf(String file) {
    final int cut = file.lastIndexOf(r'\');
    return cut < 0 ? '.' : file.substring(0, cut);
  }

  int? _sizeOf(String other) {
    final File f = File(other);
    return f.existsSync() ? f.lengthSync() : null;
  }

  /// Renames rather than deletes, and only when there is something to keep: the
  /// incident that filled the file is the one most worth reading.
  void _rotateIfOversized() {
    final File f = File(path);
    if (!f.existsSync() || f.lengthSync() < maxBytes) return;
    final File previous = File('$path$previousSuffix');
    if (previous.existsSync()) previous.deleteSync();
    f.renameSync(previous.path);
  }
}

/// Installs the handlers on both surfaces. Called once per isolate, before
/// anything else can throw. Returns the log so a caller keeps one instance.
CrashLog installCrashHandlers(CrashLog log) {
  final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    log.record(
      details.exception,
      details.stack ?? StackTrace.current,
      source: 'flutter',
    );
    previous?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    log.record(error, stack, source: 'isolate');
    // Returning true marks it handled: without this the process keeps running in
    // a state nobody asked for, and the file is the only evidence.
    return true;
  };

  return log;
}
