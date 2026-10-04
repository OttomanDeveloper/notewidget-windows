/// The dependency rule from `AGENTS.md` §0.4, as a test.
///
/// This is the only rule in the frozen list that is about the shape of the app
/// rather than the shape of a layer, and it is here rather than in
/// `AGENTS.md` §3 because §3 is the layer table. The rule it enforces is not
/// "no dependencies" — that would be a number and would eventually be wrong.
/// It is "every dependency is a decision somebody made on purpose", which is a
/// list.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

void main() {
  final tree = SourceTree();
  final pubspec = tree.read('pubspec.yaml');

  group('runtime dependencies are enumerated rather than open-ended', () {
    test('nothing is declared beyond the approved list', () {
      final unapproved = unapprovedDependencies(pubspec);

      expect(
        unapproved,
        isEmpty,
        reason: 'AGENTS.md §0.4 allows a named set, not a number.\n'
            '${unapproved.join(', ')} ${unapproved.length == 1 ? 'is' : 'are'} '
            'not on it.\n'
            'Before adding a package, settle three things: the rule says the '
            'capability should be owned in this repo rather than bought, and '
            'what exactly stays owned once it is. The first dependency to clear '
            'that bar was `markdown`, the CommonMark parser - parsing to a '
            'standard is not worth hand-writing, and the presentation still is.\n'
            'Then add the name to `approvedDependencies` in guards.dart, with '
            'the reasoning, so this stops failing.',
      );
    });

    test('the approved list is not empty, or the rule cannot fail', () {
      // A guard that passes because the allowed set contains everything is
      // indistinguishable from a guard that is not running. The approved set is
      // deliberately tiny, and this asserts it stayed tiny.
      expect(approvedDependencies, isNotEmpty);
      expect(
        approvedDependencies.length,
        lessThanOrEqualTo(2),
        reason: 'AGENTS.md §0.4 enumerates one package. If this now needs a '
            'bigger number, the rule has quietly become "no dependencies" '
            'again and the count is the wrong thing to be asserting.',
      );
      expect(approvedDependencies, contains('markdown'));
    });

    test('the scanner actually bites: a planted dependency is rejected', () {
      // Proven by feeding the scanner a pubspec that is not the real one,
      // rather than by editing this repository's. A guard that can only be
      // tested by breaking the thing it guards is a guard that gets left
      // untested.
      const planted = '''
name: win_notes
dependencies:
  flutter:
    sdk: flutter
  markdown: ^7.3.1
  http: ^1.2.0
dev_dependencies:
  flutter_test:
    sdk: flutter
''';

      expect(unapprovedDependencies(planted), <String>['http']);
    });

    test('the scanner reads the block it means to, and stops at the next key',
        () {
      // Two ways this could silently pass while doing nothing: reading
      // dev_dependencies as well, or running off the end of the file and
      // collecting every indented `name:` in it.
      const planted = '''
name: win_notes
dependencies:
  flutter:
    sdk: flutter
  markdown: ^7.3.1
dev_dependencies:
  never_in_shipped_app: ^1.0.0
''';

      expect(
        unapprovedDependencies(planted),
        isEmpty,
        reason: 'a test-only package cannot reach the shipped app',
      );
      expect(
        declaredRuntimeDependencies(planted),
        <String>{'markdown'},
        reason: 'the SDK entry is not a third-party dependency',
      );
    });

    test('a pubspec with no dependencies block is empty, not everything',
        () {
      expect(
        unapprovedDependencies('name: win_notes\nversion: 1.1.0+1\n'),
        isEmpty,
      );
    });

    test('the block is read at its own indentation, not an assumed two spaces',
        () {
      // A scanner hard-coded to two spaces finds nothing in a four-space pubspec
      // and reports a clean bill of health. That is the failure that reads as
      // enforcement, so it is worth a test of its own.
      const wide = '''
name: win_notes
dependencies:
    flutter:
        sdk: flutter
    markdown: ^7.3.1
    http: ^1.2.0
''';

      expect(
        unapprovedDependencies(wide),
        <String>['http'],
        reason: 'four-space indentation is a style choice, not a second class '
            'of dependency',
      );
    });
  });
}