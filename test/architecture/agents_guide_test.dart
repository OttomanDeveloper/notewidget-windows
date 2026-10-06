/// `AGENTS.md` has to follow the patterns it states, or it is a document
/// describing a project that does not exist.
///
/// The rules in §0 are enforced by the other twelve guards in this folder. This
/// one is about the guide itself, and it exists because of two specific failures,
/// both of which were caught by a reader rather than by a tool:
///
///  - **`AGENTS.md` claimed 147 architecture tests and 473 in total. It was
///    148 and 481.** Nothing had been written to §0 that day. The numbers were
///    simply left behind by work that added tests, which is what a hand-kept
///    count always does. The count is not re-checked below; it is *removed*, and
///    replaced by the command that prints it. A number nobody can check is a
///    number nobody should trust.
///  - **The §3.1 table listed thirteen guards.** It listed thirteen because
///    thirteen existed, and it would have kept saying thirteen if a fourteenth
///    were added without a line here - which is the failure mode of a table
///    that is maintained by remembering.
///
/// So the checks are: every guard that exists is named in the table, every guard
/// the table names exists, every frozen rule names the thing that enforces it,
/// and no hand-kept test counts survive anywhere in the file.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// The guards this folder is allowed to contain. Listed so the completeness check
/// below reads as a closed set rather than "whatever is on disk today".
const List<String> _guardFiles = <String>[
  'agents_guide_test.dart',
  'changelog_guard_test.dart',
  'dependency_guard_test.dart',
  'docs_test.dart',
  'flutter_rules_guard_test.dart',
  'icon_guard_test.dart',
  'isolate_guard_test.dart',
  'layer_test.dart',
  'no_set_state_test.dart',
  'platform_guard_test.dart',
  'provider_guard_test.dart',
  'storage_guard_test.dart',
  'storage_location_guard_test.dart',
  'widget_guard_test.dart',
];

/// Rule headings in §0, in order. The count is asserted so a rule cannot be
/// added to §0 without saying what enforces it.
final RegExp _frozenRule = RegExp(r'^\s*(\d+)\.\s+\*\*');

