/// The layer rules from `AGENTS.md` §3, as tests.
///
/// These are the guards that would have caught the non-atomic export. They pass
/// today because the violation was fixed, not because the rule is vague — see
/// `docs/storage_pattern.md` §6 for what the export used to do and why a
/// truncated export was the worst available outcome.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

void main() {
  final SourceTree tree = SourceTree();

  group('dart:io is confined to utils/ and data/', () {
    test('no file operation appears in presentation, theme or platform/', () {
      final List<String> violations = findFileOperationsOutsideDataLayer(tree);

      expect(
        violations,
        isEmpty,
        reason: 'dart:io outside utils/ and data/ breaks the layer rule.\n'
            'Writes are the hazard - not atomic, so an interrupted write leaves a '
            'truncated file.\n'
            'Put the operation behind a repository method in data/ instead. '
            'Exceptions need an entry in ALLOWED_FILE_OPERATIONS with the reason.\n\n'
            '${violations.join('\n')}',
      );
    });

    test('the rule actually bites: utils/ and data/ do hold file operations', () {
      // Without this, the guard above would also pass on an empty tree, or if
      // the regex silently stopped matching. A guard that cannot fail is worse
      // than no guard, because it reads as enforcement.
      final bool inDataLayer = RegExp(r'\bFile\s*\(').hasMatch(
        tree.dartFilesUnder('lib/core/utils').values.join('\n') +
            tree.dartFilesUnder('lib/features/notes/data').values.join('\n') +
            tree.dartFilesUnder('lib/features/settings/data').values.join('\n') +
            tree.dartFilesUnder('lib/features/widget/data').values.join('\n'),
      );

      expect(
        inDataLayer,
        isTrue,
        reason: 'utils/ and data/ are supposed to contain the file operations. '
            'If they do not, the scanner is broken, not the code.',
      );
    });

    test('the guard is absolute - there is no allowlist to drift', () {
      // No exceptions mechanism exists, on purpose. If a write genuinely cannot
      // go through data/, the fix is to edit this scanner, which shows up in the
      // diff; a list checked-in elsewhere would be a quiet hole. Asserted so
      // that adding one is a deliberate, visible act.
      final String source = File('${tree.root}/test/architecture/guards.dart')
          .readAsStringSync();

      expect(
        RegExp(r'(allow|except|skip|ignore)list', caseSensitive: false)
            .hasMatch(source),
        isFalse,
        reason: 'Add exceptions to the scanner itself, where the diff shows '
            'them, rather than as a list that can quietly grow.',
      );
    });
  });

  group('the method channel is reached one way', () {
    test('only platform/ constructs a MethodChannel', () {
      final List<String> violations = findChannelsOutsidePlatform(tree);

      expect(
        violations,
        isEmpty,
        reason: 'Method names must live in one file so they can be checked '
            'against the runner. Go through ShellChannel.\n\n'
            '${violations.join('\n')}',
      );
    });

    test('every method called from Dart is handled by the runner', () {
      final Set<String> called = dartMethodNames(tree);
      final Set<String> handled = runnerMethodNames(tree);
      final List<String> missing = called.difference(handled).toList()..sort();

      expect(
        called,
        isNotEmpty,
        reason: 'If this is empty the scanner is broken, not the code.',
      );
      expect(
        missing,
        isEmpty,
        reason: 'A method the runner does not handle is a silent no-op. The '
            'runner answers Success() either way, so the Dart await completes '
            'and nothing happens.\n\n  missing: $missing',
      );
    });

    test('the scan finds methods on both sides, so parity means something', () {
      // The first version of this check matched only `_fire`, which made eleven
      // real methods look dead. Both entry points have to be matched, and this
      // is what stops that mistake coming back.
      final Set<String> called = dartMethodNames(tree);
      final Set<String> handled = runnerMethodNames(tree);

      expect(called.length, greaterThan(15),
          reason: 'Expected well over the 17 _fire methods alone.');
      expect(handled.length, greaterThan(20),
          reason: 'The runner handles more than the number of _fire calls.');
      expect(
        dartMethodNames(SourceTree(tree.root)).length,
        called.length,
        reason: 'Both _fire and _invoke are matched; re-scanning must agree.',
      );
    });
  });
}