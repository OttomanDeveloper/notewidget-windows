/// `AGENTS.md` §0.10 and `docs/isolate_pattern.md`: the two surfaces build the same
/// graph, from one place.
///
/// This was a countdown. Ten constructions inside `lib/src/ui/` on 2026-10-05, five
/// in `EditorApp` and five in `WidgetApp`. Every one reached zero.
///
/// The reason it mattered was never tidiness. Each root built its own copy of the
/// same five things, and the duplication had already produced a live divergence:
/// `_resolveBrightness` existed in three copies across the two files and the widget's
/// copies disagreed with the editor's about the system-dark fallback. Both surfaces
/// could resolve "system" theme differently after a Windows theme change, and the
/// only symptom would be a widget that no longer matched the editor.
///
/// That is fixed, and the reason it is fixed rather than merely recorded is in the
/// guards below: one graph is built from one declaration in `lib/src/state/`, and
/// this check makes a second one impossible to reintroduce without a red build.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

void main() {
  final tree = SourceTree();

  group('one graph, built once', () {
    test('no widget constructs a repository or a controller', () {
      final live = uiConstructionCounts(tree);

      expect(
        live,
        isEmpty,
        reason: 'AGENTS.md §0.10.\n\n'
            '${live.entries.map((e) => '  ${e.key}: ${e.value}').join('\n')}\n'
            '    Construction belongs in lib/src/state/providers.dart, so both '
            'surfaces get the same graph. A repository that changes its constructor '
            'is then one edit instead of two.',
      );
    });

    test('the scanner still finds the six types it claims to', () {
      final live = uiConstructionCounts(tree);

      expect(live, isEmpty, reason: 'precondition: nothing to count');

      // Checked against the pattern rather than against the tree, because a scanner
      // that finds nothing and a clean codebase look identical from here.
      final pattern = RegExp(
        // `WidgetStateRepository` first: `Widget` followed by `Repository` does not
        // match it, because `State` is in between. The original pattern had that
        // hole and this test is what found it - a guard whose own test is the only
        // thing checking the scanner is a guard nobody has checked.
        r'\b(?:Notes|Settings|WidgetState|Selection)Repository\s*\(|\b(?:Notes|Settings|Widget)Controller\s*\(',
      );
      for (final declaration in [
        'NotesRepository(AtomicJsonFile(p))',
        'SettingsRepository(file, shell)',
        'WidgetStateRepository(file)',
        'SelectionRepository(file)',
        'NotesController(repository: r)',
        'SettingsController(repository: r, shell: s)',
        'WidgetController(shell: s)',
      ]) {
        expect(
          pattern.hasMatch(declaration),
          isTrue,
          reason: '$declaration must be caught by the scanner',
        );
      }
    });

    test('main() builds the scope and passes no state to either root', () {
      // The structure that made zero parameters possible. `main()` runs once per
      // isolate, so building the scope here gives each isolate its own container -
      // `docs/isolate_pattern.md` §2 - and means neither root widget takes a shell, a
      // launch info or a path.
      final main_ = tree.read('lib/main.dart');

      expect(
        main_.contains('ProviderScope'),
        isTrue,
        reason: 'The container is created once, with the three values it cannot '
            'discover for itself.',
      );
      expect(
        main_.contains('shellProvider.overrideWithValue'),
        isTrue,
        reason: 'The runner channel exists before any widget does.',
      );
      expect(
        main_.contains('launchInfoProvider.overrideWithValue'),
        isTrue,
      );
      expect(main_.contains('appPathsProvider.overrideWithValue'), isTrue);

      // And the roots themselves take nothing. Scoped to the root class rather
      // than the file, because `EditorEventRouter` in the same file legitimately
      // takes a `Widget child` - that is a value, not state.
      for (final root in {
        'lib/src/ui/editor/editor_app.dart': 'EditorApp',
        'lib/src/ui/widget/widget_app.dart': 'WidgetApp',
      }.entries) {
        final source = tree.read(root.key);
        final declaration = RegExp(
          'class ${root.value} extends ConsumerWidget \\{\\s*const ${root.value}\\(\\{([^}]*)\\}',
        ).firstMatch(source);

        expect(
          declaration,
          isNotNull,
          reason: '${root.value} must be a ConsumerWidget with an explicit const '
              'constructor, or this check cannot see what it takes.',
        );
        expect(
          RegExp(r'required\s+this\.').hasMatch(declaration!.group(1) ?? ''),
          isFalse,
          reason: '${root.value} takes a parameter. Whatever it needs belongs in '
              'a provider; `AGENTS.md` §0.8 has nothing carved out of it. Got: '
              '${declaration.group(1)}',
        );
      }
    });

    test('both roots read the same providers, from the same declarations', () {
      // The actual fix for §4.7: one place decides what a `ThemeData` is, and both
      // surfaces ask it. Three copies of a brightness resolver is not a style
      // problem; two of them already disagreed.
      final editor = tree.read('lib/src/ui/editor/editor_app.dart');
      final widgetApp = tree.read('lib/src/ui/widget/widget_app.dart');
      final themeScope = tree.read('lib/src/ui/theme_scope.dart');

      expect(
        themeScope.contains('widgetSurfaceThemeProvider'),
        isTrue,
        reason: 'precondition: there is one theme provider',
      );
      for (final entry in {'editor': editor, 'widget': widgetApp}.entries) {
        expect(
          entry.value.contains('widgetSurfaceThemeProvider'),
          isTrue,
          reason: 'the ${entry.key} surface must resolve its theme through the '
              'shared provider, not through its own copy of the logic',
        );
        // A declaration, not a mention. Both files *name* `_resolveBrightness` in a
        // comment saying it is gone, and checking the raw text would fail on its own
        // documentation - which is the trap `changelog_guard_test` already had to
        // be taught about.
        expect(
          RegExp(r'Brightness\s+_resolveBrightness\s*\(|void\s+_resolveBrightness\s*\(')
              .hasMatch(entry.value.replaceAll(RegExp(r'//.*'), '')),
          isFalse,
          reason: 'the ${entry.key} surface still declares its own brightness '
              'resolver, which is the divergence this replaced',
        );
      }
    });

    test('main() never touches the reported directory when an override is set', () {
      // The one line in `main()` that can write to the real profile: it creates the
      // data directory before any widget exists. It read `launch.dataDirectory` -
      // what the runner reported - rather than `paths.dataDirectory`, which is the
      // same directory unless `WIN_NOTES_DATA_DIR` overrides it.
      //
      // So the override was honoured for every read and write and the real
      // `%APPDATA%\WinNotes` was still created anyway, by the app, on every run. That
      // is the bug this whole change exists to remove: an override that touches the
      // directory it exists to avoid is worse than no override, because it looks like
      // isolation and is not.
      final main_ = tree.read('lib/main.dart');

      expect(
        main_.contains('AppPaths.resolve('),
        isTrue,
        reason: 'precondition: the override is resolved rather than ignored.',
      );
      expect(
        RegExp(r'Directory\(launch\.dataDirectory\)').hasMatch(main_),
        isFalse,
        reason: '`main()` must create `paths.dataDirectory`. `launch.dataDirectory` '
            'is what the runner reported - %APPDATA%\\WinNotes - and creating that '
            'when an override is in effect puts the real profile back on disk for a '
            'run that was supposed to be isolated from it. Use the resolved path.',
      );
    });

    test('the theme provider is under ui/, not state/', () {
      // `state/` must not reach up into `ui/`, so a provider that needs
      // `theme.dart` cannot live beside the repositories. Asserted because the
      // natural place to put it was `providers.dart`, and someone will try again.
      final providers = tree.read('lib/src/state/providers.dart');

      expect(
        providers.contains('theme.dart') || providers.contains('palette.dart'),
        isFalse,
        reason: 'lib/src/state/providers.dart must not import from ui/. The theme '
            'providers live in lib/src/ui/theme_scope.dart for exactly that reason.',
      );
      expect(tree.exists('lib/src/ui/theme_scope.dart'), isTrue);
    });

    test('the flush-on-teardown hazard is still named', () {
      // Not a fault. A recorded fact. The writes are still unawaited and still race
      // isolate death; `ref.onDispose` is synchronous and cannot await, so no amount
      // of provider work fixes it. `docs/storage_pattern.md` §3.11 says never lose a
      // data file, so it needs an answer rather than a migration.
      //
      // The test exists so the hazard cannot be forgotten by being quietly changed.
      final editor = tree.read('lib/src/ui/editor/editor_app.dart');

      // `EditorTeardown.run` awaits each flush internally and is itself called
      // unawaited from `dispose`, which is the same hazard in a new shape. The first
      // version of this test matched the old `unawaited(...flush())` text and passed
      // vacuously once the calls moved - so it checks the two halves separately,
      // because that is the only way it fails for the right reason.
      expect(
        RegExp(r'unawaited\(_teardown\.run\(\)\)').hasMatch(editor),
        isTrue,
        reason: 'Teardown must be called exactly once, unawaited, from dispose.',
      );
      expect(
        RegExp(r'await \w+\.flush\(\);').hasMatch(editor),
        isTrue,
        reason: 'The flushes themselves must still be awaited *inside* '
            'EditorTeardown - which is what makes the outer unawaited a hazard.',
      );

      // The widget surface has no teardown object, so it is checked on its own: the
      // flush is still unawaited, which is the recorded hazard.
      final widgetApp = tree.read('lib/src/ui/widget/widget_app.dart');
      expect(
        RegExp(r'unawaited\(_notifier\.flush\(\)\)').hasMatch(widgetApp),
        isTrue,
        reason: 'The widget surface has no EditorTeardown equivalent; its flush is '
            'still unawaited, and that is the hazard `AGENTS.md` section 4.8 records.',
      );

      // And the two roots must not reach for `ref` in `dispose`, which Riverpod
      // forbids outright - it throws during tree finalisation, after the test that
      // closed the surface has already passed.
      for (final root in {
        'editor': editor,
        'widget': widgetApp,
      }.entries) {
        final dispose = _disposeBody(root.value);
        expect(
          dispose,
          isNotNull,
          reason: 'the ${root.key} root has no dispose() to check',
        );
        expect(
          // Comments stripped first. Both roots *explain in a comment* why they do
          // not use `ref` here, so matching raw text fails on the file's own
          // documentation - the same trap `changelog_guard_test` had to be taught
          // about, and the reason this check cannot simply look for the word.
          RegExp(r'\bref\b').hasMatch(_stripComments(dispose!)),
          isFalse,
          reason: 'the ${root.key} root reads `ref` inside dispose(). Riverpod '
              'asserts on any `ref` use there, and the failure lands during tree '
              'finalisation - after the test has passed. Capture in initState.',
        );
      }
    });
  });
}

/// The body of the first `dispose()` in [source], or null if there is none.
///
/// Extracted so the assertions above can be about *what* the method does rather than
/// about how its text is shaped. Ends at the closing brace at two-space indent, which
/// is where a `State`'s `dispose` ends in every file here - and if that ever stops
/// being true the test fails rather than quietly passing on a prefix.
String? _disposeBody(String source) =>
    RegExp(r'void dispose\(\) \{([\s\S]*?)\n  \}').firstMatch(source)?.group(1);

/// [source] with `//` comments removed.
///
/// Crude on purpose: a `//` inside a string literal would confuse it, and none
/// appears in a `dispose`. Getting it wrong here means failing a guard that was
/// passing, which is the safe direction to be wrong in.
String _stripComments(String source) => source.replaceAll(RegExp(r'//.*'), '');