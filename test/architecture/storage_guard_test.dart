/// `docs/storage_pattern.md` §3.8 and §3.2, as tests.
///
/// The rules here are about code paths that no Dart test can observe: where the
/// watcher is attached, and whether the export goes through the atomic writer.
/// Both were true only by accident before, and both fail silently — one blocks
/// your backup tool, the other truncates the file you would use to recover.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// Code with line comments stripped, so a rule explained in prose does not read
/// as code that breaks it.
String _code(String source) => source
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final tree = SourceTree();

  group('the watcher watches the directory', () {
    // §3.8. The failure is invisible until it bites: File.watch() on Windows
    // holds a handle on the file itself, which blocks the other isolate's atomic
    // rename, blocks a backup tool, and stops someone copying their own notes
    // out by hand. Nothing throws. The notes just stop syncing between windows,
    // or a manual copy fails with an error nobody can explain.
    late String code;

    setUpAll(() {
      code = _code(tree.read('lib/core/utils/atomic_json_file.dart'));
    });

    test('the subscription is on the parent directory', () {
      expect(
        code,
        contains('parent.watch(recursive: false)'),
        reason: 'A directory watcher takes a shared handle on the folder, which '
            'stops nothing. See docs/storage_pattern.md §3.8.',
      );
    });

    test('nothing watches the file itself', () {
      // The failure is invisible until it bites: File.watch() on Windows holds a
      // handle on the file for the whole session, which blocks the other
      // isolate's atomic rename, blocks a backup tool, and stops someone copying
      // their own notes out by hand. Nothing throws. The notes just stop
      // syncing between the two windows, or a manual copy fails with an error
      // nobody can explain.
      expect(
        RegExp(r'File\([^)]*\)\s*\.watch\(').hasMatch(code),
        isFalse,
        reason: 'the file itself must never be the watch target',
      );
      expect(
        RegExp(r'\bfile\.watch\(').hasMatch(code),
        isFalse,
        reason: 'nor via a local variable holding the File',
      );
    });

    test('the events are filtered down to the one file', () {
      // The other half of the rule. Watching the directory means every write to
      // any file in %APPDATA%\WinNotes arrives here, so without the filter the
      // widget would re-read notes.json - and re-render - every time
      // settings.json changed.
      expect(
        code,
        contains('_normalise(event.path) == target'),
        reason: 'a directory watcher needs a path filter or every file in the '
            'folder wakes this one',
      );
    });

    test('the guard would notice if either half changed', () {
      // Proves the two assertions above are not vacuous, which matters because
      // a rename of the local variable would otherwise turn this file green.
      const wrongWatch = 'await File(target).watch(recursive: false)';
      const rightWatch = 'await parent.watch(recursive: false)';
      const noFilter = 'await parent.watch(recursive: false).listen((_) {})';

      expect(RegExp(r'File\([^)]*\)\s*\.watch\(').hasMatch(wrongWatch), isTrue,
          reason: 'the file form must be caught');
      expect(RegExp(r'File\([^)]*\)\s*\.watch\(').hasMatch(rightWatch), isFalse);
      expect(code, isNot(contains('File(target).watch(')));
      expect(code, contains('parent.watch(recursive: false)'));
      expect(noFilter.contains('_normalise(event.path) == target'), isFalse,
          reason: 'an unfiltered watcher must not satisfy the filter assertion');
    });
  });

  group('the export is atomic', () {
    // §3.2 applied to the export. This is the defect that made this whole
    // exercise worth doing: editor_app.dart used to call
    // File(path).writeAsString from the UI layer, so an interrupted export left
    // a truncated file - and that file is what someone reaches for when
    // everything else has failed.
    late String backupService;

    setUpAll(() {
      backupService = tree.read('lib/features/notes/data/notes_repository.dart');
    });

    test('exportTo goes through the atomic writer', () {
      expect(
        backupService,
        contains('AtomicJsonFile.writeTextAtomically'),
        reason: 'The export must reach disk by rename, not by truncating the '
            'destination first.',
      );
    });

    test('the backup is taken before the replace, not after', () {
      // The ordering is invisible in a diff and catastrophic in reverse: taking
      // the backup afterwards would copy the file just written over the backup,
      // leaving the previous version gone. This is exactly what happened while
      // extracting the helper, so it is asserted rather than trusted.
      final atomic = tree.read('lib/core/utils/atomic_json_file.dart');
      final hookIndex = atomic.indexOf('beforeReplace?.call()');
      final renameIndex = atomic.indexOf('await temp.rename(path)');

      expect(hookIndex, greaterThan(0), reason: 'the hook must still exist');
      expect(renameIndex, greaterThan(0));
      expect(
        hookIndex,
        lessThan(renameIndex),
        reason: 'the previous version has to be captured before the replace, '
            'or the backup becomes a copy of the current file',
      );
    });

    test('the export does not write the destination directly', () {
      final editor = _code(tree.read('lib/features/notes/presentation/screens/editor_app/editor_app.dart'));
      expect(
        editor.contains('.writeAsString'),
        isFalse,
        reason: 'A direct write in the UI is exactly what was removed',
      );
    });
  });

  group('one writer per file, decided by the runner', () {
    // `docs/storage_pattern.md` §3.1 was pinned only by behaviour:
    // `widget_integration_test` proves the widget asks the editor rather than
    // writing. That is worth having, and it is not the same thing - a behaviour test
    // proves the *current* call sites cooperate, and says nothing about a new one
    // added tomorrow in a third file. The rule is about where writes may live at all,
    // which is a source property.
    test('only the two notifiers write notes.json', () {
      final writers = _filesWritingNotes(tree);

      expect(
        writers,
        equals(<String>{
          'lib/features/notes/presentation/providers/notes_controller.dart',
          'lib/features/widget/presentation/providers/widget_controller.dart',
        }),
        reason: 'notes.json has one writer by rule. The editor notifier is it; the\n'
            'widget notifier may write *only* when the runner has said no editor is\n'
            'running, which the next test checks.\n\n'
            '  files that write it: ${(writers.toList()..sort()).join(', ')}',
      );
    });

    test('every widget-side write asks the runner first', () {
      // The dangerous half. The widget surface may write notes.json when the editor
      // is closed, and must not when it is open: the editor holds keystrokes in
      // memory for a quarter of a second before they reach disk, so a toggle written
      // from here inside that window overwrites them and silently loses whatever was
      // typed. The runner is asked who owns the file, and the answer decides.
      final source = tree.read('lib/features/widget/presentation/providers/widget_controller.dart');
      final unguarded = _methodNamesWritingNotesWithoutAsking(source);

      expect(
        unguarded,
        isEmpty,
        reason: 'A method that writes notes.json without asking\n'
            '`_shell.isEditorRunning()` first puts two writers on one file. That is\n'
            'the exact thing §3.1 exists to prevent, and it loses keystrokes rather\n'
            'than throwing:\n\n'
            '  ${unguarded.join('\n  ')}',
      );
    });

    test('the editor notifier is the writer and does not ask itself', () {
      // Asserted because it is the asymmetry that makes the rule work: the editor
      // writes unconditionally, the widget asks. A future change that made the
      // editor ask would mean a hotkey race on startup; one that made the widget
      // write unconditionally would mean a lost-keystroke race on every toggle.
      final source = tree.read('lib/features/notes/presentation/providers/notes_controller.dart');

      expect(
        source.contains('isEditorRunning'),
        isFalse,
        reason: 'The editor owns notes.json. Asking whether an editor is running '
            'would be asking itself, and the answer would be racy on startup.',
      );
      expect(
        RegExp(r'_repository\.save\(').allMatches(source).length,
        greaterThan(0),
        reason: 'precondition: the editor really does write. If this is zero the '
            'rule above is passing because nothing writes at all.',
      );
    });
  });
}

