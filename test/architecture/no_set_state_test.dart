/// `AGENTS.md` §0.7: no `setState`, no excuse accepted.
///
/// Enforced as a **budget**, not an allowlist. There are 24 call sites today and
/// removing them is one piece of work; a rule that cannot be satisfied until that
/// work is finished is a rule that gets deleted instead of obeyed. So the count is
/// recorded per file, and the guard fails on three things:
///
///  - a file with more `setState` calls than its budget,
///  - a file with none recorded at all,
///  - a file with *fewer*, because that budget line is now a lie.
///
/// The third is the one that matters. A budget that only fails when it grows is a
/// number that drifts up to meet the code and nobody notices, which is how the last
/// style rule in this repo got reversed.
///
/// Read `docs/provider_pattern.md` §4 for what replaces each site.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// The 24 sites that exist today, counted per file.
///
/// Each number is the *only* thing standing between this guard and a green build,
/// so each one is a claim that can be falsified: fix a `setState` and this file
/// fails until the number comes down with it. That is deliberate. See
/// `docs/provider_pattern.md` §4.4 for the replacement each group gets.
const Map<String, int> setStateBudget = {
  'lib/src/ui/editor/editor_app.dart': 3,
  'lib/src/ui/editor/editor_view.dart': 10,
  'lib/src/ui/editor/note_editor_pane.dart': 1,
  'lib/src/ui/settings/settings_dialog.dart': 3,
  'lib/src/ui/widget/widget_app.dart': 2,
  'lib/src/ui/widget/widget_surface.dart': 5,
};

const RemovalBudget _setStates = RemovalBudget(
  what: 'setState call',
  allowance: setStateBudget,
  rule: 'Shared state belongs in a provider (`docs/provider_pattern.md` §3). '
      'Ephemeral state - hover, a one-shot hint, a dialog draft nobody has '
      'committed - belongs in a ValueNotifier read by a ValueListenableBuilder '
      '(`docs/widget_pattern.md` §3.19). There is no third option and no '
      'exemption for a State that "only holds one bool".',
);

void main() {
  final tree = SourceTree();

  group('no setState, no excuse', () {
    test('lib/ has no setState beyond the recorded countdown', () {
      final live = setStateCounts(tree);
      final faults = _setStates.faults(live);

      expect(
        faults,
        isEmpty,
        reason: 'AGENTS.md §0.7.\n'
            '${live.values.fold(0, (a, b) => a + b)} of '
            '${_setStates.allowanceTotal} recorded sites remain.\n\n'
            '${faults.join('\n')}',
      );
    });

    test('the countdown is still counting', () {
      // If the scanner found nothing at all, the rule above would be satisfied by
      // a broken scanner rather than by the code. A guard that cannot tell those
      // two apart is worse than no guard.
      final live = setStateCounts(tree);

      expect(
        live,
        isNotEmpty,
        reason: 'setStateCounts found nothing in lib/. Either the app has been '
            'migrated - in which case this budget and its whole guard should be '
            'deleted - or the scanner is broken.',
      );
      expect(
        live.values.fold(0, (a, b) => a + b),
        _setStates.allowanceTotal,
        reason: 'The recorded countdown and the code disagree. One `setState` '
            'with no budget line, or one budget line with no `setState`.',
      );
    });

    test('a new setState is a fault', () {
      const live = {
        'lib/src/ui/editor/editor_view.dart': 10,
        'lib/src/ui/editor/editor_app.dart': 3,
        'lib/src/ui/editor/note_editor_pane.dart': 1,
        'lib/src/ui/settings/settings_dialog.dart': 3,
        'lib/src/ui/widget/widget_app.dart': 2,
        'lib/src/ui/widget/widget_surface.dart': 5,
        'lib/src/ui/editor/editor_toolbar.dart': 1,
      };

      final faults = _setStates.faults(live);
      expect(
        faults.single,
        contains('is not in the budget at all'),
        reason: faults.join('\n'),
      );
      expect(faults.single, contains('editor_toolbar.dart'));
    });

    test('one more in a counted file is a fault', () {
      final live = Map<String, int>.from(setStateBudget);
      live['lib/src/ui/widget/widget_surface.dart'] =
          live['lib/src/ui/widget/widget_surface.dart']! + 1;

      final faults = _setStates.faults(live);
      expect(faults, hasLength(1));
      expect(faults.single, contains('the budget allows 5'));
    });

    test('one fewer is also a fault, and says why', () {
      // The property that makes this a countdown rather than a quota. Fixing a
      // site without lowering the number is how the number stops meaning anything,
      // so it fails and says so.
      final live = Map<String, int>.from(setStateBudget);
      live['lib/src/ui/widget/widget_surface.dart'] =
          live['lib/src/ui/widget/widget_surface.dart']! - 1;

      final faults = _setStates.faults(live);
      expect(faults, hasLength(1));
      expect(faults.single, contains('still allows 5'));
      expect(faults.single, contains('Delete the line'));
    });

    test('a file emptied completely has its budget line removed', () {
      final live = Map<String, int>.from(setStateBudget)..remove(
            'lib/src/ui/editor/note_editor_pane.dart',
          );

      final faults = _setStates.faults(live);
      expect(faults, hasLength(1));
      expect(faults.single, contains('note_editor_pane.dart'));
      expect(faults.single, contains('still allows 1'));
    });

    test('the scanner counts a setState wherever it is written', () {
      // The three ways it appears today. A scanner that only matched the
      // single-line form would under-report and the budget would look satisfied.
      const oneLine = 'onTap: () => setState(() => _busy = false),';
      const blockForm = '''
        setState(() {
          _busy = true;
        });''';
      const spaced = 'setState ( () { _x = 1; } );';

      expect(RegExp(r'\bsetState\s*\(').hasMatch(oneLine), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(blockForm), isTrue);
      expect(RegExp(r'\bsetState\s*\(').hasMatch(spaced), isTrue);
    });

    test('a name containing setState is not a setState call', () {
      // `resetState` and `_setStateValue` must not trip the scan, or the budget
      // inflates with false positives and stops being believed.
      for (final decoy in ['resetState();', '_setStateValue = 1;', 'setStates']) {
        expect(
          RegExp(r'\bsetState\s*\(').hasMatch(decoy),
          isFalse,
          reason: '$decoy is not a setState call',
        );
      }
    });

    test('the rule does not exempt tests', () {
      // `flutter_test` has no business calling setState either, and a budget that
      // quietly excluded test/ would be a hole with a plausible reason in it.
      expect(
        countPerFile(tree, 'lib', r'\bsetState\s*\(').keys,
        everyElement(startsWith('lib/src')),
        reason: 'The scan is over lib/ only. If test/ ever grows a setState, that '
            'is a separate rule and a separate decision, not a silent widening of '
            'this one.',
      );
    });
  });
}