void main() {
  final SourceTree tree = SourceTree();
  final String guide = tree.read('AGENTS.md');

  group('AGENTS.md describes the project that exists', () {
    test('every guard in this folder is named in the §3.1 table', () {
      // The direction that catches drift: a new guard that nobody documented is
      // a guard whose rule nobody will read.
      final List<String> missing = <String>[
        for (final String name in _guardFiles)
          // The table writes `no_set_state_test`, not `no_set_state_test.dart`,
          // so the stem is what is matched.
          if (!guide.contains(name.replaceAll('.dart', ''))) name,
      ];

      expect(
        missing,
        isEmpty,
        reason: 'These guards run in CI but AGENTS.md §3.1 does not name them, so '
            'the rule each one enforces has no entry in the table that is supposed '
            'to say what is enforced:\n\n'
            '${missing.map((String m) => '  $m').join('\n')}\n'
            '    Add a row. If the guard does not belong, delete the guard.',
      );
    });

    test('every guard the guide names actually exists', () {
      // The other direction. A table citing a test that was renamed or removed
      // is a table pointing at nothing, and it reads as enforced when it is not.
      final List<String> cited = RegExp(r'\b([a-z_]+_test)\.dart\b')
          .allMatches(guide)
          .map((RegExpMatch m) => '${m.group(1)}.dart')
          .toSet()
          .toList()
        ..sort();
      final List<String> missing = <String>[
        for (final String name in cited)
          if (!_guardFiles.contains(name) &&
              !File('test/$name').existsSync()) name,
      ];

      expect(
        missing,
        isEmpty,
        reason: 'AGENTS.md cites tests that are not in test/. A cited guard that '
            'does not exist is worse than an uncited rule: it looks enforced.\n\n'
            '${missing.map((String m) => '  $m').join('\n')}',
      );
    });

    test('this folder holds exactly the guards the list expects', () {
      // Closes the set. Without it a deleted guard would satisfy both checks
      // above at once - nothing would cite it and nothing would be missing.
      final List<String> onDisk = Directory('test/architecture')
          .listSync()
          .whereType<File>()
          .map((File f) => f.uri.pathSegments.last)
          .where((String n) => n.endsWith('.dart') && !n.startsWith('guards'))
          .toList()
        ..sort();
      final List<String> expected = List<String>.of(_guardFiles)..sort();

      expect(
        onDisk,
        expected,
        reason: 'test/architecture and _guardFiles have drifted apart. A guard '
            'added here but not listed would be caught by the completeness check '
            'above; one removed here but still listed would be caught by the '
            'existence check. This catches both being edited to agree with each '
            'other while the guard itself is gone.',
      );
    });

    test('every frozen rule says what enforces it', () {
      // §0 is the part of the guide a reader trusts most, and the part most
      // likely to be aspirational. A rule with no enforcement named is a rule
      // that is a comment - and this repository's own line is that "a rule with
      // no test name in that table is a comment, not a rule".
      //
      // The block is taken whole and split on the numbered items, because §0's
      // items are numbered list entries rather than headings.
      final RegExpMatch? start = RegExp(r'^## 0\..*$', multiLine: true).firstMatch(guide);
      expect(start, isNotNull, reason: '§0 Frozen Rules should still be there');
      final int from = start!.end;
      final RegExpMatch next = RegExp(r'^## ', multiLine: true).firstMatch(guide.substring(from))!;
      final String block = guide.substring(from, from + next.start);

      final List<String> unenforced = <String>[];
      int numbered = 0;
      for (final String rule in block.split(RegExp(r'(?=^\s*\d+\.\s+\*\*)', multiLine: true))) {
        final RegExpMatch? head = _frozenRule.firstMatch(rule);
        if (head == null) continue;
        numbered++;
        // Enforced if it names a test, a guard, or declares itself
        // documentation-only on purpose. The stem matches, because the guide
        // writes `no_set_state_test` and not `no_set_state_test.dart`.
        final bool enforced = RegExp(r'_test|guards\.dart|`guard`')
                .hasMatch(rule) ||
            RegExp(r'\bnot enforced\b|\bprose only\b', caseSensitive: false)
                .hasMatch(rule);
        if (!enforced) {
          unenforced.add(rule.trim().split('\n').first);
        }
      }

      expect(numbered, greaterThanOrEqualTo(11),
          reason: 'the §0 frozen rules should still be all there');
      expect(
        unenforced,
        isEmpty,
        reason: 'These rules in §0 name nothing that enforces them, so they are '
            'prose. Say which test or guard pins each one, or mark it explicitly '
            'as documentation-only and say why.\n\n'
            '${unenforced.join('\n')}',
      );
    });

    test('the guide states no test count of its own', () {
      // The rule that would have caught "147" and "473". A count in prose is a
      // snapshot with no refresh date; the gate prints the number every run, and
      // that is the copy worth reading.
      final RegExpMatch? stale = RegExp(
        r'\b(\d{2,4})\s+(architecture\s+)?tests\b',
      ).firstMatch(guide);

      expect(
        stale,
        isNull,
        reason: 'AGENTS.md states "${stale?.group(0)}". That number is a '
            'hand-kept snapshot and it was wrong twice before this check '
            'existed. Print it instead: `flutter test --reporter=compact` for '
            'the suite, `flutter test test/architecture` for the guards.',
      );
    });

    test('every script the runbook names exists', () {
      // The runbook is the part a newcomer follows at 2am, so a path that has
      // moved makes it worse than the absence of a runbook.
      final Set<String> cited = RegExp(r'tool[\\/][A-Za-z0-9_./\\-]+\.ps1')
          .allMatches(guide)
          .map((RegExpMatch m) => m.group(0)!.replaceAll('\\', '/'))
          .toSet();
      final List<String> missing = <String>[
        for (final String p in cited)
          if (!File(p).existsSync()) p,
      ];

      expect(cited, isNotEmpty, reason: 'the runbook should name some scripts');
      expect(
        missing,
        isEmpty,
        reason: 'The runbook names scripts that are not there. Someone following '
            'it on a clean checkout gets a command that cannot run:\n\n'
            '${missing.join('\n')}',
      );
    });

    test('the scanners above still bite', () {
      // Every guard in this folder proves its own scanner matches planted text.
      // This one has three scanners of its own, and a regex that quietly stops
      // matching passes all the checks above vacuously.
      expect(
        RegExp(r'tool[\\/][A-Za-z0-9_./\\-]+\.ps1').hasMatch(r'pwsh tool\verify\verify.ps1'),
        isTrue,
      );
      expect(
        RegExp(r'tool[\\/][A-Za-z0-9_./\\-]+\.ps1').hasMatch(r'tool\verify\verify.ps1'),
        isTrue,
      );
      expect(
        RegExp(r'tool[\\/][A-Za-z0-9_./\\-]+\.ps1').hasMatch(r'C:\proj\tool\verify\verify.ps1'),
        isTrue,
      );
      expect(
        RegExp(r'\b(\d{2,4})\s+(architecture\s+)?tests\b')
            .hasMatch('test/architecture/ - 147 tests'),
        isTrue,
      );
      expect(
        RegExp(r'\b(\d{2,4})\s+(architecture\s+)?tests\b')
            .hasMatch('the 473 tests'),
        isTrue,
      );
      expect(
        RegExp(r'\b(\d{2,4})\s+(architecture\s+)?tests\b')
            .hasMatch('the twenty traps'),
        isFalse,
        reason: 'a word is not a number',
      );
    });
  });
}