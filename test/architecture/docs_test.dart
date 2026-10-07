/// The pattern docs must agree with the test suite.
///
/// `docs/storage_pattern.md` §8 and `docs/widget_pattern.md` §7 both end with a
/// table naming the tests that pin each rule, on the principle that a rule with
/// no test name in that table is a comment rather than a rule.
///
/// That principle is only worth anything if somebody checks it. A table is text,
/// and text rots: a test gets renamed, the doc keeps the old name, and the table
/// quietly becomes fiction while still looking authoritative. These tests make
/// the roting visible.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// Docs that carry a rule-to-test table, and the heading of that table.
const Map<String, String> _tables = <String, String>{
  'docs/storage_pattern.md': '## 8. Tests',
  'docs/widget_pattern.md': '## 7. Tests',
  'docs/provider_pattern.md': '## 7. Tests',
  'docs/isolate_pattern.md': '## 7. Tests',
  'docs/platform_pattern.md': '## 7. Tests',
};

void main() {
  final SourceTree tree = SourceTree();
  final Set<String> suite = allTestNames(tree);

  group('the pattern docs', () {
    test('the scanner found tests to check against', () {
      expect(
        suite.length,
        greaterThan(150),
        reason: 'If this is small the scanner is broken, and every check below '
            'would pass vacuously.',
      );
    });

    for (final MapEntry<String, String> entry in _tables.entries) {
      final String path = entry.key;
      final String heading = entry.value;

      group(path, () {
        late String markdown;
        late String table;

        setUpAll(() {
          markdown = tree.read(path);
          // The table is everything from its heading to the next `##`, which is
          // where the Guarantees section begins in both docs.
          final int start = markdown.indexOf(heading);
          expect(start, greaterThanOrEqualTo(0),
              reason: '$path has no "$heading" section');
          final String rest = markdown.substring(start + heading.length);
          final int end = rest.indexOf('\n## ');
          table = end < 0 ? rest : rest.substring(0, end);
        });

        test('every rule in section 3 has a row in the table', () {
          final List<String> rules = ruleHeadings(markdown);
          expect(
            rules,
            isNotEmpty,
            reason: '$path documents no numbered rules, so there is nothing to '
                'pin. Either the numbering changed or the rules moved.',
          );

          // Two rules under one number. Added after this happened: adding a rule
          // took `§3.14` while `§3.14` already existed, and every test above
          // still passed - one heading, one row, both claims satisfied, and the
          // Markdown rule silently demoted to a duplicate. `rules` is a list, so
          // the set is what catches it.
          final Set<String> seen = <String>{};
          final List<String> duplicated = rules
              .where((String r) => !seen.add(r))
              .toList();
          expect(
            duplicated,
            isEmpty,
            reason: '$path numbers two different rules the same. A § that names '
                'two things resolves to neither when someone follows a '
                'citation.\n\n  duplicated: $duplicated',
          );

          // Each row cites a § number in its first column. Checked by set, not
          // by counting rows: a count would be satisfied by thirteen rows all
          // pointing at §3.1, which is precisely the rot this is meant to catch.
          // The letter suffix matches [ruleHeadings]: `§3.0a` and `§3.13a` were
          // both invisible here, so those four rows had never been checked for
          // citing a test that exists.
          final Set<String> pinned =
              RegExp(r'^\|\s*(\d+\.\d+[a-z]?)\s*\|', multiLine: true)
                  .allMatches(table)
                  .map((RegExpMatch m) => m.group(1)!)
                  .toSet();

          final List<String> unpinned = rules.where((String r) => !pinned.contains(r)).toList();
          expect(
            unpinned,
            isEmpty,
            reason: '$path has rules with no row in its Tests table. A rule '
                'with no test name is a comment.\n\n  unpinned: $unpinned',
          );

          // And the reverse: a row citing a § that no longer exists is a stale
          // claim of enforcement.
          final List<String> stale =
              pinned.difference(rules.toSet()).where((String r) => r != '—').toList();
          expect(
            stale,
            isEmpty,
            reason: '$path cites rule numbers that do not exist: $stale',
          );
        });

        test('every test name it cites actually exists', () {
          final Set<String> cited = citedTestNames(markdown);
          expect(
            cited,
            isNotEmpty,
            reason: '$path cites no test names, so the table is decoration.',
          );

          final List<String> missing = cited.difference(suite).toList()..sort();
          expect(
            missing,
            isEmpty,
            reason: '$path pins rules with tests that do not exist. Either the '
                'test was renamed or it was deleted, and the doc is now '
                'claiming enforcement it does not have.\n\n  missing: $missing',
          );
        });
      });
    }

    test('AGENTS.md points at docs that exist', () {
      final String agents = tree.read('AGENTS.md');
      // Any path ending in `.md`, at any depth. The character class used to be
      // `[\w_]+`, which cannot match a `/` — so a citation like
      // `docs/testing/README.md` was invisible here rather than checked. Five
      // such paths were added to the docs index before anyone noticed, and the
      // guard was the thing that was supposed to notice.
      final Set<String> referenced = RegExp(r'`([\w./-]+\.md)`')
          .allMatches(agents)
          .map((RegExpMatch m) => m.group(1)!)
          .where((String r) => r.contains('/') || r.endsWith('.md'))
          .toSet();

      final List<String> missing = referenced
          .where((String r) => r != 'PROJECT.md' && !tree.exists(r))
          .toSet()
          .toList();

      expect(
        missing,
        isEmpty,
        reason: 'AGENTS.md is the entry point. A link to a doc that is not there '
            'is worse than no index, because it looks checked.\n\n  $missing',
      );
    });

    test('the AGENTS.md citation check is not vacuous', () {
      // A regex that matches nothing reports a clean index. Fed a citation with
      // a subdirectory in it — the shape five real entries have — it must find
      // it, or the test above is decoration.
      final Iterable<RegExpMatch> cited = RegExp(r'`([\w./-]+\.md)`').allMatches('`docs/testing/x.md`');
      expect(
        cited.map((RegExpMatch m) => m.group(1)).toList(),
        contains('docs/testing/x.md'),
        reason: 'a path with a directory in it is the case the old character '
            'class could not match',
      );
    });

    test('AGENTS.md no longer claims an unenforced rule', () {
      final String agents = tree.read('AGENTS.md');

      // §4 used to record the non-atomic export as a known divergence. It is
      // fixed, so the claim must be gone: a stale divergence is as misleading as
      // a stale citation, because it says "known" and stops anyone looking.
      expect(
        agents.contains('bypasses the atomic writer'),
        isFalse,
        reason: 'The export goes through AtomicJsonFile now. If this is back, '
            'either the fix was reverted or AGENTS.md was not updated with it.',
      );
    });

    test('the storage doc no longer lists outstanding layer violations', () {
      final String doc = tree.read('docs/storage_pattern.md');

      expect(
        findFileOperationsOutsideDataLayer(tree),
        isEmpty,
        reason: 'precondition: the layer guard is clean',
      );
      expect(
        doc.contains('are a known divergence'),
        isFalse,
        reason: 'docs/storage_pattern.md §6 still lists the ui/ dart:io calls '
            'as a divergence. There are none now.',
      );
    });

    test('every guard the docs cite exists', () {
      // A doc that points at a guard which was renamed or deleted is claiming
      // enforcement it does not have, which is the failure this whole file
      // exists to prevent.
      final Set<String> guards = SourceTree()
          .dartFilesUnder('test/architecture')
          .keys
          .map((String p) => p.replaceAll(r'\', '/').split('/').last)
          .toSet();

      for (final String path in _tables.keys) {
        final String markdown = tree.read(path);
        final Set<String> cited = RegExp(r'\*\*guard\*\*\s+`(\w+_test)`')
            .allMatches(markdown)
            .map((RegExpMatch m) => '${m.group(1)}.dart')
            .toSet();

        expect(cited, isNotEmpty,
            reason: '$path should cite at least one architecture guard');
        for (final String c in cited) {
          expect(
            guards,
            contains(c),
            reason: '$path cites guard $c, which does not exist',
          );
        }
      }
    });
  });
}