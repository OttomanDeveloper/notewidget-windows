/// The changelog rule from `AGENTS.md` §0.6, as a test.
///
/// A style rule stated once and never checked is how the last one got reversed:
/// the 1.2.0 notes were three-paragraph essays arguing with themselves, written
/// by someone who had just read the rule saying not to. So this is the
/// mechanical form of it.
///
/// Scoped to the `Unreleased` section. Released sections are historical record,
/// and rewriting a shipped changelog to match a newer house style is a worse
/// trade than inconsistent formatting — so the guard must not demand it, or it
/// would be a rule everyone learns to ignore.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// A changelog in the shape §0.6 asks for.
const String _terse = '''
# Changelog

## Unreleased

### Added

- `changelog_guard_test`: fails on an entry longer than one bullet.
- A second change, on its own bullet.

### Fixed

- A bug is fixed.

## 1.0.0

### Added

- This is a released section and is not judged, however it is written.
  Even when it runs on for a paragraph, and on for another.
''';

void main() {
  final tree = SourceTree();

  group('a changelog entry says what changed', () {
    test('the real changelog has no Unreleased entry that breaks the rule', () {
      final faults = findChangelogFaults(tree.read('CHANGELOG.md'));

      expect(
        faults,
        isEmpty,
        reason: 'AGENTS.md §0.6.\n'
            'One bullet per change, at most $kChangelogBulletLines lines '
            'including the `- `, and no second paragraph hung off the same '
            'bullet. The reasoning goes in PROJECT.md or a pattern doc.\n\n'
            '${faults.join('\n')}',
      );
    });

    test('a correctly written changelog has no faults', () {
      expect(findChangelogFaults(_terse), isEmpty);
    });

    test('the rule bites: a second paragraph under one bullet is rejected', () {
      // The fingerprint the rule exists to catch. A wrapped bullet, a blank
      // line, then more indented text with no bullet above it — which is what
      // every one of the 1.2.0 notes looked like.
      const essay = '''
# Changelog

## Unreleased

### Fixed

- **The editor can no longer be shrunk to nothing.** It could be dragged by a
  corner down to a few pixels and left there.
  There is now a floor of 520 x 360.

  The floor comes from the layout rather than from taste, because the editor
  already collapses to one pane below 760 wide.
''';

      final faults = findChangelogFaults(essay);
      expect(
        faults.any((f) => f.contains('indented line with no bullet above it')),
        isTrue,
        reason: faults.join('\n'),
      );
    });

    test('the rule bites: a bullet longer than the limit is rejected', () {
      const long = '''
# Changelog

## Unreleased

### Fixed

- **Something.** A change that needed one sentence, and then a second one, and
  then a third, because the writer is explaining rather than saying, and by now
  the bullet has run to four lines and has not finished the thought, which is
  the part that gives it away.
''';

      final faults = findChangelogFaults(long);
      expect(
        faults.any((f) => f.contains('lines; the limit is')),
        isTrue,
        reason: faults.join('\n'),
      );
    });

    test('the guard bites: the essay that shipped as 1.2.0 is rejected', () {
      // Taken from the real released section, because a fixture invented for
      // the purpose proves less than the thing that actually happened. The
      // 1.2.0 notes are not judged as a section - only this excerpt is.
      //
      // Anchored on the `## 1.2.0` heading rather than on "the first `### Fixed`".
      // The earlier version found the first `### Fixed` anywhere in the file and the
      // next `### Added` after it, which silently depended on `Unreleased` having no
      // `Fixed` section of its own - so the day it grew one, this test quietly
      // stopped finding the fixture it was asserting on and failed with an empty
      // list. A negative fixture that can go missing is not a guard.
      final released = tree.read('CHANGELOG.md');
      final release = released.indexOf('## 1.2.0');
      expect(
        release,
        isNot(-1),
        reason: 'precondition: 1.2.0 is still a released section. If it is '
            'reformatted, point this at whichever section still contains the essay.',
      );

      final start = released.indexOf('### Fixed', release);
      final end = released.indexOf('\n## ', start);
      final body = end < 0 ? released.substring(start) : released.substring(start, end);

      final essay = '# Changelog\n\n## Unreleased\n\n$body\n';

      expect(
        findChangelogFaults(essay),
        isNotEmpty,
        reason: 'the 1.2.0 notes are the exact shape this rule forbids',
      );
    });

    test('an absent Unreleased section is not a fault', () {
      // The normal state between releases. Failing on it would mean the guard
      // could only be satisfied by leaving something in the file.
      expect(findChangelogFaults('# Changelog\n\n## 1.0.0\n\n### Added\n\n- x.\n'),
          isEmpty);
    });

    test('a released section is never judged, however long it runs', () {
      // The counterpart to the above: the guard must not push anyone to rewrite
      // a shipped changelog.
      const history = '''
# Changelog

## Unreleased

### Added

- A terse new entry.

## 1.0.0

### Fixed

- An old entry that is far too long to satisfy §0.6, and which stays anyway.
  It has a second paragraph.
  And a third.

  And a fourth, orphaned under nothing at all.
''';

      expect(findChangelogFaults(history), isEmpty);
    });

    test('the limit is a number a reader can check', () {
      // Asserted so the constant cannot be quietly raised to whatever the
      // current entries happen to need, which is the usual way a length rule
      // stops meaning anything.
      expect(kChangelogBulletLines, 3);
    });
  });
}