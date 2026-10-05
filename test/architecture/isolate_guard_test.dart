/// `AGENTS.md` §0.10 and `docs/isolate_pattern.md`: the two surfaces build the
/// same graph, from one place.
///
/// This app has no DI framework. `EditorApp` and `WidgetApp` are each a
/// `StatefulWidget` whose `initState` constructs four repositories, loads settings
/// and wires an event stream - and then `dispose` flushes three of them in an
/// order that matters, with a comment explaining that there is no quit hook to do
/// it later. The two roots do this separately, and the duplication has already
/// produced a real divergence: `_resolveBrightness` exists in three copies across
/// the two files, and they disagree about what happens when the theme is "system"
/// and no system brightness has been reported yet.
///
/// So the rule is not "use Riverpod". It is that **construction happens in a
/// provider, once**, and both surfaces build the same graph from the same
/// declarations. That is what makes the duplication impossible rather than
/// discouraged.
///
/// The budget exists because the migration has not happened yet. Ten construction
/// sites, in two files, and the guard falls in both directions - see
/// `no_set_state_test` for why a countdown that can only rise is not a countdown.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// The ten constructions that exist today, inside widgets.
const Map<String, int> constructionBudget = {
  'lib/src/ui/editor/editor_app.dart': 5,
  'lib/src/ui/widget/widget_app.dart': 5,
};

const RemovalBudget _construction = RemovalBudget(
  what: 'dependency construction',
  allowance: constructionBudget,
  rule: 'Construct it in a provider and read it with ref '
      '(`docs/provider_pattern.md` §3.1). Both surfaces build the same graph, so '
      'a repository that changes constructor takes one edit instead of two.',
);

void main() {
  final tree = SourceTree();

  group('one graph, built once', () {
    test('no widget constructs a dependency beyond the recorded countdown', () {
      final live = uiConstructionCounts(tree);
      final faults = _construction.faults(live);

      expect(
        faults,
        isEmpty,
        reason: 'AGENTS.md §0.10.\n'
            '${live.values.fold(0, (a, b) => a + b)} of '
            '${_construction.allowanceTotal} recorded sites remain.\n\n'
            '${faults.join('\n')}',
      );
    });

    test('the countdown is still counting', () {
      final live = uiConstructionCounts(tree);
      expect(live, isNotEmpty, reason: 'The scanner found nothing.');
      expect(
        live.values.fold(0, (a, b) => a + b),
        _construction.allowanceTotal,
      );
    });

    test('construction in a third file is a fault', () {
      final live = Map<String, int>.from(constructionBudget);
      live['lib/src/ui/editor/editor_view.dart'] = 1;

      final faults = _construction.faults(live);
      expect(faults.single, contains('is not in the budget at all'));
    });

    test('the two roots are named, and they are the two roots', () {
      // If a third surface appears - a settings window, a second editor - the
      // duplication this doc exists to stop has already happened, and the budget
      // is the place it shows up first.
      expect(constructionBudget.keys, hasLength(2));
      expect(
        constructionBudget.keys.every((p) =>
            p == 'lib/src/ui/editor/editor_app.dart' ||
            p == 'lib/src/ui/widget/widget_app.dart'),
        isTrue,
      );
      expect(
        constructionBudget.values.every((n) => n == 5),
        isTrue,
        reason: 'Both roots construct the same five things. If that stops being '
            'true, the two surfaces need different graphs and that is a decision, '
            'not an accident.',
      );
    });

    test('main() still branches rather than being given both surfaces', () {
      // The rule that a ProviderScope must be per-isolate rests on this. Both
      // isolates call the same main(), so anything hoisted above the branch is
      // built twice - once per surface - which is correct, and anything that looks
      // like shared state across that line does not exist.
      final main_ = tree.read('lib/main.dart');
      expect(main_, contains('launch.isWidgetSurface'));
      expect(main_, contains('runApp('));
      expect(
        main_.contains('ProviderScope'),
        isFalse,
        reason: 'A ProviderScope in main() would be above the branch, so both '
            'isolates would build it - which is correct - but it would also hide '
            'the per-isolate boundary that docs/isolate_pattern.md §3.2 is about. '
            'Each root owns its own scope instead.',
      );
    });

    test('the flush-on-teardown hazard is still named', () {
      // Not a fault. A recorded fact, in the same spirit as the singleton: four
      // `unawaited(...flush())` calls run inside `dispose()`, and an unawaited
      // async write in a dispose whose isolate is being torn down can lose a
      // write. `docs/storage_pattern.md` §3.11 says never lose a data file. This
      // is pre-existing, it is not caused by any provider work, and Riverpod's
      // `ref.onDispose` cannot await - so it needs an answer, not a refactor.
      //
      // The test exists so the hazard cannot be forgotten by being fixed
      // accidentally without a word in the docs.
      final editor = tree.read('lib/src/ui/editor/editor_app.dart');
      expect(
        RegExp(r'unawaited\(_?\w+\.flush\(\)\)').hasMatch(editor),
        isTrue,
        reason: 'The unawaited flushes are gone. Before deleting this budget: is '
            'the write actually awaited now, and does docs/isolate_pattern.md §5 '
            'say so?',
      );
    });
  });
}