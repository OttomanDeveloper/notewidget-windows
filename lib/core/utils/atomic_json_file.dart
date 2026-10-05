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
    this.transient = false,
  });

  final String path;

  /// Human-readable explanation, shown to the person who has to deal with it.
  final String reason;
  final Object? underlying;

  /// Whether the file might be fine in a moment.
  ///
  /// The distinction that matters, and it is not a cosmetic one. A file that
  /// opened and then failed to parse is damaged, and no amount of waiting will
  /// change that. A file that could not be *opened* is very likely being held by
  /// antivirus, Search Indexer or a backup tool at that instant, and it is
  /// perfectly intact underneath - which means saying "your notes file is
  /// broken" about it is both alarming and wrong, and offering to start fresh
  /// would invite someone to rename a healthy file.
  ///
  /// Set only after the read ladder has already been walked, so this means
  /// "still held after retrying", not "held once".
  final bool transient;

  @override
  String toString() =>
      'CorruptDataFile($path: $reason${transient ? ', transient' : ''})';
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

  /// Backoff for a write that could not land.
  ///
  /// Replacing a file on Windows fails outright whenever something else holds
  /// the destination open, and on a live desktop that is routinely Search
  /// Indexer, antivirus or a backup tool. It clears in milliseconds. Retrying is
  /// the difference between a slightly late write and a lost note, so a failed
  /// write keeps its payload and walks up this ladder.
  ///
  /// Bounded, because a genuinely unwritable destination - a full disk, a
  /// read-only folder - would otherwise retry for the rest of the session.
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

  /// The content this isolate last wrote, or last read.
  ///
  /// Used to ignore the file-watcher event that our own write causes, which
  /// would otherwise bounce back in and re-parse on every keystroke.
  String? _lastKnown;

  /// Backoff for a read that could not open the file.
  ///
  /// The write ladder's twin, and it was missing for a long time: writes retry
  /// because antivirus holds the destination, but reads did not, so the same
  /// antivirus that made a write late could make a *startup* fail outright. A
  /// file that cannot be opened is nearly always held rather than damaged, so the
  /// ladder walks about two and a half seconds before giving up - long enough for
  /// a real-time scan, and paid for only when something is genuinely in the way.
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
        // Having walked the whole ladder and still been unable to open it, this
        // is very likely a lock rather than damage. The distinction decides
        // whether the app suggests starting fresh, which would be the wrong
        // advice for an intact file.
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

  /// Set when the file could not be read. While this is non-null every write
  /// is a no-op, which is what stops the app from "recovering" by replacing a
  /// file nobody has read yet.
  ///
  /// Only a failed *read* sets this. A write that could not land does not: the
  /// notes are perfectly readable, and blocking on a transient write failure
  /// would be both a lie to the user and a way to lose the next edit.
  CorruptDataFile? blocked;

  void _scheduleWrite() {
    // Two edges, deliberately not resettable by each other.
    //
    // The debounce timer slides with every keystroke. The ceiling timer does
    // not: resetting it on each write is what turns it into a second debounce
    // with a longer delay, and continuous typing would then never write at all.
    // It is set only when nothing is pending.
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
      // A write that could not land is not unreadable data.
      //
      // Putting the payload back is the important part: it means the value on
      // screen is still the value queued for disk, so the next write carries it
      // to disk rather than the retry finding nothing to do. `_pending ??=`
      // because a keystroke may have arrived while this write was in flight, and
      // that newer value is the one that should win.
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
    // Order matters and is easy to get wrong: the previous version is captured
    // *before* the replace. Taking it afterwards would copy the file we just
    // wrote over the backup, leaving the backup a duplicate of the current
    // content and the previous version gone for good - which is the one thing
    // the backup exists to prevent.
    await writeTextAtomically(
      path,
      contents,
      beforeReplace: () => _keepPreviousVersion(contents),
    );
  }

  /// Replaces [path] with [contents], or not at all.
  ///
  /// The whole document goes to a sibling temp file and is then renamed over the
  /// target, so a reader sees either the old file or the new one and never a
  /// partial write. A torn write is what turns a recoverable problem into lost
  /// notes, which is why this is not an optimisation.
  ///
  /// Static, and public, because the plain-text export needs the same guarantee
  /// and it is not JSON: an export is the file someone reaches for when
  /// everything else has gone wrong, so a half-written one is the worst possible
  /// outcome. Duplicating the temp-and-rename dance at the call site is how the
  /// export ended up writing non-atomically in the first place.
  ///
  /// No `.bak`, deliberately. This is a caller-chosen destination, not a file
  /// the app rewrites constantly, so a rolling previous version beside it would
  /// be noise the user did not ask for. [AtomicJsonFile] takes one because it
  /// replaces the same file over and over - and takes it before the replace,
  /// which is why this takes a [beforeReplace] hook rather than doing it here.
  ///
  /// The rename is retried because MoveFileEx fails outright if anything else
  /// happens to hold the destination open, and on Windows that is routinely
  /// Search Indexer, antivirus, or a backup tool.
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
  ///
  /// This is the recovery route for a file that has been damaged *from outside*,
  /// and it is the only one that needs nothing from the user first. Because
  /// writes are atomic, WinNotes can never produce a file it cannot read - so
  /// corruption is always something else: a hand-edit, a syncing tool writing
  /// two copies at once, a disk that dropped a sector. In every one of those
  /// cases the thing that saves the notes is the last state this app itself put
  /// on disk, which is exactly what this copies.
  ///
  /// It runs before every atomic replace, so the backup is one write behind. That
  /// costs at most the debounce window of typing - a fraction of a second - and
  /// buys back everything before that.
  ///
  /// Failures here are swallowed deliberately. A backup that could not be taken
  /// is a reason to lose the safety net, not a reason to lose the edit that was
  /// being written; refusing the write would turn a housekeeping problem into
  /// lost notes.
  Future<void> _keepPreviousVersion(String contents) async {
    try {
      final current = File(path);
      if (!await current.exists()) return;
      // Compared against what is about to replace it, not against what this
      // isolate last wrote. The file on disk is the *previous* version by
      // definition at this point, and that is the thing worth keeping - so the
      // check is only here to avoid copying a file over itself when a write
      // happens to carry no change.
      if (await current.readAsString() == contents) return;
      await current.copy(backupPathFor(path));
    } on FileSystemException {
      // Held by a scanner, or no room on the disk. Carry on with the write.
    }
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