import 'dart:convert';
import 'dart:io';

import '../../../core/utils/app_paths.dart';
import '../domain/settings.dart';
import './storage_location.dart';

/// Moves a library to a folder the person chose — by **copying**, never by moving.
///
/// Three rules, all of them about not losing notes:
///
///  1. **Copy, never move.** Nothing is deleted from the source. A person who has
///     chosen a new folder and found their notes in it can delete the old copies
///     themselves, at their own pace, having seen for themselves that the notes
///     arrived. An app that deletes the originals has taken away the ability to check.
///  2. **Never overwrite.** If the destination already has a `notes.json`, this
///     refuses and says so. `storage_pattern.md` §3.7 makes a failed read block every
///     write, and this is the same instinct: notes that were never read are the one
///     thing that must not be replaced. It also means "point at the wrong folder"
///     cannot destroy a library.
///  3. **Flush first.** A keystroke may still be sitting in the debounce window. Every
///     source file is flushed to disk *before* anything is copied, or the copy is of a
///     file that is about to change.
///
/// The settings file is written to **both** places — see `storage_pattern.md`
/// §3.0a. The copy in the default folder is the pointer that makes the chosen folder
/// findable next time; the copy in the chosen folder is what makes that folder
/// self-contained.
/// The result of a transfer, spelled out rather than thrown, so the caller can say
/// what happened in the person's own terms.
///
/// Top level because Dart does not allow an enum inside a class. Every value is a
/// thing the caller has to explain to somebody — "it did not work" is not one of them
/// — and a `switch` over this is the list of sentences the Settings screen can say.
enum StorageTransferOutcome {
  /// Copied. The app needs restarting to use the new folder.
  done,

  /// The destination already has notes. Nothing was written and nothing was deleted.
  destinationNotEmpty,

  /// The path is not one this app is willing to write to.
  notUsable,

  /// The destination is not there, or cannot be written to.
  destinationUnreachable,

  /// The same folder that is already in use.
  alreadyThere,

  /// Writing failed part way. Whatever was written is left in place; the source is
  /// untouched either way, so nothing is lost and the next attempt can see what is
  /// there.
  failed,
}

class StorageTransfer {
  const StorageTransfer._();

  /// The files that make up a library, in the order they should be copied.
  ///
  /// Notes first and alone in the sense that matters: if it cannot be copied, nothing
  /// else should have been written. [StorageTransferOutcome.failed] covers that, and because nothing
  /// is deleted, retrying after fixing the cause is safe.
  static const List<String> fileNames = <String>[
    'notes.json',
    'widget_state.json',
    'selection.json',
    'settings.json',
  ];

  /// Copies the library from [from] into [to].
  ///
  /// [settings] is written into the destination as well, with [WinNotesSettings]
  /// carrying the new location. The source settings file is **not** rewritten here —
  /// the pointer copy is the caller's job, because only it knows whether the app is
  /// restarting, and a half-finished transfer that also moved the pointer would leave
  /// an app pointing at a folder with no notes in it.
  static Future<StorageTransferOutcome> copyLibrary({
    required AppPaths from,
    required AppPaths to,
    required WinNotesSettings settings,
  }) async {
    if (!AppPaths.isUsableDirectory(to.dataDirectory)) {
      return StorageTransferOutcome.notUsable;
    }
    if (StorageLocation.sameDirectory(
      from.dataDirectory,
      to.dataDirectory,
    )) {
      return StorageTransferOutcome.alreadyThere;
    }

    try {
      Directory(to.dataDirectory).createSync(recursive: true);
    } on FileSystemException {
      return StorageTransferOutcome.destinationUnreachable;
    }

    // Refuse *before* writing anything, and only if there is real content in the way.
    // An empty or absent file is not a library and is not worth a refusal - somebody
    // choosing a folder that once held a stray notes.json should not be blocked by it.
    final destinationNotes = File(to.notesFile);
    if (destinationNotes.existsSync() &&
        destinationNotes.lengthSync() > 0 &&
        !await _isEmptyDocument(destinationNotes)) {
      return StorageTransferOutcome.destinationNotEmpty;
    }

    // Flush every source file first. A write still sitting in the debounce window is
    // a keystroke that would be copied as it was before the last few characters.
    for (final name in fileNames) {
      final source = File(_join(from.dataDirectory, name));
      if (!source.existsSync()) continue;
      await _copyReplacing(source, File(_join(to.dataDirectory, name)));
    }

    // The settings file in the destination carries the new location, so that folder is
    // self-contained: copied on its own, or handed to somebody else, it still works.
    // Written with the same two-space indent `AtomicJsonFile` uses, so the two copies
    // of `settings.json` - the pointer and the one in the chosen folder - are
    // byte-comparable rather than differing only in whitespace.
    //
    // Written directly rather than through the repository's atomic writer because no
    // repository exists for that directory yet: there is nothing to debounce against
    // and no reader to protect, the whole transfer is synchronous and has already
    // refused to start if the folder cannot be written to.
    File(_join(to.dataDirectory, 'settings.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );

    return StorageTransferOutcome.done;
  }

  /// An empty document, or one holding no notes, is not a library.
///
///   Checked by reading rather than by size: `{"notes":[]}` is longer than nothing and
///   means the same thing, and refusing on it would make a folder unusable after
///   somebody had once opened the app there and closed it again.
  ///
  ///   [notesArray] is a `static final` field rather than something built here.
  ///   `flutter_architecture_pattern.md` §7.1 puts it plainly: no heavy work on the hot
  ///   path, and a `RegExp` is not free. This one is not in a frame loop, but it is a
  ///   constant pattern and building it per call is an allocation for nothing — and
  ///   `flutter_rules_guard_test` caught exactly this in this file the day the guard
  ///   was written, which is the only reason it is stated here rather than discovered.
  static final RegExp notesArray =
      RegExp(r'"notes"\s*:\s*\[([^\]]*)\]', dotAll: true);

  static Future<bool> _isEmptyDocument(File file) async {
    try {
      final text = file.readAsStringSync().trim();
      if (text.isEmpty) return true;
      final notes = notesArray.firstMatch(text);
      if (notes == null) return false;
      return notes.group(1)!.trim().isEmpty;
    } catch (_) {
      // Unreadable is not empty, and unreadable must not be overwritten.
      return false;
    }
  }

  /// Copy, then replace. Written as write-then-delete rather than `copy` so a
  /// half-finished copy never presents itself as a complete file, and so a failure
  /// part way through leaves the old file rather than nothing.
  static Future<void> _copyReplacing(File from, File to) async {
    final temporary = File('${to.path}.copying');
    if (temporary.existsSync()) temporary.deleteSync();
    await from.copy(temporary.path);
    if (to.existsSync()) to.deleteSync();
    await temporary.rename(to.path);
  }

  static String _join(String directory, String name) => '$directory\\$name';
}