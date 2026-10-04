import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/src/core/atomic_json_file.dart';
import 'package:win_notes/src/data/settings.dart';
import 'package:win_notes/src/data/settings_repository.dart';
import 'package:win_notes/src/platform/shell_channel.dart';
import 'package:win_notes/src/state/settings_controller.dart';
import 'package:win_notes/src/ui/palette.dart';
import 'package:win_notes/src/ui/settings/settings_dialog.dart';
import 'package:win_notes/src/ui/theme.dart';

/// Keys the picker publishes, so a test aims at a swatch without reverse-
/// engineering the wrap order.
Key swatchKey(String id) => ValueKey('settings.palette.$id');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the palette list', () {
    test('ids are unique, so one setting can name one palette', () {
      final ids = winNotesPalettes.map((p) => p.id).toSet();
      expect(ids, hasLength(winNotesPalettes.length),
          reason: 'a duplicate id would make one swatch unselectable');
    });

    test('labels are unique too, or two swatches read the same', () {
      final labels = winNotesPalettes.map((p) => p.label).toSet();
      expect(labels, hasLength(winNotesPalettes.length));
    });

    test('the default is first, because an absent field means "the default"', () {
      // settings.json from before this feature has no palette field, and a
      // missing field resolves to index zero. Reordering this list would change
      // what an existing install sees, with nothing to mark the change.
      expect(winNotesPalettes.first.id, 'coral');
      expect(paletteById(null), same(winNotesPalettes.first));
    });

    test('the default palette is still the brand', () {
      // Frozen. The logo, the artwork and the release screenshots are all built
      // from these two values, so a palette may add colours but the default
      // cannot quietly become something else.
      final brand = winNotesPalettes.first;
      expect(brand.accent, const Color(0xFFE8551D));
      expect(brand.accentDark, const Color(0xFFFF7A45));
    });

    test('every dark accent is lighter than its light one', () {
      // A saturated colour on a dark background loses its edge, so the dark
      // variant is always a lighter shade of the same hue. If this ever fails,
      // the swatch shows a colour the user will not actually get in dark mode.
      for (final palette in winNotesPalettes) {
        expect(
          palette.accentDark.computeLuminance(),
          greaterThan(palette.accent.computeLuminance()),
          reason: '${palette.id}: the dark accent must be the lighter one',
        );
      }
    });
  });

  group('legibility, which is the whole reason for a palette', () {
    // A free colour picker cannot make this guarantee; a hand-checked list can,
    // and this is what stops a future palette being added without checking it.
    // The threshold is WCAG AA for non-body text (3:1). The accent is used as a
    // thin card bar, a tick stroke and a 2px focus ring, all of which are
    // graphical objects rather than paragraphs of prose.
    const minimum = 3.0;

    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final palette in winNotesPalettes) {
      group(palette.label, () {
        test('the accent reads against the light widget surface', () {
          final surface = palette.surfaces(Brightness.light).surface;
          expect(
            contrast(palette.accent, surface),
            greaterThan(minimum),
            reason: '${palette.id} accent on its own light surface',
          );
        });

        test('the accent reads against the dark widget surface', () {
          final surface = palette.surfaces(Brightness.dark).surface;
          expect(
            contrast(palette.accentDark, surface),
            greaterThan(minimum),
            reason: '${palette.id} accent on its own dark surface',
          );
        });

        test('the tick drawn inside the accent reads against it', () {
          // The completion toggle puts a tick on the accent fill, and that tick
          // has to be visible or a finished task looks unfinished.
          final onAccent = readableOn(palette.accent);
          expect(contrast(onAccent, palette.accent), greaterThan(minimum),
              reason: '${palette.id}: tick on the swatch');
          expect(contrast(readableOn(palette.accentDark), palette.accentDark),
              greaterThan(minimum));
        });

        test('body text reads against the editor background', () {
          for (final brightness in Brightness.values) {
            final surfaces = palette.surfaces(brightness);
            expect(
              contrast(surfaces.onSurface, surfaces.scaffold),
              greaterThan(4.5),
              reason: '${palette.id} in $brightness: note bodies are prose, so '
                  'this one is held to the stricter 4.5',
            );
            expect(
              contrast(surfaces.onSurfaceVariant, surfaces.scaffold),
              greaterThan(3.0),
              reason: '${palette.id} in $brightness: list previews and hints',
            );
          }
        });

        test('the dialog is a different surface from the editor it sits on', () {
          // The one place two of these surfaces genuinely appear together: a
          // dialog is drawn over the editor. They are close - Material leans on
          // elevation for that - so the check is that the dialog is at least a
          // distinct tone rather than identical, which is what would happen if a
          // palette mapped both to the same container.
          //
          // What this deliberately does NOT check: the widget surface against the
          // editor background. Those are separate windows and are never side by
          // side, so a difference between them is a difference nobody sees. An
          // earlier version of this test asserted one anyway and failed, which
          // was the test being wrong rather than the palettes.
          for (final brightness in Brightness.values) {
            final surfaces = palette.surfaces(brightness);
            expect(surfaces.dialog, isNot(surfaces.scaffold),
                reason: '${palette.id} in $brightness: a dialog painted '
                    'exactly the editor colour has no edge at all');
          }
        });
      });
    }

    test('readableOn actually flips with brightness', () {
      expect(readableOn(const Color(0xFFFFFFFF)), isNot(const Color(0xFFFFFFFF)));
      expect(
        readableOn(const Color(0xFF000000)),
        isNot(readableOn(const Color(0xFFFFFFFF))),
      );
    });
  });

  group('paletteById', () {
    test('resolves a known id', () {
      expect(paletteById('teal').id, 'teal');
    });

    test('falls back to the default for an unknown id', () {
      // A settings.json hand-edited, or written by a build whose palette has
      // since been removed, must still open. Refusing to start over a colour
      // name would be absurd.
      expect(paletteById('chartreuse'), same(winNotesPalettes.first));
      expect(paletteById(''), same(winNotesPalettes.first));
    });
  });

  group('the setting survives a round trip', () {
    late Directory temp;
    late SettingsRepository repository;
    late ShellChannel shell;

    setUp(() {
      shell = ShellChannel();
      temp = Directory.systemTemp.createTempSync('wn_palette');
      repository = SettingsRepository(
        AtomicJsonFile('${temp.path}\\settings.json'),
        shell,
      );
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('omitted from the file entirely when never chosen', () async {
      // Same rule as completedAt: a profile that never touched the setting
      // stays byte-identical to one written before the setting existed.
      final json = WinNotesSettings.defaults.toJson();

      expect(json.containsKey('accentPalette'), isFalse,
          reason: 'an empty choice should not appear in the file at all');
      await repository.saveNow(WinNotesSettings.defaults);
      final written = File('${temp.path}\\settings.json').readAsStringSync();
      expect(written.contains('accentPalette'), isFalse);
    });

    test('written once chosen, and read back', () async {
      await repository.saveNow(
        WinNotesSettings.defaults.copyWith(accentPalette: 'moss'),
      );
      final loaded = await repository.load();
      expect(loaded.accentPalette, 'moss');
    });

    test('an unknown value in the file is kept, not silently rewritten', () {
      // Resolving it at the edge means one place decides what an unrecognised
      // name means. Rewriting it here would fight the user who typed it.
      final loaded = WinNotesSettings.fromJson({'accentPalette': 'chartreuse'});
      expect(loaded.accentPalette, 'chartreuse');
      expect(paletteById(loaded.accentPalette).id, 'coral');
    });

    test('a file with no palette field loads as never chosen', () {
      final loaded = WinNotesSettings.fromJson({'themeMode': 'dark'});
      expect(loaded.accentPalette, isEmpty);
      expect(paletteById(loaded.accentPalette), same(winNotesPalettes.first));
    });

    test('the palette participates in equality, or it would never save', () {
      final a = WinNotesSettings.defaults.copyWith(accentPalette: 'teal');
      final b = WinNotesSettings.defaults.copyWith(accentPalette: 'rose');

      expect(a == b, isFalse,
          reason: 'SettingsController skips the write when nothing changed');
      expect(a == a.copyWith(), isTrue);
      expect(a.hashCode, isNot(b.hashCode));
    });

    test('copyWith replaces only the palette', () {
      final a = WinNotesSettings.defaults.copyWith(accentPalette: 'teal');
      final b = a.copyWith(widgetOpacity: 50);
      expect(b.accentPalette, 'teal');
      expect(b.widgetOpacity, 50);
    });

    test('a change lands on disk through the debounce, not just in memory',
        () async {
      // In a plain test rather than a testWidgets, on purpose. Under a fake
      // clock the debounce timer fires but the real write it starts never
      // completes, so `flush()` finds nothing pending and the file is never
      // created - which looks exactly like the setting not being saved. Real
      // elapsed time is the only honest way to test a debounce.
      repository.save(
        WinNotesSettings.defaults.copyWith(accentPalette: 'amber'),
      );
      expect(File('${temp.path}\\settings.json').existsSync(), isFalse,
          reason: 'precondition: nothing on disk yet');

      // Polled rather than slept on. A fixed delay has to guess a margin over
      // the 250ms debounce, and this suite runs 271 tests in parallel on a
      // machine that is busy exactly when the guess is tight - which made this
      // fail about one run in three. What is claimed here is "the debounce
      // lands it eventually", so that is what gets waited on.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      final target = File('${temp.path}\\settings.json');
      while (DateTime.now().isBefore(deadline)) {
        if (target.existsSync() &&
            target.readAsStringSync().contains('"accentPalette": "amber"')) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      final written = target.readAsStringSync();
      expect(written, contains('"accentPalette": "amber"'),
          reason: 'the debounced write should land well within 10 seconds');
      expect((await repository.load()).accentPalette, 'amber');
    });
  });

  group('the picker in Settings', () {
    late Directory temp;
    late SettingsController controller;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.winnotes/shell'),
        (call) async => null,
      );
      temp = Directory.systemTemp.createTempSync('wn_palette_ui');
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    Future<void> pumpDialog(WidgetTester tester) async {
      final shell = ShellChannel();
      // Under runAsync, and not inline: loading the settings file is real file
      // I/O, and a widget test's fake clock never advances the real event loop.
      // Awaiting it directly hangs forever - the same trap as the debounced
      // writes, and for the same reason. See docs/testing_pattern.md §4.
      await tester.runAsync(() async {
        controller = SettingsController(
          repository: SettingsRepository(
            AtomicJsonFile('${temp.path}\\settings.json'),
            shell,
          ),
          shell: shell,
        );
        await controller.load(animationsEnabled: true, acrylicSupported: true);
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildWinNotesTheme(
            brightness: Brightness.light,
            highContrast: false,
          ),
          home: Scaffold(
            body: SettingsDialog(
              controller: controller,
              shell: shell,
              defaultDataDirectory: temp.path,
            ),
          ),
        ),
      );
      // pumpAndSettle rather than pump: the swatch grows over 140ms when the
      // selection moves, and a test that asserted before that finished would be
      // asserting the previous animation frame.
      await tester.pumpAndSettle();
    }

    testWidgets('every palette has a swatch', (tester) async {
      await pumpDialog(tester);

      for (final palette in winNotesPalettes) {
        expect(find.byKey(swatchKey(palette.id)), findsOneWidget,
            reason: '${palette.id} has no swatch');
      }
    });

    testWidgets('the swatches wrap instead of running off the row',
        (tester) async {
      // Nine swatches at 30px plus gaps is wider than the settings panel. If
      // they overflowed rather than wrapping, the last ones would be clipped and
      // unreachable - and a colour you cannot see is a colour you cannot pick.
      await pumpDialog(tester);

      final tops = <double>{};
      for (final palette in winNotesPalettes) {
        final box = tester.getRect(find.byKey(swatchKey(palette.id)));
        expect(box.width, 30.0);
        expect(box.height, 30.0);
        expect(
          box.right,
          lessThanOrEqualTo(tester.getSize(find.byType(SettingsDialog)).width),
          reason: '${palette.id} is clipped by the panel',
        );
        tops.add(box.top);
      }
      expect(tops.length, greaterThan(1),
          reason: 'all nine on one row means the row is too narrow to hold them');
    });

    testWidgets('tapping a swatch chooses that palette', (tester) async {
      await pumpDialog(tester);

      await tester.tap(find.byKey(swatchKey('teal')));
      await tester.pumpAndSettle();

      expect(controller.settings.accentPalette, 'teal');
    });

    testWidgets('the chosen name is written out, not left to be guessed',
        (tester) async {
      // The row shows colours, which is the point - but a colour list with no
      // name is unreadable to anyone who cannot distinguish them.
      await pumpDialog(tester);
      expect(find.text('Coral'), findsOneWidget);

      await tester.tap(find.byKey(swatchKey('rose')));
      await tester.pumpAndSettle();

      expect(find.text('Rose'), findsOneWidget);
      expect(find.text('Coral'), findsNothing);
    });

    testWidgets('exactly one swatch claims to be selected', (tester) async {
      await pumpDialog(tester);

      List<WinNotesPalette> selectedSwatches() => [
            for (final palette in winNotesPalettes)
              if (tester
                  .widget<Semantics>(find.byKey(swatchKey(palette.id)))
                  .properties
                  .selected ==
                  true)
                palette,
          ];

      expect(selectedSwatches(), hasLength(1));
      expect(selectedSwatches().single.id, 'coral');

      await tester.tap(find.byKey(swatchKey('moss')));
      await tester.pumpAndSettle();

      // Scoped to the swatches rather than counting every selected Semantics in
      // the dialog: the Theme SegmentedButton legitimately marks its own segment
      // selected, and a dialog-wide count would be asserting about that too.
      expect(selectedSwatches(), hasLength(1));
      expect(selectedSwatches().single.id, 'moss');
    });
  });
}