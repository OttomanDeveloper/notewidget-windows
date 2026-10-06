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
  final SourceTree tree = SourceTree();

  group('state arrives through ref, not through a parameter', () {
    test('no widget holds shared state by constructor parameter', () {
      final Map<String, int> live = injectedStateParamCounts(tree);

      expect(
        live,
        isEmpty,
        reason: 'AGENTS.md §0.8. Zero is the only accepted number.\n\n'
            '${live.entries.map((MapEntry<String, int> e) => '  ${e.key}: ${e.value}').join('\n')}\n'
            '    Read it with ref.watch to draw, ref.read to act. A callback may '
            'cross as a parameter; anything that holds state may not.',
      );
    });

    test('the scanner still matches the names it claims to', () {
      // The rule above is satisfied by an empty map, so the scanner is checked
      // against text it must match. Every name in the alternation, so a future
      // tightening that drops one is caught here rather than silently narrowing the
      // rule.
      for (final String name in <String>[
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
      for (final String valueParam in <String>[
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
      final String editorView = tree.read('lib/features/notes/presentation/screens/editor_view/editor_view.dart');

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
    // §2 sets 300 lines, code only. One file is over it: `notes_controller.dart`
    // at 333. Recorded in `AGENTS.md` §4 rather than hidden. The split from
    // `provider_pattern.md` §3.6 (list/selection/search vs corrupt-file recovery)
    // lands separately; until then the breach is bounded in one direction: a
    // second file over the cap is a red build.
    test('no more provider files are over the cap than are already recorded', () {
      const int cap = 300;

      // Empty since the notes split: no provider file is over the cap. Kept as
      // a set rather than deleted so the next breach has a named place to go,
      // and the removal half below keeps checking the record is current.
      const Set<String> known = <String>{};

      final Map<String, int> over = _filesOverCodeOnlyCap(
        _providerFiles(tree),
        cap,
      );

      expect(
        over.keys.toSet().difference(known),
        isEmpty,
        reason: 'A new file is over the $cap-line code-only cap in a providers/ dir.\n'
            '  over the cap: ${over.entries.map((MapEntry<String, int> e) => '${e.key} (${e.value})').join(', ')}\n'
            '  already recorded in AGENTS.md §4: ${(known.toList()..sort()).join(', ')}\n\n'
            'Split it before adding to it. One file over the cap is recorded debt; '
            'two is drift, and the only difference between the two is whether '
            'anything notices.',
      );

      // And the recorded breach must still be the one that is over, so a split
      // that brings it under the cap has to update the record in the same commit
      // rather than leaving a file named as a breach that no longer is.
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
      // asks for the split files directly rather than trusting the absence in
      // the test above to mean anything.
      final Map<String, int> over = _filesOverCodeOnlyCap(
        _providerFiles(tree),
        300,
      );

      expect(
        over,
        isEmpty,
        reason: 'precondition: no provider file is over the cap after the split.',
      );
      for (final String split in <String>[
        'lib/features/notes/presentation/providers/notes_controller.dart',
        'lib/features/notes/presentation/providers/notes_state.dart',
      ]) {
        expect(
          _providerFiles(tree).keys,
          contains(split),
          reason: 'precondition: the split file $split is scanned, or the '
              'emptiness above is vacuous.',
        );
      }
      expect(
        _filesOverCodeOnlyCap(_providerFiles(tree), 10000),
        isEmpty,
        reason: 'precondition: a cap of 10000 excludes everything, so the scanner '
            'does discriminate rather than always returning a set.',
      );
    });
  });
}

/// Code-only line count per §2: imports, blank lines and comments do not count.
int _codeOnlyLines(List<String> lines) {
  int n = 0;
  for (final String line in lines) {
    final String trimmed = line.trimLeft();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('//')) continue;
    if (trimmed.startsWith('import ') ||
        trimmed.startsWith('export ') ||
        trimmed == 'library;') {
      continue;
    }
    n++;
  }
  return n;
}

/// Files over [cap] code-only lines, keyed by repo-relative path.
Map<String, int> _filesOverCodeOnlyCap(
  Map<String, List<String>> files,
  int cap,
) {
  final Map<String, int> out = <String, int>{};
  for (final MapEntry<String, List<String>> entry in files.entries) {
    final int lines = _codeOnlyLines(entry.value);
    if (lines > cap) out[entry.key] = lines;
  }
  return out;
}

/// Every file that may hold a provider: the three feature providers dirs plus
/// the shared graph in `core/utils`. Narrow on purpose: a screen or widget file
/// over the cap is a §2 matter, not a provider matter.
Map<String, List<String>> _providerFiles(SourceTree tree) => <String, List<String>>{
      ...tree.dartFilesUnderRelative(
        'lib/features/notes/presentation/providers',
      ),
      ...tree.dartFilesUnderRelative(
        'lib/features/widget/presentation/providers',
      ),
      ...tree.dartFilesUnderRelative(
        'lib/features/settings/presentation/providers',
      ),
      'lib/core/utils/app_providers.dart':
          tree.read('lib/core/utils/app_providers.dart').split('\n'),
    };