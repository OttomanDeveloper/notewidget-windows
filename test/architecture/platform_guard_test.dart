/// `AGENTS.md` §0.9 and `docs/platform_pattern.md`: the Dart-to-runner contract is
/// declared in one place.
///
/// `AGENTS.md` §3 already says "every method name must exist on both sides", and
/// `layer_test` checks it. What it did not do was *declare* the contract, which
/// left two problems:
///
///  1. **The check had a blind spot.** `dartMethodNames` matched `_fire(` and
///     `_invoke(` **line by line**, so any call whose name sat on the next line was
///     invisible: `dialog.confirmQuit`, `path.pickFile`, `path.pickFolder`,
///     `path.saveFile` and `widget.beginResize` were never parity-checked. All
///     five are handled by the runner, so no code was broken - the guard was
///     reporting on 19 of 24 methods and calling it parity, and its own
///     `greaterThan(15)` assertion passed partly *because* of what it missed.
///  2. **Four dispatch idioms, one undocumented.** `_fire` swallows failures,
///     `_invoke` turns `PlatformException` into null, and seven methods call
///     `methodChannel.invokeMethod` / `invokeMapMethod` directly with a
///     hand-rolled `try` each. Nothing said which a new method should use.
///
/// The registry below is the contract: 28 names, checked three ways - declared,
/// actually called, actually handled - plus the six `event.*` names that travel the
/// other way and must never appear in it. `docs/platform_pattern.md` §2 lists the
/// same 28 and a test here asserts the two agree, so the doc cannot rot into
/// fiction while still looking authoritative.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// Every method Dart sends to the runner.
///
/// `bootstrap` is the only one without a `namespace.` prefix. It was already like
/// that and the runner matches on it, so it stays - but `docs/platform_pattern.md`
/// §3.2 records it as the one name a newcomer will copy by accident.
const Set<String> platformMethodRegistry = {
  'app.quit',
  'autostart.query',
  'autostart.set',
  'bootstrap',
  'dialog.confirmQuit',
  'editor.running',
  'hotkey.register',
  'note.create',
  'note.toggleCompleted',
  'path.open',
  'path.pickFile',
  'path.pickFolder',
  'path.reveal',
  'path.saveFile',
  'shell.openSettings',
  'shell.showEditor',
  'shell.showWidget',
  'tray.notice',
  'widget.beginMove',
  'widget.beginResize',
  'widget.configure',
  'widget.getBounds',
  'widget.setComposeMode',
  'widget.setGeometry',
  'window.focus',
  'window.hide',
  'window.setTitle',
  'window.show',
};

/// The six events the runner pushes up to Dart.
///
/// Same channel, opposite direction. They are listed here so a test can assert the
/// two namespaces stay disjoint - they travel together and are easy to confuse.
const Set<String> inboundEvents = {
  'event.createNote',
  'event.geometry',
  'event.hotkey',
  'event.openSettings',
  'event.toggleCompleted',
  'event.visibility',
};

