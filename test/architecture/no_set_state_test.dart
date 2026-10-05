/// `AGENTS.md` §0.7: no `setState` anywhere in `lib/`. No excuse accepted.
///
/// This was a countdown. It was 24 sites on 2026-10-05, recorded per file, and the
/// budget lines are now gone: every one of them reached zero.
///
/// They were replaced by exactly two things, and the choice was about lifetime
/// rather than importance:
///
///  - **A provider.** `_busy`, `_ready`, `_settingsOpen`, `_showListOnNarrow` and
///    `_narrowShowsPreview` were all navigation, loading and responsive layout -
///    state that was never given anywhere to live.
///  - **A `ValueNotifier`.** `_hovering`, `_lockedHint`, `_composing`, `_pending`
///    and `_thumbOpacity` are true for one frame and nothing outside their widget
///    will ever ask. `widget_surface.dart` was already doing this once before the
///    migration, so the pattern was in the tree rather than imported.
///
/// `State` is not deleted. It remains the disposal shell for a `TextEditingController`,
/// a `ScrollController`, a `FocusNode`, and for the two widgets that must observe the
/// binding. What it may not do is hold a bool a provider could hold.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';


void main() {
  final tree = SourceTree();

  group('no setState, no excuse', () {
    test('lib/ has no setState calls at all', () {
      final live = setStateCounts(tree);

      expect(
        live,
        isEmpty,
        reason: 'AGENTS.md §0.7. Zero is the only accepted number.\n\n'
            '${live.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n'
            '    State that outlives the widget belongs in a provider; state that '
            'is true for one frame belongs in a ValueNotifier read by a '
            'ValueListenableBuilder. There is no third option.',
      );
    });

    test('the scanner still finds them, or the rule above is vacuous', () {
      // The rule above is satisfied by an empty map as easily as by clean code, so
      // the scanner is checked against text it must match. A guard that cannot tell
      // "no setState" from "no matches" is worse than no guard.
      expect(
        RegExp(r'\bsetState\s*\(').hasMatch('setState(() { _busy = true; });'),
        isTrue,
      );
      expect(
        RegExp(r'\bsetState\s*\(').hasMatch('onTap: () => setState ( () {} );'),
        isTrue,
      );
      expect(
        RegExp(r'\bsetState\s*\(').hasMatch('setState(() => _x = 1)'),
        isTrue,
      );
      expect(
        RegExp(r'\bsetState\s*\(').hasMatch('resetState();'),
        isFalse,
        reason: 'A name containing setState is not a call.',
      );
    });

    test('the two replacements are the only two', () {
      // Naming them is what stops the ban being satisfied by inventing a third
      // mechanism: a hand-rolled InheritedWidget, a global variable, a
      // StreamBuilder. Every rebuild in lib/ is now one of these two.
      final notifiers = countPerFile(tree, 'lib', r'ValueNotifier<');
      final providers = countPerFile(tree, 'lib', r'ref\.watch\(|ref\.listen\(');

      expect(notifiers, isNotEmpty, reason: 'the ValueNotifier half is in use');
      expect(providers, isNotEmpty, reason: 'the provider half is in use');
    });

    test('every ValueNotifier is listened to, or nothing rebuilds', () {
      // The one rule this migration could not enforce by deleting the thing it bans.
      //
      // `setState` had two jobs: hold the value, and rebuild the widget. A
      // `ValueNotifier` only does the first, so replacing a `setState` without adding
      // a listener produces code that compiles, analyzes clean, passes every test that
      // does not happen to look at the result, and silently does nothing. There is no
      // crash and no log - the field is simply written and read back by nobody.
      //
      // That happened three times during the 2026-10-05 migration, in three different
      // files, and in each case an existing behavioural test caught it:
      //
      //  - `note_editor_pane.dart`'s Preview button read `_narrowShowsPreview.value`
      //    outside the builder, so the label never changed.
      //  - `widget_surface.dart`'s `_lockedHint` had no listener at all, so a refused
      //    drag said nothing.
      //  - `settings_dialog.dart`'s `_pending` had no listener, so the capture dialog
      //    showed the combination it started with.
      //
      // So the check is coarse: a file that declares a `ValueNotifier` field must also
      // contain something that listens to one. It cannot prove *which* notifier is
      // wired, and it is not claiming to - it is claiming that the replacement for
      // `setState` was used as a replacement, rather than as a field.
      final declares = <String, int>{};
      for (final layer in ['lib/features', 'lib/core/widgets']) {
        for (final entry in countPerFile(tree, layer, r'\bValueNotifier<').entries) {
          declares[entry.key] = (declares[entry.key] ?? 0) + entry.value;
        }
      }
      expect(declares, isNotEmpty, reason: 'precondition: the pattern is in use');

      final silent = <String, String>{};
      for (final path in declares.keys) {
        final source = tree.read(path);
        final listens =
            RegExp(r'ValueListenableBuilder|ListenableBuilder|Listenable\.merge|\.addListener\(')
                .hasMatch(source);
        if (!listens) silent[path] = '${declares[path]} notifier(s), no listener';
      }

      expect(
        silent,
        isEmpty,
        reason: 'These declare a `ValueNotifier` and never listen to one, so nothing '
            'they write can ever reach the screen:\n\n'
            '${silent.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n'
            '    A `setState` rebuilds as a side effect of holding. A `ValueNotifier` '
            'does not - it needs a `ValueListenableBuilder`, a `ListenableBuilder`, '
            'or an `addListener`, and the symptom of forgetting is silence.',
      );
    });
  });
}
