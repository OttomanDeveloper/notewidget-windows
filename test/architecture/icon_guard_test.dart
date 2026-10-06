/// The icon Windows draws, in every place it reads one from.
///
/// Four independent places decide what a person sees, and a build can look entirely
/// healthy while one of them is empty:
///
///   1. `setup.exe` itself       - `SetupIconFile`
///   2. the running exe          - `Runner.rc` compiling `app_icon.ico`
///   3. the Start Menu shortcut  - `[Icons]` `IconFilename`
///   4. Settings > Apps          - `DisplayIcon` in the uninstall registry key, which
///                                  only `UninstallDisplayIcon` writes
///
/// (4) was the one missing, and it is the only one that produces no symptom anywhere
/// else. The installer compiled, installed, made a working shortcut, and left the Apps
/// list with a name and nothing beside it.
///
/// A guard, because the failure is silent: nothing errors, nothing warns, the artifact
/// is the right size, and the icon is simply absent from one list of places it could
/// have been in. `tool/verify/verify_icons.ps1` checks the same facts against a real
/// install and a real build; this checks the source, so it runs in CI without Inno
/// Setup installed and without a build present.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

void main() {
  final SourceTree tree = SourceTree();

  group('the icon file itself', () {
    test('app_icon.ico is where the runner expects it', () {
      // One path, named once. The .rc, the .iss and this test all read it, so there is
      // no second copy to fall out of step - which is the alternative, and it is what
      // "the installer has a different logo to the app" looks like when it happens.
      expect(
        tree.exists('windows/runner/resources/app_icon.ico'),
        isTrue,
        reason: 'Runner.rc compiles this file into the exe, and the installer names '
            'it. If it has moved, both of those point at nothing.',
      );
    });

    test('the generated copy in assets is the same file, byte for byte', () {
      // `assets/brand/winnotes.ico` is what the README and the website show. It is
      // generated from the same SVG, but "generated from the same source" is a claim
      // about a script; this is a fact about two files.
      expect(
        tree.exists('assets/brand/winnotes.ico'),
        isTrue,
        reason: 'precondition: there is an assets copy to compare against',
      );
      expect(
        tree.readBytes('assets/brand/winnotes.ico'),
        tree.readBytes('windows/runner/resources/app_icon.ico'),
        reason: 'The app and the assets folder have drifted. Run '
            'tool/brand/generate_assets.ps1, or delete the assets copy and have the '
            'README reference the runner one.',
      );
    });

    test('it carries the sizes Windows asks for', () {
      // A file that is structurally valid but missing 16x16 looks correct in Explorer
      // and draws as a blank square in a Start Menu list. 16, 32, 48 and 256 are what
      // Inno's own documentation asks a setup icon to include; 64 is what the shell
      // reaches for in between.
      final List<int> bytes = tree.readBytes('windows/runner/resources/app_icon.ico');
      expect(bytes.length, greaterThan(6), reason: 'precondition: a real .ico');

      final int count = bytes[4] | (bytes[5] << 8);
      expect(count, greaterThan(0), reason: 'precondition: it declares frames');

      final Set<int> sizes = <int>{};
      for (int i = 0; i < count; i++) {
        final int o = 6 + i * 16;
        if (o + 16 > bytes.length) break;
        // 0 means 256 in an .ico directory entry - the field is one byte wide, so the
        // encoding is "0 or it did not fit", which is worth spelling out rather than
        // reading 256 sizes as a missing 0.
        sizes.add(bytes[o] == 0 ? 256 : bytes[o]);
      }

      const List<int> wanted = <int>[16, 32, 48, 64, 256];
      expect(
        sizes,
        containsAll(wanted),
        reason: 'missing ${wanted.where((int s) => !sizes.contains(s)).toList()}'
            ' - a valid .ico without these draws blank where it matters most',
      );
    });
  });

  group('the executable', () {
    test('Runner.rc compiles the icon in', () {
      // Doubled backslashes on purpose. `Runner.rc` is a Windows resource script and
      // writes `resources\\app_icon.ico`; a single-backslash regex finds nothing and
      // reports an icon that is there as missing. That is this repo's most repeated
      // trap, and it has now caught the verifier as well as the verifier's author.
      final String rc = tree.read('windows/runner/Runner.rc');
      expect(
        rc,
        matches(RegExp(r'ICON\s+"resources\\\\app_icon\.ico"')),
        reason: 'Without this line the exe has no icon of its own, so anything that '
            'resolves an icon from the binary - the taskbar, Alt+Tab, the Apps list '
            'when DisplayIcon points at the exe - has nothing to draw.',
      );
    });
  });

  group('the installer', () {
    late String iss;

    setUpAll(() {
      iss = tree.read('installer/winnotes.iss');
    });

    test('the setup program has the project icon, not the default', () {
      expect(
        iss,
        matches(RegExp(r'^SetupIconFile=', multiLine: true)),
        reason: "Without this, setup.exe carries Inno Setup's own icon. That is the "
            'generic logo in Explorer, in Downloads, and on the taskbar while it '
            'installs - while the application it installs has a real one.',
      );
    });

    test('the Apps list has an icon', () {
      // The whole of the reported bug. Inno writes no `DisplayIcon` into the uninstall
      // key without this directive, and Windows 11's Settings > Apps has nothing to
      // draw - no warning, no fallback, just the name.
      expect(
        iss,
        matches(RegExp(r'^UninstallDisplayIcon=', multiLine: true)),
        reason: '`UninstallDisplayIcon` is what puts `DisplayIcon` in the uninstall '
            'registry key, which is where Windows 11 reads the Apps-list icon from. '
            'A shortcut icon and an Apps-list icon come from two different places, '
            'and only the shortcut was configured.',
      );
    });

    test('and it is not written under a name that does not exist', () {
      // `AppIconFile` is the name this looks like it should have. ISCC rejects it as
      // an unrecognised directive, which is a loud failure - but only if someone
      // compiles. Leaving it in the file as a plausible-looking line would read as
      // done without ever being tested.
      expect(
        iss,
        isNot(matches(RegExp(r'^\s*AppIconFile=', multiLine: true))),
        reason: 'AppIconFile is not an Inno Setup directive. Use '
            'UninstallDisplayIcon. If this is failing, the name was carried over from '
            'a different installer system.',
      );
    });

    test('the icon it names is actually installed', () {
      // `UninstallDisplayIcon` records a path, it does not copy anything. If the file
      // is not installed, the registry points at a file that is not there - the same
      // blank result as before, reached from a different direction, and it would also
      // surface at uninstall time.
      expect(
        iss,
        matches(RegExp(r'Source:\s*"\{#AppIcon\}"\s*;\s*DestDir:\s*"\{app\}"')),
        reason: 'The .ico must be installed into {app}, because both the shortcut and '
            "the uninstall key name a path that has to resolve on somebody's machine.",
      );
    });

    test('both application shortcuts name the icon', () {
      // Two shortcuts: the Start Menu entry and the optional desktop one. Naming the
      // installed file means they keep the logo even if the exe's embedded resource is
      // ever lost, instead of degrading to a blank square at the same moment.
      final int named =
          RegExp(r'^Name:.*IconFilename:', multiLine: true).allMatches(iss).length;
      final int shortcuts =
          RegExp(r'^Name:\s*"\{', multiLine: true).allMatches(iss).length;
      expect(
        shortcuts,
        greaterThanOrEqualTo(2),
        reason: 'precondition: there are application shortcuts to check',
      );
      expect(
        named,
        equals(2),
        reason: 'Both application shortcuts should name the icon file. The uninstall '
            'shortcut legitimately does not - it points at the uninstaller.',
      );
    });

    test('the icon path points at the runner, not at a second copy', () {
      // A relative path in Inno Setup is relative to the .iss file. One define, read
      // from the runner, is what makes the installer and the running app the same
      // drawing rather than two files that currently agree.
      expect(
        iss,
        matches(RegExp(
          r'#define AppIcon "\.\.\\windows\\runner\\resources\\app_icon\.ico"',
        )),
        reason: 'One define, read from the runner, so the installer cannot name a '
            'different drawing from the one the app runs with.',
      );
    });
  });

  group('the verifier', () {
    test('the PowerShell probe checks the same directive this guard does', () {
      // The probe checks a real install and a real build; this file checks the
      // source. Both existing is the point - the source check runs in CI with no Inno
      // Setup, and the build check is what would catch Inno Setup quietly changing
      // what a directive means.
      expect(
        tree.exists('tool/verify/verify_icons.ps1'),
        isTrue,
      );
      expect(
        tree.read('tool/verify/verify_icons.ps1'),
        matches(RegExp(r'UninstallDisplayIcon')),
        reason: 'precondition: the probe names the same directive, so a rename in one '
            'shows up as a failure in the other rather than as two quietly '
            'disagreeing checks.',
      );
    });
  });
}