import 'dart:convert';
import 'dart:io';

import '../../../core/utils/app_paths.dart';
import '../domain/settings.dart';
import './storage_location.dart';

/// Moves a library to a chosen folder by copying, never moving or overwriting.
/// Flush first; settings goes to both places (§3.0a). Outcomes are spelled out
/// (top level: Dart forbids enums in classes) so callers report them plainly.
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

  /// Adopted: the app will read a library already in that folder. Nothing was
  /// written there and nothing was deleted from anywhere.
  adopted,

  /// There are no notes in that folder to adopt. Refused rather than created - see
  /// [StorageTransfer.inspectExistingLibrary].
  nothingToAdopt,

  /// Writing failed part way. Whatever was written is left in place; the source is
  /// untouched either way, so nothing is lost and the next attempt can see what is
  /// there.
  failed,
}

class StorageTransfer {
  const StorageTransfer._();

    /// Library files in copy order. Notes first: if it cannot be copied, nothing
    /// else is written, and retrying later is safe since nothing is deleted.
  static const List<String> fileNames = <String>[
    'notes.json',
    'widget_state.json',
    'selection.json',
    'settings.json',
  ];

  /// Points the app at a library **already** in [target], copying nothing - the
  /// mirror of [copyLibrary], which refuses a folder that has notes. Nothing is
  /// written or deleted, so it is always reversible. See `storage_pattern.md` §3.0c.
  static StorageTransferOutcome inspectExistingLibrary(String target) {
    final String trimmed = target.trim();
    if (!AppPaths.isUsableDirectory(trimmed)) {
      return StorageTransferOutcome.notUsable;
    }
    // Absent or empty is refused rather than created. A folder with no notes is
    // not a library, and quietly writing one into somebody's folder is exactly
    // the overwrite this whole path exists to prevent.
    final File notes = File(_join(trimmed, 'notes.json'));
    if (!notes.existsSync() || notes.lengthSync() == 0) {
      return StorageTransferOutcome.nothingToAdopt;
    }
    return StorageTransferOutcome.adopted;
  }

    /// Copies the library. The source settings file is not rewritten: only the
    /// caller knows whether the app is restarting, and a moved pointer plus a
    /// half-finished transfer would strand the app.
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
    final File destinationNotes = File(to.notesFile);
    if (destinationNotes.existsSync() &&
        destinationNotes.lengthSync() > 0 &&
        !await _isEmptyDocument(destinationNotes)) {
      return StorageTransferOutcome.destinationNotEmpty;
    }

    // Flush every source file first. A write still sitting in the debounce window is
    // a keystroke that would be copied as it was before the last few characters.
    for (final String name in fileNames) {
      final File source = File(_join(from.dataDirectory, name));
      if (!source.existsSync()) continue;
      await _copyReplacing(source, File(_join(to.dataDirectory, name)));
    }

      // Destination carries the new location (self-contained); same indent keeps the
      // copies byte-comparable. Written directly: no repo exists there yet to debounce.
    File(_join(to.dataDirectory, 'settings.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );

    return StorageTransferOutcome.done;
  }

    /// Empty means no library, read not sized: an empty open-close cycle must not
    /// make a folder unusable. The `RegExp` is a `static final` field (§7.1).
  static final RegExp notesArray =
      RegExp(r'"notes"\s*:\s*\[([^\]]*)\]', dotAll: true);

  static Future<bool> _isEmptyDocument(File file) async {
    try {
      final String text = file.readAsStringSync().trim();
      if (text.isEmpty) return true;
      final RegExpMatch? notes = notesArray.firstMatch(text);
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
    final File temporary = File('${to.path}.copying');
    if (temporary.existsSync()) temporary.deleteSync();
    await from.copy(temporary.path);
    if (to.existsSync()) to.deleteSync();
    await temporary.rename(to.path);
  }

  static String _join(String directory, String name) => '$directory\\$name';
}