/// Files under `lib/` that contain a write to the notes repository.
Set<String> _filesWritingNotes(SourceTree tree) {
  final out = <String>{};
  // Matched on the *argument*, not the receiver. The two notifiers name their
  // repositories differently - `_repository` and `_notesRepo` - so a receiver-name
  // heuristic finds one and misses the other, which is how the first version of this
  // check reported a single writer. The argument is the reliable signal: a notes write
  // passes notes, and the settings and widget-state writes pass `next` and
  // `state.requireValue.window`.
  final save = RegExp(r'\.save\([^)]*\bnotes\b', caseSensitive: false);

  for (final entry in tree.dartFilesUnderRelative('lib').entries) {
    if (entry.key.endsWith('notes_repository.dart')) continue; // the repository
    if (save.hasMatch(entry.value.join('\n'))) out.add(entry.key);
  }
  return out;
}

/// Method names in [source] that write notes without asking the runner.
Set<String> _methodNamesWritingNotesWithoutAsking(String source) {
  final out = <String>{};
  final lines = source.split('\n');

  // Same signal as above: the argument, not the receiver.
  final save = RegExp(r'\.save\([^)]*\bnotes\b', caseSensitive: false);
  final asks = RegExp(r'isEditorRunning');

  for (var i = 0; i < lines.length; i++) {
    if (!save.hasMatch(lines[i])) continue;

    // Walk back to the enclosing method signature: the first line above that opens a
    // member at two-space indent and ends with `{` or `async {`.
    var start = i;
    while (start >= 0 &&
        !RegExp(r'^  [A-Za-z_].*\{\s*$').hasMatch(lines[start])) {
      start--;
    }
    if (start < 0) continue;

    // And forward to its close, at two-space indent.
    var end = i;
    while (end < lines.length && lines[end] != '  }') {
      end++;
    }

    final body = lines.sublist(start, end + 1).join('\n');
    if (!asks.hasMatch(body)) {
      final name = RegExp(r'^  [\w<>?, ]*?(\w+)\s*\(')
          .firstMatch(lines[start])
          ?.group(1);
      out.add('${name ?? 'line ${start + 1}'} (line ${i + 1})');
    }
  }
  return out;
}
