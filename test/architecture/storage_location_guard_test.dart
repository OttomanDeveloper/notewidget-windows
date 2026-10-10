/// The storage location must be a real setting, not a placebo.
///
/// This guard exists because the setting was one for a long time and did nothing.
/// `Settings` had a folder picker, it saved `storageDirectory` into `settings.json`,
/// the dialog displayed the resolved path — and every file went to
/// `%APPDATA%\WinNotes` regardless. Nothing failed. The build was clean, `flutter
/// test` was green, and the app was honest about the path only in the one place that
/// was reading the setting back.
///
/// **A setting that is displayed but not obeyed has no symptom.** So the checks here
/// are about the *path actually used*, not about the setting existing.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

void main() {
  final SourceTree tree = SourceTree();

  group('main() resolves the location before it builds anything', () {
    test('the data directory comes from the resolver, not from the runner', () {
      // The single line that makes the feature real. Without it `paths` *was* the
      // runner's answer, and every other part of this file could be perfect while the
      // notes went to `%APPDATA%` anyway.
      final String main_ = tree.read('lib/main.dart');
      expect(
        main_,
        matches(RegExp(r'StorageLocation\.resolveDataDirectory\(')),
        reason: 'main() must resolve the configured folder. Assigning the result of '
            'AppPaths.resolve straight to `paths` is what left the picker inert.',
      );
    });

    test('and it is applied to the paths, not just computed', () {
      // Resolving and then ignoring it is the same failure wearing a hat.
      final String main_ = tree.read('lib/main.dart');
      expect(
        main_,
        matches(RegExp(r'copyWith\(\s*\n?\s*dataDirectory:')),
        reason: 'the resolved directory must reach AppPaths. A computed value that is '
            'never applied produces exactly the placebo this guard is for.',
      );
    });

    test('the reported directory is still what settings.json is read from', () {
      // The bootstrap ordering. `settings.json` is how the app learns where anything
      // else is, so it has to be findable before the answer is known — which is why
      // `reportedDirectory` and `dataDirectory` are separate fields rather than one.
      final String paths = tree.read('lib/core/utils/app_paths.dart');
      expect(
        paths,
        matches(RegExp(r'final String\? reportedDirectory;')),
        reason: 'two directories, not one. Collapsing them makes a chosen folder '
            'unfindable the first time somebody changes it.',
      );
      expect(
        paths,
        contains('settingsPointerFile'),
        reason: 'and there must be a named way to ask where the pointer lives',
      );
    });

    test('the pointer is in the reported directory and the library is not', () {
      final String paths = tree.read('lib/core/utils/app_paths.dart');
      expect(
        paths,
        matches(RegExp(r"settingsPointerFile\s*=>\s*'\$reportedDirectory")),
        reason: 'the pointer has to be where the app looks before it knows anything',
      );
      expect(
        paths,
        matches(RegExp(r"notesFile\s*=>\s*'\$dataDirectory")),
        reason: 'and notes must follow the chosen folder, which is the whole feature',
      );
    });
  });

  group('a chosen folder that is gone must not become an empty one', () {
    test('the resolver asks whether the folder is reachable', () {
      final String location = tree.read('lib/features/settings/data/storage_location.dart');
      expect(
        location,
        matches(RegExp(r'if \(!isReachable\(pointer\)\) return null;')),
        reason: 'An unplugged drive still has a perfectly well-shaped path, so a shape '
            'check alone passes it — and main() creates the data directory, which would '
            'recreate the folder locally and write an empty library into it. Total '
            'loss, dressed as a successful launch.',
      );
    });

    test('and the reachability check never creates the folder it is asked about', () {
      // The trap this guard exists for: a check that creates what it tests answers
      // "yes" to every path ever pointed at.
      final String location = tree.read('lib/features/settings/data/storage_location.dart');
      final String body = location.substring(
        location.indexOf('static bool isReachable'),
        location.indexOf('static bool isReachable') + 900,
      );

      expect(
        body,
        isNot(contains('createSync(recursive: true)')),
        reason: 'isReachable must not create. `Directory(...).createSync(recursive: '
            'true)` inside it would make a missing drive reappear as an empty library.',
      );
      expect(
        body,
        contains('existsSync()'),
        reason: 'it must ask whether the folder is there',
      );
    });

    test('main() creates the directory it resolved, which is the only creator', () {
      // One creator, and it happens after resolution. Asserted so a second
      // createSync elsewhere cannot appear and re-introduce the same hazard.
      final String main_ = tree.read('lib/main.dart');
      expect(
        RegExp(r'createSync\(recursive: true\)').allMatches(main_).length,
        equals(1),
        reason: 'main() creates the data directory exactly once. A second site is '
            'either redundant or is creating something that should not be created.',
      );
    });
  });

  group('nothing may be deleted by a transfer', () {
    test('the transfer code contains no delete of a source file', () {
      // "Copy, never move" is the decision the owner made, and the one that makes
      // this recoverable: a person who has seen the copy arrive can remove the old
      // one themselves. An app that deletes it has taken that away.
      final String transfer = tree.read('lib/features/settings/data/storage_transfer.dart');

      // Every delete in the file, with context, so the assertion below can say
      // something useful rather than just "no delete".
      final Iterable<RegExpMatch> deletes = RegExp(r'\.deleteSync\(\)|\.delete\(').allMatches(transfer);
      for (final RegExpMatch match in deletes) {
        final String before = transfer.substring(
          match.start > 260 ? match.start - 260 : 0,
          match.start,
        );
        final bool deletesSomethingInTheDestination =
            before.contains('.copying') ||
                before.contains('to.existsSync()') ||
                before.contains('destinationNotes') ||
                before.contains('.wn-write-probe');
        final bool deletingAProbe = before.contains('probe');

        expect(
          deletesSomethingInTheDestination || deletingAProbe,
          isTrue,
          reason: 'a delete outside the destination or a write-probe would risk '
              'removing a source file.\n  ...${before.trimRight()}\n  '
              '${transfer.substring(match.start, match.end)}',
        );
      }
    });

    test('a destination that already has notes is refused', () {
      // The other half of "cannot lose notes": pointing at the wrong folder must not
      // destroy a library that was never read.
      final String transfer = tree.read('lib/features/settings/data/storage_transfer.dart');
      expect(
        transfer,
        contains('destinationNotEmpty'),
        reason: 'the refusal has to be an outcome, or the UI has nothing to say',
      );
      expect(
        transfer,
        matches(RegExp(r'notes\.json')),
        reason: 'and the refusal is about notes specifically, which is the file that '
            'matters',
      );
    });

    test('the source is flushed before anything is copied', () {
      // A keystroke can still be in the debounce window. Copying before flushing
      // copies a file that is about to change, so "your notes arrived" would be
      // nearly true rather than true.
      //
      // Matched as `await StorageTransfer.copyLibrary(` rather than as the word
      // `copyLibrary`. The first version used the bare word and found it at offset
      // 310 — inside this method's own doc comment, which explains the rule before
      // the code does it. A guard that reads a comment is a guard that passes
      // whatever the code says.
      final String controller = tree.read('lib/features/settings/presentation/providers/settings_controller.dart');
      final String move = controller.substring(
        controller.indexOf('Future<StorageTransferOutcome> moveTo'),
        controller.indexOf('Future<StorageTransferOutcome> moveTo') + 1800,
      );
      final int flush = move.indexOf('flush()');
      final int copy = move.indexOf('await StorageTransfer.copyLibrary(');

      expect(
        flush,
        greaterThanOrEqualTo(0),
        reason: 'moveTo must flush before it copies',
      );
      expect(
        copy,
        greaterThan(flush),
        reason: 'and it must flush *before* the copy, not after',
      );
    });

    test('the pointer is written last', () {
      // Writing the pointer first means a failed transfer leaves the next launch
      // pointing at a folder with no notes in it. That is the whole ordering.
      final String controller = tree.read('lib/features/settings/presentation/providers/settings_controller.dart');
      final String move = controller.substring(
        controller.indexOf('Future<StorageTransferOutcome> moveTo'),
        controller.indexOf('Future<StorageTransferOutcome> moveTo') + 1800,
      );

      expect(
        move.indexOf('await StorageTransfer.copyLibrary('),
        lessThan(move.indexOf('_writePointer(')),
        reason: 'the copy has to land before the pointer that finds it',
      );
    });

    test('main() carries the unreachable folder onto the paths', () {
      // The silence is the bug. The resolver falls back to the default folder when
      // a chosen drive is missing - correct for reading, and it means the editor
      // would write there - so the fact has to survive resolution. Checked in
      // `main()` rather than in `resolveDataDirectory`, because carrying it is a
      // wiring decision: computing it and not attaching it is §3.0a's exact
      // failure wearing a hat, which is the first check in this file.
      final String main_ = tree.read('lib/main.dart');
      expect(
        main_,
        contains('unreachableDirectory: StorageLocation.unreachableChoice('),
        reason: 'a chosen folder that could not be reached must reach AppPaths. '
            'Otherwise the editor opens on the default folder and every keystroke '
            'lands in a place nobody chose, with nothing said.',
      );
    });

    test('the adopt path has no copy and no delete', () {
      // Adopting exists for somebody whose notes are already where they keep them.
      // The one thing it must never do is touch that folder - so this is checked as
      // source, because "nothing is written" is not an assertion a test can make
      // about a path the code decides to write to later.
      final String controller =
          tree.read('lib/features/settings/presentation/providers/settings_controller.dart');
      final int start = controller.indexOf('Future<StorageTransferOutcome> useExisting');
      expect(start, greaterThan(0), reason: 'precondition: the method exists');
      final String body = controller.substring(start, start + 1200);

      expect(
        RegExp(r'copyLibrary|\.copy\(|writeAsString|\.delete').allMatches(body),
        isEmpty,
        reason: 'adopting points the app at a folder; writing to it is §3.0b\'s '
            'overwrite wearing a smaller hat.\n\n  ...${body.trimRight()}',
      );
    });
  });

  group('the setting is persisted under one key, read by two readers', () {
    test('the bootstrap reader and the model agree on the key', () {
      // Two readers of settings.json is a real duplication, accepted because the
      // bootstrap read happens before any repository exists. The cost of that being
      // a *drift* rather than a duplication is one shared constant, and this is what
      // holds them to it.
      final String location = tree.read('lib/features/settings/data/storage_location.dart');
      final String settings = tree.read('lib/features/settings/domain/settings.dart');

      expect(
        location,
        contains("static const String storageDirectoryKey = 'storageDirectory'"),
      );
      expect(
        settings,
        matches(RegExp(r"'storageDirectory'")),
        reason: 'precondition: the model persists the same key the reader looks for',
      );
    });

    test('the bootstrap reader never throws', () {
      // Somebody whose preferences file is unreadable must still be able to open
      // their notes. That is the opposite of the notes rule on purpose, and it is
      // worth pinning so a future "let me clean this up" does not make the app refuse
      // to start over a preferences file.
      final String location = tree.read('lib/features/settings/data/storage_location.dart');
      final int start = location.indexOf('static String? _readKey');
      expect(start, greaterThan(0), reason: 'precondition: the reader exists');

      // To the end of the method rather than a fixed window: a slice is a number
      // someone guessed, and this one was guessed short enough to miss the `catch`
      // and report the guard as failing for the wrong reason.
      final String rest = location.substring(start);
      final String body = rest.substring(0, rest.indexOf('\n  }'));

      expect(
        body,
        contains('catch'),
        reason: 'a malformed settings.json must read as "no folder chosen", not throw',
      );
      expect(
        body,
        contains('return null'),
        reason: 'and the failure path is "no location chosen"',
      );
    });
  });

  group('the tests that cover it', () {
    test('storage_location_test exists and covers both directions', () {
      expect(tree.exists('test/storage_location_test.dart'), isTrue);
      final String tests = tree.read('test/storage_location_test.dart');
      for (final String claim in <String>[
        'files go there',
        'asking does not create the folder',
        'the original is left alone',
        'already has notes is refused',
        'adopted, and nothing in it is touched',
      ]) {
        expect(
          tests,
          contains(claim),
          reason: 'the guard above checks the shape of the implementation; this '
              'checks it actually does the thing. Both, or neither is evidence.',
        );
      }
    });
  });
}