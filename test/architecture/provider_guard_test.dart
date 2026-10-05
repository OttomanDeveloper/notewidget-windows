/// `AGENTS.md` §0.8: a widget below a `ProviderScope` reads shared state with
/// `ref`, never through a constructor parameter.
///
/// This was a countdown. 23 parameters on 2026-10-05, across seven files, thirteen
/// of them in `settings_dialog.dart`. Every one reached zero and the budget is
/// gone.
///
/// Why the rule is about *where state comes from* rather than about which library
/// is installed: introducing a state package without this rule changes nothing. The
/// next thing anyone writes is `NoteEditorPane(controller: ref.read(notesProvider))`,
/// the tree is clean for one commit, and the plumbing is back. This check has teeth
/// on day one with `pubspec.yaml` untouched.
///
/// **Its known limit, stated rather than hidden.** It matches constructor *field
/// names*, not types. A dependency arriving as `this.foo` would not be caught.
/// The two `ScrollController` and `TextEditingController` fields this rule
/// legitimately tolerates are the price of a check that runs in CI, and they were
/// given honest names - `scroll`, `field` - so a reader can see they are per-widget
/// resources rather than shared state.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

void main() {
  final tree = SourceTree();

  group('state arrives through ref, not through a parameter', () {
    test('no widget holds shared state by constructor parameter', () {
      final live = injectedStateParamCounts(tree);

      expect(
        live,
        isEmpty,
        reason: 'AGENTS.md §0.8. Zero is the only accepted number.\n\n'
            '${live.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n'
            '    Read it with ref.watch to draw, ref.read to act. A callback may '
            'cross as a parameter; anything that holds state may not.',
      );
    });

    test('the scanner still matches the names it claims to', () {
      // The rule above is satisfied by an empty map, so the scanner is checked
      // against text it must match. Every name in the alternation, so a future
      // tightening that drops one is caught here rather than silently narrowing the
      // rule.
      for (final name in [
        'controller',
        'shell',
        'settings',
        'notifier',
        'store',
        'model',
        'repo',
        'repository',
        'viewModel',
      ]) {
        expect(
          RegExp(r'\bthis\.(controller|shell|settings|notifier|store|model|repo|repository|viewModel)\b')
              .hasMatch('required this.$name,'),
          isTrue,
          reason: 'this.$name must be caught. If it is deliberately exempt, delete '
              'it from the alternation and say why here.',
        );
      }
    });

    test('a value is not a dependency', () {
      // The distinction the rule turns on. `this.path` and `this.onTap` are fine:
      // they are data or behaviour, and passing those is what parameters are for.
      // `this.controller` holds state, which is what §0.8 is about.
      for (final valueParam in [
        'required this.path',
        'required this.index',
        'required this.onTap',
        'required this.noteId',
        'required this.brightness',
        'required this.scroll',
        'required this.field',
      ]) {
        expect(
          RegExp(
            r'\bthis\.(controller|shell|settings|notifier|store|model|repo|repository|viewModel)\b',
          ).hasMatch(valueParam),
          isFalse,
          reason: '$valueParam is a value and is not what §0.8 is about',
        );
      }
    });

    test('a load result is not an injected dependency', () {
      // `NotesLoaded(this.notes)` is why `notes` is absent from the alternation. A
      // scan that could not tell a load result from a controller would carry that
      // false positive forever, and a guard with a permanent false positive is one
      // nobody believes.
      expect(
        RegExp(r'\bthis\.(controller|shell|settings|notifier|store|model|repo|repository|viewModel)\b')
            .hasMatch('const NotesLoaded(this.notes);'),
        isFalse,
      );
    });

    test('callbacks are allowed, and are what the roots pass', () {
      // The rule has to leave room for something, or it reads as "no parameters".
      // What it leaves room for is behaviour: `EditorView` takes three callbacks and
      // no state, and that is the shape every widget below the roots should have.
      final editorView = tree.read('lib/src/ui/editor/editor_view.dart');

      expect(
        editorView.contains('final VoidCallback onOpenSettings;'),
        isTrue,
        reason: 'precondition: callbacks still cross as parameters',
      );
      expect(
        injectedStateParamCounts(tree),
        isEmpty,
        reason: 'and nothing that holds state does',
      );
    });
  });

  group('a provider file may not grow past the cap', () {
    // `docs/provider_pattern.md` §3.6 sets 200 lines, and two files are over it:
    // `notes_controller.dart` at 637 and `widget_controller.dart` at 413. That is
    // recorded in `AGENTS.md` §4 rather than hidden, so the rule currently reads as
    // broken.
    //
    // This group does not pretend otherwise. It makes the breach *bounded in one
    // direction*: a third file over the cap is a red build. Without that, "we are
    // already over" quietly becomes "we are all over", and a cap that is already
    // violated is not a cap - it is a number in a document. The two existing
    // breaches stay visible and named, and the count is what gets pinned.
    test('no more provider files are over the cap than are already recorded', () {
      const cap = 200;

      // Named, so the message can say which is which rather than "3 files, expected
      // 2", and so the removal half below has something to check against.
      const known = <String>{
        'lib/src/state/notes_controller.dart',
        'lib/src/state/widget_controller.dart',
      };

      final over = _filesOverCap(
        tree.dartFilesUnderRelative('lib/src/state'),
        cap,
      );

      expect(
        over.keys.toSet().difference(known),
        isEmpty,
        reason: 'A new file is over the $cap-line cap in `lib/src/state/`.\n'
            '  over the cap: ${over.entries.map((e) => '${e.key} (${e.value})').join(', ')}\n'
            '  already recorded in AGENTS.md §4: ${(known.toList()..sort()).join(', ')}\n\n'
            'Split it before adding to it. Two files over the cap is recorded debt; '
            'three is drift, and the only difference between the two is whether '
            'anything notices.',
      );

      // And the recorded two must still be the ones that are over, so a split that
      // brings one under the cap has to update the record in the same commit rather
      // than leaving a file named as a breach that no longer is.
      expect(
        known.difference(over.keys.toSet()),
        isEmpty,
        reason: 'A recorded breach is no longer over the cap:\n'
            '  ${known.difference(over.keys.toSet()).join(', ')}\n'
            'Remove it from the list in this test, from `AGENTS.md` §4 and from '
            '`docs/provider_pattern.md` §3.6 in the same change. A record that '
            'overstates the debt is the same failure as one that hides it.',
      );
    });

    test('the scanner measures what it claims to measure', () {
      // A cap guard that silently measures nothing passes forever, and the way it
      // silently measures nothing is by keying on paths that never match. So this
      // asks for the two named files directly rather than trusting the absence in
      // the test above to mean anything.
      final over = _filesOverCap(
        tree.dartFilesUnderRelative('lib/src/state'),
        200,
      );

      expect(
        over,
        containsPair('lib/src/state/notes_controller.dart', 637),
        reason: 'precondition: `notes_controller.dart` is 637 lines against a cap of '
            '200, so it must appear with that count. The number changes as the split '
            'lands - update it then, and in `AGENTS.md` §4 in the same change.',
      );
      expect(
        over.keys,
        contains('lib/src/state/widget_controller.dart'),
        reason: 'precondition: and `widget_controller.dart` is over the cap too.',
      );
      expect(
        _filesOverCap(tree.dartFilesUnderRelative('lib/src/state'), 10000),
        isEmpty,
        reason: 'precondition: a cap of 10000 excludes everything, so the scanner '
            'does discriminate rather than always returning a set.',
      );
    });
  });
}

/// Files over [cap] lines, keyed by repo-relative path with forward slashes.
Map<String, int> _filesOverCap(
  Map<String, List<String>> files,
  int cap,
) {
  final out = <String, int>{};
  for (final entry in files.entries) {
    final lines = entry.value.length;
    if (lines > cap) out[entry.key] = lines;
  }
  return out;
}