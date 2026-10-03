import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Raised when a data file exists but cannot be understood.
///
/// The app refuses to start in this state rather than replacing the file with
/// an empty one. Overwriting notes that were never read is the single failure
/// this project will not risk, so this exception is load-bearing: every write
/// path checks for it and refuses.
class CorruptDataFile implements Exception {
  CorruptDataFile({
    required this.path,
    required this.reason,
    this.underlying,
  });

  final String path;

  /// Human-readable explanation, shown to the person who has to deal with it.
  final String reason;
  final Object? underlying;

  @override
  String toString() => 'CorruptDataFile($path: $reason)';
}

/// A JSON file on disk that both surfaces can share.
///
/// Two things make this more than a `File` wrapper:
///
/// * **Writes are atomic.** The whole file is written to a sibling temp file
///   and then moved over the target, so a kill mid-write can never leave half
///   a document behind. A torn write is what turns a recoverable problem into
///   lost notes.
/// * **Writes are coalesced.** Typing produces an edit per character; without
///   a debounce that is one atomic rewrite per keystroke. The debounce has a
///   ceiling as well as a trailing edge, so a long typing burst still lands on
///   disk while it is happening rather than only once it stops.
///
/// Because each Flutter surface is its own isolate, this class is also how
/// state crosses between them: whichever side owns a file writes it, and the
/// other side picks the change up through [watch].
class AtomicJsonFile {
  AtomicJsonFile(this.path, {this.debounce = const Duration(milliseconds: 250)});

  final String path;
  final Duration debounce;

  /// Longest a change may sit unwritten while typing continues.
  ///
  /// Without this ceiling, someone typing a long sentence continuously would
  /// never write anything at all, which is the exact scenario the "killed
  /// mid-sentence loses nothing" promise is about.
  static const Duration _maxWriteDelay = Duration(milliseconds: 1500);

  Timer? _debounceTimer;
  Timer? _maxTimer;
  String? _pending;
  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _watchDebounce;

  /// The content this isolate last wrote, or last read.
  ///
  /// Used to ignore the file-watcher event that our own write causes, which
  /// would otherwise bounce back in and re-parse on every keystroke.
  String? _lastKnown;

  /// Reads and decodes the file. A missing file is an empty document, not an
  /// error: this is a first run.
  Future<Map<String, dynamic>> read() async {
    final file = File(path);
    if (!await file.exists()) {
      _lastKnown = null;
      return const {};
    }
    final String raw;
    try {
      raw = await file.readAsString();
    } on FileSystemException catch (error) {
      throw CorruptDataFile(
        path: path,
        reason: 'The file could not be read (${error.osError?.message ?? 'unknown error'}).',
        underlying: error,
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

  /// Set when the file could not be read. While this is non-null every write
  /// is a no-op, which is what stops the app from "recovering" by replacing a
  /// file nobody has read yet.
  CorruptDataFile? blocked;

  void _scheduleWrite() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _maxTimer?.cancel();
      unawaited(_flush());
    });
    _maxTimer ??= Timer(_maxWriteDelay, () {
      _debounceTimer?.cancel();
      unawaited(_flush());
    });
  }

  void _cancelTimers() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _maxTimer?.cancel();
    _maxTimer = null;
  }

  Future<void> _flush() async {
    _cancelTimers();
    final payload = _pending;
    _pending = null;
    if (payload == null) return;
    try {
      await _writeAtomically(payload);
      _lastKnown = payload;
    } on FileSystemException catch (error) {
      // A failed write must be visible, not silently swallowed: the notes on
      // screen would otherwise disagree with the notes on disk.
      blocked = CorruptDataFile(
        path: path,
        reason: 'The file could not be written (${error.osError?.message ?? 'unknown error'}).',
        underlying: error,
      );
    }
  }

  Future<void> _writeAtomically(String contents) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(contents, flush: true);

    // rename replaces the destination on Windows, so a reader sees either the
    // old file or the new one and never a partial write.
    //
    // Retried, because MoveFileEx fails outright if anything else happens to
    // hold the destination open, and on Windows that is routinely Search
    // Indexer, antivirus, or a backup tool. Retrying a few times turns a lost
    // write into a slightly delayed one.
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
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
      'Could not replace $path after 5 attempts: $lastError',
      path,
    );
  }

  /// Watches for changes made by the other surface.
  ///
  /// [onChanged] is only called when the content actually differs from what
  /// this isolate already has, so the echo of our own write is filtered out.
  void watch(void Function() onChanged) {
    if (_watchSubscription != null) return;
    try {
      final target = _normalise(path);
      final parent = File(target).parent;
      // The directory has to exist before a watcher will see anything, and a
      // first run has no file yet to watch.
      parent.createSync(recursive: true);

      // Watching the DIRECTORY, not the file.
      //
      // File.watch() on Windows keeps a handle open on the file itself, which
      // blocks anyone else from replacing or deleting it: the other isolate's
      // atomic rename fails, a backup tool fails, and a person trying to back
      // notes up by hand gets an error. The promise that the notes file can be
      // read and handled without this app in the way depends on not holding it.
      // A directory watcher takes a shared handle on the folder, which stops
      // nothing.
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

  /// Reads the file, retrying once through a transient sharing violation.
  ///
  /// Replacing a file on Windows opens the destination for a moment, so a read
  /// that lands in that window fails with ERROR_SHARING_VIOLATION rather than
  /// returning anything. Without the retry, a change notification that arrives
  /// at exactly the wrong millisecond is simply lost, and the other surface
  /// stops updating until the next edit.
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

  Future<void> dispose() async {
    _cancelTimers();
    _watchDebounce?.cancel();
    await _watchSubscription?.cancel();
    _watchSubscription = null;
  }
}