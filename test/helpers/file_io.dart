import 'dart:io';

/// Test-only helpers for two Windows behaviours that are timing, not logic.
///
/// Neither of these is a workaround for a bug in the code under test. Both are
/// the OS declining an operation because another handle is open at that instant,
/// which is a race between a background debounced write and the test's own
/// cleanup or assertion. `docs/storage_pattern.md` §3.5 is the product's answer
/// to the same behaviour at runtime; this is the test's much smaller version.

/// Deletes a directory, retrying while Windows still holds a handle on it.
///
/// Several of these tests deliberately leave a watcher, an exclusive lock, or an
/// in-flight debounced write behind, so whether the last handle is closed by the
/// time the body returns is not a property of the code. Without the retry this
/// failed about one run in three with errno 32.
///
/// Real, not `Future.delayed`: the callers are `tearDown` bodies, several of
/// which are synchronous, and a caller that cannot await should still get the
/// retry rather than a first-attempt failure.
void deleteTempDir(Directory dir) {
  // About five seconds, which is far longer than it ever needs and far shorter
  // than a flake costs. Several of these tests leave a directory watcher, an
  // exclusive lock, or a debounced write holding the file, and how long the
  // last handle survives is not a property of the code under test. A previous
  // budget of one second failed about one run in six - long enough to look like
  // it worked, short enough to keep losing.
  const attempts = 200;
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (!dir.existsSync()) return;
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == attempts - 1) rethrow;
      sleep(const Duration(milliseconds: 25));
    }
  }
}

/// Reads a file, retrying while Windows holds it open for writing.
///
/// The atomic writer opens the notes file to write it, and a test that asserts
/// on the result can catch the file mid-replace. `errno 32` from here says
/// nothing about whether the write succeeded.
String readFileEventually(File file) {
  const attempts = 200;
  Object? last;
  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      return file.readAsStringSync();
    } on FileSystemException catch (e) {
      last = e;
      sleep(const Duration(milliseconds: 25));
    }
  }
  throw StateError('Could not read ${file.path} after retrying: $last');
}

/// Waits until [file] contains [needle], reading with [readFileEventually].
///
/// For assertions about a debounced write. Polling rather than sleeping,
/// because the claim is "this eventually lands", not "this lands within N
/// milliseconds" — and a guessed margin is a flake waiting for a busy machine.
Future<String> waitForContent(
  File file,
  String needle, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  var content = '';
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      content = readFileEventually(file);
      if (content.contains(needle)) return content;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return content;
}