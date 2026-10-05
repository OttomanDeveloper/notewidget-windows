import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/utils/app_paths.dart';

/// `AppPaths.resolve` — the override that lets tooling run without touching a
/// real profile.
///
/// Added on 2026-10-05 after a verification script moved `%APPDATA%\WinNotes` aside,
/// restored it, and then deleted it again on the next line. The fix that would have
/// prevented that is here: the app can be pointed somewhere else, so nothing has to
/// move the real directory out of the way at all.
void main() {
  group('with nothing set, it uses what the runner reported', () {
    test('the reported directory is used as-is', () {
      final paths = AppPaths.resolve(
        reported: r'C:\Users\someone\AppData\Roaming\WinNotes',
        executablePath: r'C:\Program Files\WinNotes\win_notes.exe',
      );

      expect(paths.dataDirectory, r'C:\Users\someone\AppData\Roaming\WinNotes');
    });

    test('an empty override is ignored rather than resolving to nowhere', () {
      // An env var set to "" is a thing that happens. Treating it as an override
      // would put the data directory at the empty string and every read would be a
      // silent miss.
      for (final blank in ['', '   ', '\t']) {
        final paths = AppPaths.resolve(
          reported: r'C:\real\WinNotes',
          executablePath: r'C:\app\win_notes.exe',
          environment: {AppPaths.overrideVariable: blank},
        );
        expect(
          paths.dataDirectory,
          r'C:\real\WinNotes',
          reason: 'a blank "$blank" must not become the data directory',
        );
      }
    });
  });

  group('with an override set, it uses that', () {
    test('an absolute path wins over the reported one', () {
      final paths = AppPaths.resolve(
        reported: r'C:\Users\someone\AppData\Roaming\WinNotes',
        executablePath: r'C:\app\win_notes.exe',
        environment: {
          AppPaths.overrideVariable: r'C:\Users\someone\AppData\Local\Temp\wn-verify',
        },
      );

      expect(
        paths.dataDirectory,
        r'C:\Users\someone\AppData\Local\Temp\wn-verify',
      );
      // And every derived file follows, which is the whole point: notes, settings,
      // widget state and selection all live under it.
      expect(
        paths.notesFile,
        r'C:\Users\someone\AppData\Local\Temp\wn-verify\notes.json',
      );
      expect(
        paths.settingsFile,
        r'C:\Users\someone\AppData\Local\Temp\wn-verify\settings.json',
      );
    });

    test('surrounding whitespace is trimmed, because a shell adds it', () {
      final paths = AppPaths.resolve(
        reported: r'C:\real\WinNotes',
        executablePath: r'C:\app\win_notes.exe',
        environment: {AppPaths.overrideVariable: '  C:\\temp\\wn  '},
      );

      expect(paths.dataDirectory, r'C:\temp\wn');
    });

    test('the real profile is not named anywhere in the result', () {
      // The assertion that would have caught the actual bug. Not "the override is
      // used" — that was true before, for every file, while the app still created
      // the real directory. What matters is that the real path is absent.
      final paths = AppPaths.resolve(
        reported: r'C:\Users\someone\AppData\Roaming\WinNotes',
        executablePath: r'C:\app\win_notes.exe',
        environment: {AppPaths.overrideVariable: r'C:\temp\wn'},
      );

      for (final file in [
        paths.notesFile,
        paths.settingsFile,
        paths.widgetStateFile,
        paths.selectionFile,
        paths.defaultStorageDirectory,
      ]) {
        expect(
          file,
          isNot(contains(r'AppData\Roaming\WinNotes')),
          reason: '$file still points into the real profile',
        );
      }
    });
  });

  group('a bad override is refused rather than half-honoured', () {
    test('a relative path is refused', () {
      // It would resolve against the runner's working directory, which is not
      // anywhere the caller chose.
      expect(
        () => AppPaths.resolve(
          reported: r'C:\real\WinNotes',
          executablePath: r'C:\app\win_notes.exe',
          environment: {AppPaths.overrideVariable: r'temp\wn'},
        ),
        throwsArgumentError,
      );
    });

    test('a path with .. is refused', () {
      // `..\` walks out of whatever was intended, which is how an override becomes
      // the one thing it promised not to be.
      expect(
        () => AppPaths.resolve(
          reported: r'C:\real\WinNotes',
          executablePath: r'C:\app\win_notes.exe',
          environment: {
            AppPaths.overrideVariable: r'C:\Users\someone\AppData\Roaming\WinNotes\..\..',
          },
        ),
        throwsArgumentError,
      );
    });

    test('a lone drive letter is refused', () {
      expect(
        () => AppPaths.resolve(
          reported: r'C:\real\WinNotes',
          executablePath: r'C:\app\win_notes.exe',
          environment: {AppPaths.overrideVariable: 'C:'},
        ),
        throwsArgumentError,
      );
    });

    test('the error names the variable, so the message is actionable', () {
      Object? caught;
      try {
        AppPaths.resolve(
          reported: r'C:\real\WinNotes',
          executablePath: r'C:\app\win_notes.exe',
          environment: {AppPaths.overrideVariable: 'relative'},
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(
        '$caught',
        contains(AppPaths.overrideVariable),
        reason: 'an operator seeing this at startup should be able to tell which '
            'variable is wrong without reading the source',
      );
    });
  });

  group('the file names are unchanged by any of this', () {
    test('the four files and the default storage directory are what they were', () {
      final paths = AppPaths(
        dataDirectory: r'C:\d',
        executablePath: r'C:\app\win_notes.exe',
      );

      expect(paths.notesFile, r'C:\d\notes.json');
      expect(paths.settingsFile, r'C:\d\settings.json');
      expect(paths.widgetStateFile, r'C:\d\widget_state.json');
      expect(paths.selectionFile, r'C:\d\selection.json');
      expect(paths.defaultStorageDirectory, r'C:\d');
    });
  });
}