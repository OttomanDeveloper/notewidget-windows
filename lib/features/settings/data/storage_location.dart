import 'dart:convert';
import 'dart:io';

import '../../../core/utils/app_paths.dart';

/// Reads `settings.json` at startup for one string: where the rest of the files are.
/// Never throws; a bad preferences file must not prevent opening notes.
/// See `docs/storage_pattern.md` §3.0 for the two-copy precedence.
class StorageLocation {
  const StorageLocation._();

  /// The key in `settings.json`. Named once so the two readers cannot drift.
  static const String storageDirectoryKey = 'storageDirectory';

    /// The configured directory: the pointer read making a chosen folder
    /// findable. See [followPointer] for the second read.
  static String? readPointer(AppPaths paths) =>
      _readKey(File(paths.settingsPointerFile));

    /// The chosen folder, from the authoritative copy. Precedence (`§3.0`): the
    /// chosen folder's copy, then the default pointer. Unreachable folders are
    /// refused here - recreating one as empty would be total loss.
  static String? followPointer(AppPaths paths) {
    final String? pointer = readPointer(paths);

    // No folder chosen: the pointer *is* the answer, and there is no second copy.
    if (pointer == null || pointer.trim().isEmpty) return null;

    // Gone, or never there. Report "no folder chosen" rather than return a path that
    // the caller would then create.
    if (!isReachable(pointer)) return null;

    // The chosen folder's own copy wins, when it has a usable one. This is what makes
    // a chosen folder survive being moved.
    final String? own = _readKey(File('$pointer\\settings.json'));
    if (own != null && own.trim().isNotEmpty && isReachable(own)) return own;

    return pointer;
  }

    /// The whole answer in one call, as `main()` uses it. Never null, never
    /// throws: the fallback is the runner's directory.
  static String resolveDataDirectory(AppPaths paths) {
    final String? configured = followPointer(paths);
    return AppPaths.configuredLocation(
      reported: paths.reportedDirectory ?? paths.dataDirectory,
      configured: configured,
    );
  }

    /// Whether a path exists and accepts writes (not merely well-shaped).
    /// Never creates anything: answering "no" must not first make it "yes".
    /// See `docs/storage_pattern.md` §3.0 for why this prevents total loss.
  static bool isReachable(String path) {
    if (!AppPaths.isUsableDirectory(path)) return false;
    try {
      final Directory dir = Directory(path.trim());
      if (!dir.existsSync()) return false;
        // Written then removed: existence and writability differ, and only the
        // second matters. Fails here, not on the first keystroke.
      final File probe = File('${dir.path}\\.wn-write-probe')
        ..createSync()
        ..deleteSync();
      return !probe.existsSync();
    } on FileSystemException {
      return false;
    }
  }

    /// Compares two paths for "the same place": trailing slash and letter case
    /// are tolerated, since Windows paths are case-insensitive.
  static bool sameDirectory(String a, String b) =>
      normalize(a).compareTo(normalize(b)) == 0;

  static String normalize(String path) {
    String p = path.trim().replaceAll('/', r'\');
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