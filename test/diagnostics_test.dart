/// The diagnostic dump: one snapshot, on demand, of the state that answers
/// "nothing happens".
///
/// The property that matters most is that it carries no note content, because
/// this file is written to be pasted into a public issue. The rest is that it
/// says *which* of the four profile files is unreadable, since that is the
/// question a "nothing happens" report is usually asking.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:win_notes/core/platform/shell_channel.dart';
import 'package:win_notes/core/utils/app_paths.dart';
import 'package:win_notes/core/utils/diagnostics.dart';

void main() {
  // The method channel is mocked, so the binding has to exist before `setUp`
  // reaches for it. `ensureInitialized` is idempotent.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('wn_diagnostics');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      ShellChannel.methodChannel,
      (MethodCall call) async =>
          <String, Object>{'left': 1548, 'top': 12, 'width': 360, 'height': 420},
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ShellChannel.methodChannel, null);
    if (temp.existsSync()) {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // A temp folder, not a failure.
      }
    }
  });

  AppPaths paths() => AppPaths(
        dataDirectory: temp.path,
        executablePath: r'C:\app\win_notes.exe',
      );

  LaunchInfo launch({String autostartCommand = '', bool autostartEnabled = false}) =>
      TestHarnessLaunch.launch(
        paths: paths(),
        autostartCommand: autostartCommand,
        autostartEnabled: autostartEnabled,
      );

  Diagnostics diagnostics({LaunchInfo? info}) =>
      Diagnostics(ShellChannel(), paths(), info ?? launch());

  group('a dump describes the profile without quoting it', () {
    test('it says a corrupt notes file is corrupt, not what was in it', () async {
      File('${temp.path}\\notes.json').writeAsStringSync('{ this is not json');

      final Map<String, dynamic> dump = await diagnostics().collect();
      final Map<String, dynamic> notes =
          (dump['profile']! as Map<String, dynamic>)['files']! as Map<String, dynamic>;
      final Map<String, dynamic> described = notes['notes']! as Map<String, dynamic>;

      expect(described['parses'], isFalse,
          reason: 'this is the answer a "nothing happens" report needs, and it '
              'needs no content to give it');
      expect(described['bytes'], isNotNull, reason: 'size still helps triage');
    });

    test('a dump carries no note text', () async {
      // The test that must never be relaxed: this file gets pasted publicly.
      File('${temp.path}\\notes.json').writeAsStringSync(
        '[{"id":"a","title":"Dentist Tuesday","body":"bring the referral letter"}]',
      );
      File('${temp.path}\\settings.json').writeAsStringSync(
        '{"accentPalette":"indigo","widgetOpacity":88}',
      );

      final String target = '${temp.path}\\dump.json';
      await diagnostics().writeTo(target);

      final String body = File(target).readAsStringSync();
      expect(body, isNot(contains('Dentist')));
      expect(body, isNot(contains('referral letter')));
      expect(body, isNot(contains('indigo')),
          reason: 'a palette name is harmless but the habit is what matters: '
              'nothing from the files is quoted into the dump');
      expect(body, contains('parses'), reason: 'the verdicts are the point');
    });

    test('a missing file is reported as missing rather than omitted', () async {
      final Map<String, dynamic> dump = await diagnostics().collect();
      final Map<String, dynamic> notes =
          (dump['profile']! as Map<String, dynamic>)['files']! as Map<String, dynamic>;

      expect((notes['settings']! as Map<String, dynamic>)['exists'], isFalse,
          reason: 'an absent key reads as "nobody looked", and "we looked and '
              'it is not there" is a different and more useful fact');
    });
  });

  group('the autostart half, which is why this exists', () {
    // These drive the **real** registry, because that is the thing the field is
    // for: `autostartCommand` is what the app *would write*, computed from its
    // own executable path, so a registry value pointing at a deleted install
    // reads as fine against it. Reading the entry back is the whole behaviour.
    //
    // The value is restored in `tearDown` whichever test ran, and the previous
    // one is captured first - a test suite that leaves an autostart entry
    // pointing at a temp file is worse than no test.
    String? savedEntry;

    setUp(() => savedEntry = _readRunEntry());
    tearDown(() => _writeRunEntry(savedEntry));

    test('an entry pointing at nothing is reported as pointing at nothing',
        () async {
      _writeRunEntry(r'"C:\nowhere\win_notes.exe" --widget');

      final Map<String, dynamic> runner =
          (await diagnostics(info: launch(autostartEnabled: true)).collect())['runner']!
              as Map<String, dynamic>;

      expect(runner['autostartEnabled'], isTrue,
          reason: 'the setting is on, which is the half that looks fine');
      expect(runner['autostartTargetExists'], isFalse,
          reason: 'an entry pointing at nothing fails silently at the next '
              'login, and this is the one line that says so');
      expect(runner['autostartRegistryEntry'], contains('nowhere'),
          reason: 'and the entry itself is in the dump, because "the registry '
              'disagrees with the app" is only visible if both are');
    });

    test('the app\'s own intent is reported separately from the registry', () async {
      _writeRunEntry(r'"C:\nowhere\win_notes.exe" --widget');

      final Map<String, dynamic> runner =
          (await diagnostics(info: launch(autostartEnabled: true)).collect())['runner']!
              as Map<String, dynamic>;

      expect(runner['autostartCommand'], isNot(contains('nowhere')),
          reason: 'autostartCommand is what the app would write, from its own '
              'exe path - confusing it with the registry value is the bug this '
              'row exists to catch');
    });

    test('a real target is recognised through the quotes and the flag', () async {
      final File exe = File('${temp.path}\\win_notes.exe')
        ..writeAsBytesSync(<int>[0x4D, 0x5A]);
      _writeRunEntry('"${exe.path}" --widget');

      final Map<String, dynamic> runner =
          (await diagnostics(info: launch(autostartEnabled: true)).collect())['runner']!
              as Map<String, dynamic>;

      expect(runner['autostartTargetExists'], isTrue,
          reason: 'a quoted path with a trailing flag is the only form Windows '
              'writes, so it is the only form that has to parse');
    });

    test('no entry at all is not a failure', () async {
      _writeRunEntry(null);

      final Map<String, dynamic> runner =
          (await diagnostics(info: launch(autostartEnabled: false)).collect())['runner']!
              as Map<String, dynamic>;

      expect(runner['autostartEnabled'], isFalse);
      expect(runner['autostartRegistryEntry'], isNull,
          reason: 'absent is reported as absent rather than as an empty string');
      expect(runner['autostartTargetExists'], isFalse);
    });
  });

  test('the dump is valid JSON a person can paste', () async {
    File('${temp.path}\\notes.json').writeAsStringSync('[]');
    final String target = '${temp.path}\\dump.json';

    await diagnostics().writeTo(target);

    final Map<String, dynamic> decoded =
        jsonDecode(File(target).readAsStringSync()) as Map<String, dynamic>;
    expect(decoded.keys, containsAll(<String>['writtenAt', 'profile', 'runner']));
  });

  test('an unwritable destination does not raise, and writes nothing', () async {
    // A dump that fails is the one moment it must not: the failure is usually
    // the thing being diagnosed. Asserting the file is *absent* as well as the
    // absence of a throw, because the catch below would swallow a real write
    // failure too and "no exception" alone proves nothing.
    await diagnostics().writeTo(r'Z:\not\a\drive\dump.json');

    expect(File(r'Z:\not\a\drive\dump.json').existsSync(), isFalse,
        reason: 'the point is that it did not raise; nothing claims it landed');
  });

  test('it adds no platform method', () {
    // `LaunchInfo` already carries monitors, the autostart entry and both paths
    // from `bootstrap`, and `widget.getBounds` gives live geometry. A dump that
    // needed a 29th method would be a contract change (`AGENTS.md` §0.10) buying
    // nothing, so the registry is asserted to still be 28 long elsewhere; this
    // is the reason, kept next to the code that could have broken it.
    expect(File('lib/core/platform/shell_channel.dart').readAsStringSync(),
        isNot(contains('widget.diagnostics')));
  });
}

