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
  final SourceTree tree = SourceTree();

  group('a changelog entry says what changed', () {
    test('the real changelog has no Unreleased entry that breaks the rule', () {
      final List<String> faults = findChangelogFaults(tree.read('CHANGELOG.md'));

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
      const String essay = '''
# Changelog

## Unreleased

### Fixed

- **The editor can no longer be shrunk to nothing.** It could be dragged by a
  corner down to a few pixels and left there.
  There is now a floor of 520 x 360.

  The floor comes from the layout rather than from taste, because the editor
  already collapses to one pane below 760 wide.
''';

      final List<String> faults = findChangelogFaults(essay);
      expect(
        faults.any((String f) => f.contains('indented line with no bullet above it')),
        isTrue,
        reason: faults.join('\n'),
      );
    });

    test('the rule bites: a bullet longer than the limit is rejected', () {
      const String long = '''
# Changelog

## Unreleased

### Fixed

- **Something.** A change that needed one sentence, and then a second one, and
  then a third, because the writer is explaining rather than saying, and by now
  the bullet has run to four lines and has not finished the thought, which is
  the part that gives it away.
''';

      final List<String> faults = findChangelogFaults(long);
      expect(
        faults.any((String f) => f.contains('lines; the limit is')),
        isTrue,
        reason: faults.join('\n'),
      );
    });

    test('the guard bites: the essay that shipped as 1.2.0 is rejected', () {
      // Verbatim from the 1.2.0 notes as they originally shipped, taken because
      // that is the real shape rather than one invented for the purpose.
      //
      // An earlier version pulled this out of the repository with
      // `indexOf('## 1.2.0')` and asserted the extracted section was faulty. That
      // worked only while CHANGELOG.md still contained the essay, and it was a
      // fixture that could go missing: the moment the changelog was converted to
      // the house style, `indexOf` returned a section that was perfectly legal,
      // and the test failed for the wrong reason while still reading as a guard
      // of something. A negative fixture that depends on the thing it is testing
      // for continuing to exist is not a guard. So the excerpt lives here.
      const String essay = '''
# Changelog

## Unreleased

### Fixed

- **The editor can no longer be shrunk to nothing.** It could be dragged by a
  corner down to a few pixels and left there — a window too small to hold a
  title, a note and a status bar is not a smaller version of this app, it is a
  broken one. There is now a floor of **520 × 360**.

  The floor comes from the layout rather than from taste: the editor already
  collapses to one pane at a time below 760 wide, and that pane stops fitting
  much under 400, so 520 leaves the narrow layout genuinely usable rather than
  technically reachable.

  Enforced with `WM_GETMINMAXINFO`, the only hook that governs the size the user
  can reach by dragging a frame edge.
''';

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
      const String history = '''
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