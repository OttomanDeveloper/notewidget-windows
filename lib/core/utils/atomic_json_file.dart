import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Raised when a data file exists but cannot be understood. Refuses to start
/// rather than overwrite unread notes; every write path checks for it.
class CorruptDataFile implements Exception {
  CorruptDataFile({
    required this.path,
    required this.reason,
    this.underlying,
    this.transient = false,
  });

  final String path;

  /// Human-readable explanation, shown to the person who has to deal with it.
  final String reason;
  final Object? underlying;

  /// Whether the file might be fine in a moment: unopenable means held
  /// (transient); opened-but-unparsed means damaged.
  final bool transient;

  @override
  String toString() =>
      'CorruptDataFile($path: $reason${transient ? ', transient' : ''})';
}

/// A JSON file on disk that both surfaces can share. Writes are atomic (temp
/// file + rename) and coalesced (debounce with ceiling); state crosses isolates
/// through [watch].
class AtomicJsonFile {
  AtomicJsonFile(this.path, {this.debounce = const Duration(milliseconds: 250)});

  final String path;
  final Duration debounce;

  /// Longest a change may sit unwritten while typing continues. Without it,
  /// continuous typing would never write anything at all.
  static const Duration _maxWriteDelay = Duration(milliseconds: 1500);

  /// Backoff for a write that could not land. A held destination clears in
  /// milliseconds, so the payload is kept and retried up this bounded ladder.
  static const List<Duration> _writeRetryLadder = <Duration>[
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(milliseconds: 1000),
    Duration(milliseconds: 2000),
  ];

  Timer? _debounceTimer;
  Timer? _maxTimer;
  Timer? _retryTimer;
  String? _pending;
  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _watchDebounce;
  int _writeFailures = 0;

  /// The content this isolate last wrote, or last read. Filters the watcher echo
  /// of our own write, which would otherwise re-parse on every keystroke.
  String? _lastKnown;

  /// Backoff for a read that could not open the file. Unopenable is nearly
  /// always held rather than damaged: walks ~2.5s before giving up.
  static const List<Duration> _readRetryLadder = <Duration>[
    Duration(milliseconds: 40),
    Duration(milliseconds: 80),
    Duration(milliseconds: 160),
    Duration(milliseconds: 320),
    Duration(milliseconds: 640),
    Duration(milliseconds: 1280),
  ];