void main() {
  final tree = SourceTree();

  group('the platform contract is declared, not inferred', () {
    test('registry, Dart calls and runner handlers all agree', () {
      final faults = platformRegistryFaults(
        registry: platformMethodRegistry,
        called: channelMethodNames(tree),
        handled: runnerMethodNames(tree),
      );

      expect(
        faults,
        isEmpty,
        reason: 'AGENTS.md §0.9, docs/platform_pattern.md §3.1.\n'
            '${platformMethodRegistry.length} declared, '
            '${channelMethodNames(tree).length} called, '
            '${runnerMethodNames(tree).length} handled.\n\n'
            '${faults.join('\n')}',
      );
    });

    test('the scan covers all four dispatch idioms', () {
      // The reason the old scanner was wrong, kept as a test so the four idioms
      // cannot quietly become three. A name on its own line is the case that bit:
      // `\s` matches a newline in a Dart RegExp, which is why the scan is over
      // joined text and not over lines.
      final called = channelMethodNames(tree);

      expect(
        called.contains('widget.beginResize'),
        isTrue,
        reason: 'beginWidgetResize writes _fire( and the name on the next line. '
            'A line-by-line scan misses it, which is exactly how five real '
            'methods went unchecked.',
      );
      expect(
        called.contains('path.saveFile'),
        isTrue,
        reason: 'saveFile calls methodChannel.invokeMethod directly, bypassing '
            'the _fire and _invoke helpers entirely.',
      );
      expect(called.length, greaterThanOrEqualTo(28));
    });

    test('an inbound event in the outbound registry is a fault', () {
      final faults = platformRegistryFaults(
        registry: {...platformMethodRegistry, 'event.hotkey'},
        called: channelMethodNames(tree),
        handled: runnerMethodNames(tree),
      );

      // Two faults, not one: an inbound name is both a method Dart never sends and
      // a method the runner never handles as an outbound call. Either is enough.
      expect(
        faults.any((f) => f.contains('Inbound event names')),
        isTrue,
        reason: faults.join('\n'),
      );
      expect(
        faults.firstWhere((f) => f.contains('Inbound event names')),
        contains('shares the channel, not the direction'),
      );
    });

    test('a method called but not declared is a fault', () {
      final faults = platformRegistryFaults(
        registry: platformMethodRegistry.where((n) => n != 'app.quit').toSet(),
        called: channelMethodNames(tree),
        handled: runnerMethodNames(tree),
      );

      expect(
        faults.any((f) => f.contains('not in the registry') && f.contains('app.quit')),
        isTrue,
        reason: faults.join('\n'),
      );
    });

    test('a declared method the runner ignores is a fault', () {
      final faults = platformRegistryFaults(
        registry: {...platformMethodRegistry, 'widget.teleport'},
        called: platformMethodRegistry,
        handled: runnerMethodNames(tree),
      );

      expect(faults, isNotEmpty);
      expect(faults.first, contains('widget.teleport'));
    });

    test('an empty registry is a fault, not a pass', () {
      // Every set-difference check above is satisfied by two empty sets. Without
      // this the guard could be satisfied by deleting the contract.
      final faults = platformRegistryFaults(
        registry: const {},
        called: channelMethodNames(tree),
        handled: runnerMethodNames(tree),
      );

      expect(faults, isNotEmpty);
      expect(faults.last, contains('empty'));
    });

    test('the registry names exactly what the runner handles', () {
      // Kept separate from the three-way check so a failure says which side moved.
      expect(
        runnerMethodNames(tree).difference(platformMethodRegistry),
        isEmpty,
        reason: 'The runner handles something the registry does not declare',
      );
      expect(
        channelMethodNames(tree).difference(platformMethodRegistry),
        isEmpty,
        reason: 'Dart calls something the registry does not declare',
      );
      expect(
        platformMethodRegistry.difference(channelMethodNames(tree)),
        isEmpty,
        reason: 'The registry declares something Dart never sends',
      );
    });

    test('the doc lists the same 28 names the registry does', () {
      // A registry that exists only in a test file is a private convention. The
      // doc is where a new method is added, so the two are checked against each
      // other and a name added to one without the other is a fault.
      //
      // Names are read from table rows only, and only from the namespaces the
      // runner actually uses. Scanning all backticked text picks up
      // `methodChannel.invokeMethod` and `namespace.verb` from prose, which is
      // how a doc-parity check becomes a check that nothing has ever been wrong.
      final doc = tree.read('docs/platform_pattern.md');
      final namespaces = RegExp(
        r'^(?:app|autostart|dialog|editor|event|hotkey|note|path|shell|tray|widget|window)\.'
        r'[a-zA-Z]+$',
      );
      final listed = <String>{};
      for (final line in doc.split('\n')) {
        if (!line.trimLeft().startsWith('|')) continue;
        for (final m in RegExp(r'`([a-zA-Z]+\.[a-zA-Z]+|bootstrap)`')
            .allMatches(line)) {
          final name = m.group(1)!;
          if (namespaces.hasMatch(name) || name == 'bootstrap') listed.add(name);
        }
      }

      final missingFromDoc =
          platformMethodRegistry.difference(listed).toList()..sort();
      final listedButUndeclared =
          listed.difference(platformMethodRegistry).toList()..sort();

      expect(
        missingFromDoc,
        isEmpty,
        reason: 'docs/platform_pattern.md does not list these methods. The table '
            'is the contract people read; a name only in the test file is not '
            'discoverable.\n\n  $missingFromDoc',
      );
      expect(
        listedButUndeclared,
        isEmpty,
        reason: 'docs/platform_pattern.md lists a method the registry does not. '
            'Either the call was renamed or it was never declared.\n\n  '
            '$listedButUndeclared',
      );
    });

    test('the two directions have separate namespaces', () {
      expect(
        platformMethodRegistry.intersection(inboundEvents),
        isEmpty,
        reason: 'A name cannot be both an outbound call and an inbound event. '
            'They share one MethodChannel, which is why this is checked.',
      );
      expect(
        inboundEvents.every((e) => e.startsWith('event.')),
        isTrue,
        reason: 'Inbound names are all under event., and that prefix is what '
            'keeps them out of the outbound registry.',
      );
    });

    test('ShellEvents is still a process-wide singleton, and that is named', () {
      // Not a fault - a recorded fact. `docs/platform_pattern.md` §4 says why it
      // is acceptable and what would have to change. A test that asserted it was
      // fixed would be claiming a fix that has not happened.
      final channel = tree.read('lib/src/platform/shell_channel.dart');
      expect(
        channel.contains('static final ShellEvents instance'),
        isTrue,
        reason: 'The singleton is gone. Delete this test and update '
            'docs/platform_pattern.md §4, do not leave a claim of a fix that did '
            'not happen.',
      );
    });
  });
}