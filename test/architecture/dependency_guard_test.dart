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
  final SourceTree tree = SourceTree();
  final String pubspec = tree.read('pubspec.yaml');

  group('runtime dependencies are enumerated rather than open-ended', () {
    test('nothing is declared beyond the approved list', () {
      final List<String> unapproved = unapprovedDependencies(pubspec);

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
        lessThanOrEqualTo(3),
        reason: 'AGENTS.md §0.4 enumerates three packages: the CommonMark '
            'parser, and the two halves of Riverpod. `riverpod` is pure Dart and '
            '`flutter_riverpod` is its Flutter binding - one decision, two '
            'entries, because the rule is about what pubspec.yaml declares. If '
            'this needs a fourth, the count is no longer the thing to assert '
            'and the reasoning in guards.dart has to say why.',
      );
      expect(approvedDependencies, contains('markdown'));
      expect(approvedDependencies, contains('riverpod'));
      expect(approvedDependencies, contains('flutter_riverpod'));
    });

    test('the two riverpod entries are the same version, or one is redundant', () {
      // `flutter_riverpod` depends on `riverpod`, so declaring only the former
      // would work. Declaring both is deliberate - the rule is about what
      // pubspec.yaml says - but if the constraints ever diverge, this app is
      // building against two versions of the same library, which is a class of
      // bug that shows up as an unexplained cast error at runtime.
      final List<String> declared = RegExp(r'^\s{2}(riverpod|flutter_riverpod):\s*(\S+)',
              multiLine: true)
          .allMatches(SourceTree().read('pubspec.yaml'))
          .map((RegExpMatch m) => '${m.group(1)}=${m.group(2)}')
          .toList();

      expect(declared, hasLength(2), reason: 'both should be declared');
      final Set<String> constraints =
          declared.map((String d) => d.substring(d.indexOf('=') + 1)).toSet();
      expect(
        constraints,
        hasLength(1),
        reason: 'The two must resolve to one version:\n  $declared',
      );
    });

    test('the scanner actually bites: a planted dependency is rejected', () {
      // Proven by feeding the scanner a pubspec that is not the real one,
      // rather than by editing this repository's. A guard that can only be
      // tested by breaking the thing it guards is a guard that gets left
      // untested.
      const String planted = '''
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
      const String planted = '''
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
      const String wide = '''
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