/// The `WinNotes` value under `HKCU\…\Run`, or null when it is absent.
///
/// The same `reg query` the production code uses, so the test parses the real
/// output format rather than a shape invented here.
String? _readRunEntry() {
  final ProcessResult result = Process.runSync(
    'reg',
    <String>['query', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run', '/v', 'WinNotes'],
  );
  if (result.exitCode != 0) return null;
  for (final String line in (result.stdout as String).split('\n')) {
    if (!line.trimLeft().startsWith('WinNotes')) continue;
    final List<String> parts = line.trim().split(RegExp(r'\s{2,}')); // ignore: prefer_const_constructors
    return parts.length >= 3 ? parts.sublist(2).join(' ').trim() : null;
  }
  return null;
}

/// Sets or clears the entry. `null` deletes it.
///
/// `reg delete` refuses a value that is not there, so the absence case is
/// guarded rather than left to fail the test.
void _writeRunEntry(String? value) {
  const String key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  if (value == null) {
    if (_readRunEntry() == null) return;
    Process.runSync('reg', <String>['delete', key, '/v', 'WinNotes', '/f']);
    return;
  }
  Process.runSync(
    'reg',
    <String>['add', key, '/v', 'WinNotes', '/t', 'REG_SZ', '/d', value, '/f'],
  );
}

/// Builds a `LaunchInfo` without pulling in the whole provider harness.
class TestHarnessLaunch {
  static LaunchInfo launch({
    required AppPaths paths,
    required String autostartCommand,
    required bool autostartEnabled,
  }) {
    return LaunchInfo(
      role: 'editor',
      launchMode: 'manual',
      isWidgetSurface: false,
      dataDirectory: paths.dataDirectory,
      executablePath: paths.executablePath,
      isSystemDark: false,
      animationsEnabled: true,
      highContrast: false,
      acrylicSupported: false,
      buildNumber: 0,
      monitors: const <MonitorInfo>[
        MonitorInfo(
          id: 0,
          left: 0,
          top: 0,
          width: 1920,
          height: 1080,
          scale: 1.0,
        ),
      ],
      autostartEnabled: autostartEnabled,
      autostartCommand: autostartCommand,
      defaultWidgetBounds:
          const NativeBounds(left: 0, top: 0, width: 360, height: 480),
    );
  }
}
