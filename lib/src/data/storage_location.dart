import 'dart:convert';
import 'dart:io';

import '../core/app_paths.dart';

/// Reads `settings.json` at startup, before anything else exists, to learn where the
/// rest of the files are.
///
/// **Why this is not `SettingsRepository`.** The repository needs a `ShellChannel`,
/// an `AtomicJsonFile`, and a provider container — none of which exist yet at the
/// point the data directory has to be decided. It also does not need to be: this reads
/// exactly one string, defensively, and must never fail in a way that stops the app
/// starting. The trade is that `settings.json` is parsed twice at startup, once here
/// and once by the repository, so the shape of the file has two readers. That is
/// deliberate and the reason is stated: [storageDirectoryKey] is the only key read
/// here, and a test asserts the two agree, so a rename that breaks one breaks the other
/// visibly rather than silently.
///
/// **Never throws.** Every failure — missing file, unreadable directory, invalid JSON,
/// the value not being a usable directory — returns null and the caller uses the
/// default. A person whose preferences file cannot be parsed must still be able to open
/// their notes. `storage_pattern.md` §3.7 makes a failed *notes* read block every
/// write, and this is the opposite case on purpose: losing preferences is a nuisance,
/// losing notes is the thing this app exists to prevent.
class StorageLocation {
  const StorageLocation._();

  /// The key in `settings.json`. Named once so the two readers cannot drift.
  static const String storageDirectoryKey = 'storageDirectory';

  /// The configured directory from `[reportedDirectory]`'s `settings.json`, or null.
  ///
  /// This is the **pointer read** — the one that makes a chosen folder findable in the
  /// first place. See [followPointer] for the second read.
  static String? readPointer(AppPaths paths) =>
      _readKey(File(paths.settingsPointerFile));

  /// The folder the person chose, from wherever the authoritative copy lives.
  ///
  /// Two copies of `settings.json` exist when a folder has been chosen, and the
  /// precedence is deliberate:
  ///
  ///  1. the chosen folder's own copy — it is self-contained, so a chosen folder can
  ///     be moved, backed up or handed to somebody else on its own;
  ///  2. the default folder's copy — the pointer, and the only one present before
  ///     anything has been chosen.
  ///
  /// If they disagree the chosen folder wins, because that is the one the person most
  /// recently used and copying a library around is exactly how they end up disagreeing.
  ///
  /// **A chosen folder that is not reachable is refused here, not later.** An unplugged
  /// drive still has a perfectly well-shaped path, so a shape check alone passes it —
  /// and `main()` creates the data directory before anything else happens, which would
  /// recreate `D:\Notes` as an empty folder on the machine's own disk and write an
  /// empty `notes.json` into it. That is total loss wearing the costume of a successful
  /// launch, and it is the single most damaging thing this feature could do. Falling
  /// back to the default folder is not a compromise: the default folder is where the
  /// notes still are.
  static String? followPointer(AppPaths paths) {
    final pointer = readPointer(paths);

    // No folder chosen: the pointer *is* the answer, and there is no second copy.
    if (pointer == null || pointer.trim().isEmpty) return null;

    // Gone, or never there. Report "no folder chosen" rather than return a path that
    // the caller would then create.
    if (!isReachable(pointer)) return null;

    // The chosen folder's own copy wins, when it has a usable one. This is what makes
    // a chosen folder survive being moved.
    final own = _readKey(File('$pointer\\settings.json'));
    if (own != null && own.trim().isNotEmpty && isReachable(own)) return own;

    return pointer;
  }

  /// The whole answer in one call, which is how `main()` uses it.
  ///
  /// Returns the effective data directory. Never null and never throws: the fallback
  /// is the runner's directory, which is where the notes are when nothing else is
  /// known.
  static String resolveDataDirectory(AppPaths paths) {
    final configured = followPointer(paths);
    return AppPaths.configuredLocation(
      reported: paths.reportedDirectory ?? paths.dataDirectory,
      configured: configured,
    );
  }

  /// Whether a path names a directory that exists and accepts writes.
  ///
  /// Separate from [AppPaths.isUsableDirectory], which asks whether a path is *shaped*
  /// like a directory. This asks whether it is *there*. Both matter, and the second is
  /// the one that prevents data loss: an unplugged drive has a perfectly good shape.
  ///
  /// **Never creates anything.** The caller in `main()` does, and that is the danger —
  /// so this has to be able to answer "no" without having made the answer true first. A
  /// version that created the directory in order to test it would answer "yes" to every
  /// well-shaped path ever pointed at, and turn a missing drive into an empty library
  /// that looks exactly like total loss.
  static bool isReachable(String path) {
    if (!AppPaths.isUsableDirectory(path)) return false;
    try {
      final dir = Directory(path.trim());
      if (!dir.existsSync()) return false;
      // Written and removed rather than merely listed, because "the folder is there"
      // and "the folder accepts writes" are different questions and only the second
      // one is the one that matters. A read-only or full drive is the failure this
      // catches, and it fails here instead of on somebody's first keystroke.
      final probe = File('${dir.path}\\.wn-write-probe')
        ..createSync()
        ..deleteSync();
      return !probe.existsSync();
    } on FileSystemException {
      return false;
    }
  }

  /// Compares two paths for "the same place", tolerating the trailing slash and
  /// letter case that make one folder look like two.
  ///
  /// Case-insensitive because Windows paths are, and a mismatch here would mean
  /// treating `C:\Notes` and `c:\notes\` as two libraries.
  static bool sameDirectory(String a, String b) =>
      normalize(a).compareTo(normalize(b)) == 0;

  static String normalize(String path) {
    var p = path.trim().replaceAll('/', r'\');
    while (p.length > 3 && p.endsWith(r'\')) {
      p = p.substring(0, p.length - 1);
    }
    return p.toLowerCase();
  }

  static String? _readKey(File file) {
    try {
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return null;
      final value = decoded[storageDirectoryKey];
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      // Any failure at all is "no location chosen". See the class doc: losing
      // preferences is recoverable, and refusing to start is not.
      return null;
    }
  }
}