  /// Reads and decodes the file. A missing file is an empty document, not an
  /// error: this is a first run.
  Future<Map<String, dynamic>> read() async {
    final file = File(path);
    if (!await file.exists()) {
      _lastKnown = null;
      return const {};
    }

    String? raw;
    Object? openError;
    for (var attempt = 0; attempt <= _readRetryLadder.length; attempt++) {
      try {
        raw = await file.readAsString();
        openError = null;
        break;
      } on FileSystemException catch (error) {
        // Deleted or moved between the exists check and here is not a lock, and
        // retrying it would just add two seconds to a first run.
        if (error.osError?.errorCode == 2 || error.osError?.errorCode == 3) {
          openError = null;
          break;
        }
        openError = error;
        if (attempt < _readRetryLadder.length) {
          await Future<void>.delayed(_readRetryLadder[attempt]);
        }
      }
    }

    if (raw == null) {
      throw CorruptDataFile(
        path: path,
        reason: 'Something else is using this file right now, so WinNotes could '
            'not open it'
            '${openError == null ? '' : ' (${(openError as FileSystemException).osError?.message ?? 'unknown error'})'}.',
        underlying: openError,
        // Still held after retrying, hence transient: the app must not
        // suggest starting fresh for an intact file.
        transient: true,
      );
    }

    if (raw.trim().isEmpty) {
      // A zero-length file is a leftover temp from a write that never
      // completed. Treat it as empty rather than refusing to start.
      _lastKnown = raw;
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('The top level of the file is not a JSON object.');
      }
      _lastKnown = raw;
      return decoded;
    } on FormatException catch (error) {
      // No retry. The file opened and its bytes did not parse, which means the
      // content is wrong, and waiting cannot make the content change. Retrying
      // here would only delay telling someone their file needs attention.
      throw CorruptDataFile(
        path: path,
        reason: error.message,
        underlying: error,
      );
    }
  }

  /// Queues a write. Repeated calls within the debounce window replace each
  /// other, so a burst of keystrokes costs one write.
  void write(Map<String, dynamic> value) {
    if (blocked != null) return;
    _pending = const JsonEncoder.withIndent('  ').convert(value);
    _scheduleWrite();
  }

  /// Writes immediately, ignoring the debounce. Called on quit, and after a
  /// restore, where "eventually" is not good enough.
  Future<void> writeNow(Map<String, dynamic> value) async {
    if (blocked != null) return;
    _pending = const JsonEncoder.withIndent('  ').convert(value);
    _cancelTimers();
    await _flush();
  }

  /// Set when the file could not be read. While non-null every write is a
  /// no-op, so the app cannot "recover" by replacing a file nobody has read.
  /// Only a failed read sets this; a failed write does not.
  CorruptDataFile? blocked;

  void _scheduleWrite() {
    // Two edges: the debounce slides with each keystroke, the ceiling does
    // not (set only when nothing is pending). Resetting the ceiling per
    // write would turn it into a second debounce and never write.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _maxTimer?.cancel();
      _maxTimer = null;
      unawaited(_flush());
    });
    _maxTimer ??= Timer(_maxWriteDelay, () {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _maxTimer = null;
      unawaited(_flush());
    });
  }

  void _cancelTimers() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _maxTimer?.cancel();
    _maxTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> _flush() async {
    _cancelTimers();
    final payload = _pending;
    _pending = null;
    if (payload == null) return;
    try {
      await _writeAtomically(payload);
      _writeFailures = 0;
      _lastKnown = payload;
    } on FileSystemException {
      // Re-queue the payload (a newer keystroke wins via `??=`), so the next
      // write carries what is on screen rather than the retry finding nothing.
      _pending ??= payload;
      _writeFailures++;
      if (_writeFailures <= _writeRetryLadder.length) {
        _retryTimer ??= Timer(_writeRetryLadder[_writeFailures - 1], () {
          _retryTimer = null;
          unawaited(_flush());
        });
      }
    }
  }

  Future<void> _writeAtomically(String contents) async {
    // Backup before the replace: afterwards would copy the new file over
    // itself and lose the previous version, the one thing the backup is for.
    await writeTextAtomically(
      path,
      contents,
      beforeReplace: () => _keepPreviousVersion(contents),
    );
  }

  /// Replaces [path] with [contents], or not at all. Temp file + rename, so
  /// readers see old or new, never partial. Public for the export; no `.bak`
  /// here, and retry covers locks.
  static Future<void> writeTextAtomically(
    String path,
    String contents, {
    Future<void> Function()? beforeReplace,
    int attempts = 5,
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(contents, flush: true);

    await beforeReplace?.call();

    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        // rename replaces the destination on Windows.
        await temp.rename(path);
        return;
      } on FileSystemException catch (error) {
        lastError = error;
        await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
      }
    }
    // Temp file deliberately left in place rather than discarded, so a partial
    // write can never be mistaken for real data on the next run.
    throw FileSystemException(
      'Could not replace $path after $attempts attempts: $lastError',
      path,
    );
  }

  /// Where the previous good copy lives, and why it exists.
  static String backupPathFor(String path) => '$path.bak';

  /// Copies the file that is about to be replaced to [backupPathFor].
  /// Recovery for outside damage (own writes are atomic); one write behind,
  /// and failures are swallowed so the edit still lands.
  Future<void> _keepPreviousVersion(String contents) async {
    try {
      final current = File(path);
      if (!await current.exists()) return;
      // Skip no-change writes: compare against the file on disk (the
      // previous version by definition), not what this isolate last wrote.
      if (await current.readAsString() == contents) return;
      await current.copy(backupPathFor(path));
    } on FileSystemException {
      // Held by a scanner, or no room on the disk. Carry on with the write.
    }
  }

  /// Watches for changes made by the other surface.
  /// [onChanged] fires only on real content change, so our own echo is out.
  void watch(void Function() onChanged) {
    if (_watchSubscription != null) return;
    try {
      final target = _normalise(path);
      final parent = File(target).parent;
      // The directory has to exist before a watcher will see anything, and a
      // first run has no file yet to watch.
      parent.createSync(recursive: true);

      // Directory, not file: File.watch() holds the file open and blocks
      // the other isolate's rename. A directory handle stops nothing.
      _watchSubscription = parent.watch(recursive: false).where((event) {
        return _normalise(event.path) == target;
      }).listen(
        (_) => _scheduleReload(onChanged),
        onError: (Object _) {
          // Losing the watcher degrades cross-surface updates but must not take
          // the app down; the file itself is untouched.
        },
      );
    } on FileSystemException {
      _watchSubscription = null;
    }
  }

  /// Canonical form for comparing two paths to the same file.
  static String _normalise(String path) {
    var value = path.replaceAll('/', r'\').toLowerCase();
    while (value.length > 3 && value.endsWith('\\')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  void _scheduleReload(void Function() onChanged) {
    _watchDebounce?.cancel();
    // Several filesystem events arrive for one logical write, and reading on
    // each of them means parsing a half-replaced file.
    _watchDebounce = Timer(const Duration(milliseconds: 120), () async {
      final raw = await _readWithRetry();
      if (raw == null) return;
      if (raw == _lastKnown) return;
      _lastKnown = raw;
      onChanged();
    });
  }

  /// Reads the file, retrying through a transient sharing violation.
  /// Replace opens the destination briefly, so a read landing in that window
  /// fails; without the retry the other surface stops updating till next edit.
  Future<String?> _readWithRetry() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await File(path).readAsString();
      } on PathAccessException {
        if (attempt == 2) return null;
        await Future<void>.delayed(Duration(milliseconds: 30 * (attempt + 1)));
      } on FileSystemException {
        // Deleted or moved underneath us. The next event will catch up.
        return null;
      }
    }
    return null;
  }

  /// Pushes anything still queued to disk. Called when quitting.
  Future<void> flushPending() => _flush();

  /// Drops the debounce timers without writing. Used when a surface is going
  /// away and the queued write belongs to state that is being discarded, such
  /// as an intermediate scroll position.
  void cancelPendingWrites() => _cancelTimers();

  /// Flushes anything queued, then releases the watcher. Ordering matters: the
  /// write has to land before the file is closed, or the last edit before a
  /// window closes would be lost.
  Future<void> dispose({bool flush = true}) async {
    if (flush) await _flush();
    _cancelTimers();
    _watchDebounce?.cancel();
    await _watchSubscription?.cancel();
    _watchSubscription = null;
  }
}