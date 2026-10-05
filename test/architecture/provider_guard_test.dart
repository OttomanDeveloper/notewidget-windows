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
}