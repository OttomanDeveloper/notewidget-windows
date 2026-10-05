/// `AGENTS.md` §0.8: a widget below a `ProviderScope` reads shared state with
/// `ref`, never through a constructor parameter.
///
/// This is the guard that matters most of the four added here, and the reason is
/// in the numbers. There are 23 constructor parameters today that thread a
/// controller, a shell channel or a settings object into a widget by hand, and
/// `settings_dialog.dart` alone accounts for 13 of them. Introducing Riverpod
/// without a rule here changes nothing: the next thing anyone writes is
/// `NoteEditorPane(controller: ref.read(notesProvider), ...)`, the tree is clean
/// for one commit, and the plumbing is back.
///
/// So the rule is about *where state comes from*, not about which library is
/// installed. It fails on a widget being handed a dependency, which is what makes
/// it survive the choice of state-management package.
///
/// Enforced as a countdown budget for the same reason as `no_set_state_test`: 23
/// sites exist now, and a rule unsatisfiable until the migration lands is a rule
/// that gets deleted rather than obeyed.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// The 23 injected parameters that exist today, counted per file.
const Map<String, int> injectedBudget = {
  'lib/src/ui/editor/editor_app.dart': 1,
  'lib/src/ui/editor/editor_view.dart': 3,
  'lib/src/ui/editor/note_editor_pane.dart': 1,
  'lib/src/ui/editor/note_list_pane.dart': 1,
  'lib/src/ui/settings/settings_dialog.dart': 13,
  'lib/src/ui/widget/widget_app.dart': 1,
  'lib/src/ui/widget/widget_surface.dart': 3,
};

const RemovalBudget _injected = RemovalBudget(
  what: 'injected state parameter',
  allowance: injectedBudget,
  rule: 'Read it with ref.watch to rebuild, or ref.read to act '
      '(`docs/provider_pattern.md` §2). A callback that has to reach a controller '
      'is ref.read inside the handler. What is allowed to cross a boundary as a '
      'parameter is a value, not a thing that holds state.',
);

void main() {
  final tree = SourceTree();

  group('state arrives through ref, not through a parameter', () {
    test('lib/src/ui has no injected state beyond the recorded countdown', () {
      final live = injectedStateParamCounts(tree);
      final faults = _injected.faults(live);

      expect(
        faults,
        isEmpty,
        reason: 'AGENTS.md §0.8.\n'
            '${live.values.fold(0, (a, b) => a + b)} of '
            '${_injected.allowanceTotal} recorded sites remain.\n\n'
            '${faults.join('\n')}',
      );
    });

    test('the countdown is still counting', () {
      final live = injectedStateParamCounts(tree);
      expect(live, isNotEmpty, reason: 'The scanner found nothing.');
      expect(
        live.values.fold(0, (a, b) => a + b),
        _injected.allowanceTotal,
        reason: 'The recorded countdown and the code disagree.',
      );
    });

    test('a new injected parameter is a fault', () {
      final live = Map<String, int>.from(injectedBudget);
      live['lib/src/ui/editor/editor_toolbar.dart'] = 2;

      final faults = _injected.faults(live);
      expect(faults.single, contains('is not in the budget at all'));
      expect(faults.single, contains('editor_toolbar.dart'));
    });

    test('a removed parameter has its budget line taken out', () {
      final live = Map<String, int>.from(injectedBudget)
        ..remove('lib/src/ui/editor/note_list_pane.dart');

      final faults = _injected.faults(live);
      expect(faults.single, contains('note_list_pane.dart'));
      expect(faults.single, contains('Delete the line'));
    });

    test('a value type passed as a parameter is not a fault', () {
      // The distinction the rule actually turns on. `this.path`, `this.index` and
      // `this.onTap` are fine: they are data or behaviour, and passing those is
      // what parameters are for. §0.8 is about a parameter that carries *state*,
      // because that is what makes a widget rebuild when it should not, and what
      // makes a subtree impossible to reuse under a different scope.
      for (final valueParam in [
        'required this.path',
        'required this.index',
        'required this.onTap',
        'required this.noteId',
        'required this.brightness',
      ]) {
        expect(
          RegExp(r'\bthis\.(controller|shell|settings)\b').hasMatch(valueParam),
          isFalse,
          reason: '$valueParam is a value and is not what §0.8 is about',
        );
      }

      expect(
        RegExp(r'\bthis\.(controller|shell|settings)\b')
            .hasMatch('required this.controller'),
        isTrue,
      );
    });

    test('a widget holding state by parameter is a fault', () {
      final live = Map<String, int>.from(injectedBudget);
      live['lib/src/ui/editor/note_card.dart'] = 3;

      final faults = _injected.faults(live);
      expect(faults, hasLength(1));
      expect(faults.single, contains('is not in the budget at all'));
      expect(faults.single, contains('note_card.dart'));
    });

    test('a load result is not an injected dependency', () {
      // `NotesLoaded(this.notes)` is why `notes` is absent from the scanner's
      // alternation. A scan that cannot tell a load result from a controller would
      // carry that false positive forever, and a budget with a permanent
      // false positive in it is a budget nobody believes.
      expect(
        RegExp(r'\bthis\.(controller|shell|settings)\b')
            .hasMatch('const NotesLoaded(this.notes);'),
        isFalse,
      );
      expect(
        RegExp(r'\bthis\.(controller|shell|settings)\b')
            .hasMatch('const NoteListPane({required this.controller})'),
        isTrue,
      );
    });

    test('every budgeted file is one the provider rule is really about', () {
      // If a budget line pointed at, say, `theme.dart`, the number would be
      // counting something else and the table in the doc would be fiction.
      for (final path in injectedBudget.keys) {
        expect(
          path,
          startsWith('lib/src/ui/'),
          reason: '$path holds state by injection but is not under ui/. '
              'Either it moved or the count means something else.',
        );
      }
    });

    test('the budget names every file that currently injects', () {
      // Catches the reverse drift: a new file that injects state is a fault above,
      // and this asserts the two lists are the same set today so the budget is a
      // description rather than an approximation.
      final live = injectedStateParamCounts(tree).keys.toSet();
      expect(
        live.difference(injectedBudget.keys.toSet()),
        isEmpty,
        reason: 'Files inject state that the budget does not list',
      );
      expect(
        injectedBudget.keys.toSet().difference(live),
        isEmpty,
        reason: 'The budget lists files that no longer inject anything',
      );
    });
  });
}