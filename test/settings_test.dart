import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/features/settings/domain/hotkey_binding.dart';
import 'package:win_notes/features/settings/domain/settings.dart';
import 'package:win_notes/features/widget/data/widget_state_repository.dart';

void main() {
  group('HotkeyBinding', () {
    test('the default is Ctrl+Alt+N', () {
      expect(HotkeyBinding.defaultBinding.display, 'Ctrl+Alt+N');
    });

    test('modifiers display in a fixed order, whatever order they were stored',
        () {
      const HotkeyBinding a = HotkeyBinding(modifiers: <String>['win', 'shift', 'alt', 'ctrl'], key: 'K');
      const HotkeyBinding b = HotkeyBinding(modifiers: <String>['ctrl', 'alt', 'shift', 'win'], key: 'K');
      expect(a.display, b.display);
      expect(a.display, 'Ctrl+Alt+Shift+Win+K');
    });

    test('a single character key is upper-cased for display', () {
      expect(const HotkeyBinding(modifiers: <String>['ctrl'], key: 'n').display, 'Ctrl+N');
    });

    test('named keys read as words', () {
      expect(
        const HotkeyBinding(modifiers: <String>['ctrl'], key: 'PageUp').display,
        'Ctrl+PgUp',
      );
      expect(
        const HotkeyBinding(modifiers: <String>['alt'], key: 'F5').display,
        'Alt+F5',
      );
    });

    test('a combination Windows would reject is not registrable', () {
      expect(const HotkeyBinding(modifiers: <String>[], key: 'N').isRegistrable, isFalse);
      // Win alone is reserved by the shell for Start and the window shortcuts.
      expect(const HotkeyBinding(modifiers: <String>['win'], key: 'N').isRegistrable, isFalse);
      expect(const HotkeyBinding(modifiers: <String>['ctrl'], key: '').isRegistrable, isFalse);
      expect(
        const HotkeyBinding(modifiers: <String>['ctrl'], key: 'N', enabled: false).isRegistrable,
        isFalse,
      );
    });

    test('Ctrl+Alt+N is registrable', () {
      expect(HotkeyBinding.defaultBinding.isRegistrable, isTrue);
    });

    test('an unusable stored combination falls back to the default', () {
      // A hand-edited file could contain anything; falling back to something
      // that registers beats showing a hotkey that silently does nothing.
      final HotkeyBinding parsed = HotkeyBinding.fromJson(
        <String, dynamic>{'modifiers': <String>[], 'key': 'N'},
        fallback: HotkeyBinding.defaultBinding,
      );
      expect(parsed.display, 'Ctrl+Alt+N');
    });

    test('equality ignores modifier ordering', () {
      const HotkeyBinding a = HotkeyBinding(modifiers: <String>['ctrl', 'alt'], key: 'N');
      const HotkeyBinding b = HotkeyBinding(modifiers: <String>['alt', 'ctrl'], key: 'N');
      // Ordering is cosmetic, but equality here drives "did this change?",
      // so it is compared exactly as stored.
      expect(a == b, isFalse);
      expect(a == a.copyWith(), isTrue);
      expect(a.hashCode, a.copyWith().hashCode);
    });

    test('survives a JSON round trip', () {
      const HotkeyBinding original = HotkeyBinding(modifiers: <String>['ctrl', 'shift'], key: 'F2');
      expect(HotkeyBinding.fromJson(original.toJson()), original);
    });
  });

  group('WinNotesSettings', () {
    test('defaults are the conservative ones', () {
      final WinNotesSettings s = WinNotesSettings();
      expect(s.themeMode, ThemeMode.system,
          reason: 'the default is System so the widget matches Windows');
      expect(s.acrylicEnabled, isTrue);
      expect(s.autoStart, isFalse,
          reason: 'nothing starts without being asked for');
      expect(s.storageDirectory, '');
      expect(s.autoStartDelayMs, greaterThan(0));
    });

    test('round trips through JSON', () {
      final WinNotesSettings original = WinNotesSettings(
        themeMode: ThemeMode.dark,
        widgetOpacity: 55,
        acrylicEnabled: false,
        alwaysOnTop: false,
        widgetPositionLocked: false,
        autoStart: true,
        autoStartDelayMs: 4000,
        editorHotkey: const HotkeyBinding(modifiers: <String>['ctrl', 'win'], key: 'Space'),
        storageDirectory: r'D:\Notes',
      );
      final WinNotesSettings restored = WinNotesSettings.fromJson(original.toJson());
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.widgetOpacity, 55);
      expect(restored.acrylicEnabled, isFalse);
      expect(restored.alwaysOnTop, isFalse);
      expect(restored.widgetPositionLocked, isFalse);
      expect(restored.autoStart, isTrue);
      expect(restored.autoStartDelayMs, 4000);
      expect(restored.editorHotkey.display, 'Ctrl+Win+Space');
      expect(restored.storageDirectory, r'D:\Notes');
    });

    test('an empty document yields the defaults', () {
      expect(WinNotesSettings.fromJson(const <String, dynamic>{}).themeMode, ThemeMode.system);
    });

    test('the widget is draggable by default', () {
      // Locking was tried first and reverted. Being unable to move the widget
      // at all was a bigger annoyance than the accidental drags it prevented,
      // and the only way out was a switch in Settings nobody would find.
      expect(WinNotesSettings.defaults.widgetPositionLocked, isFalse);
    });

    test('a settings file written before the lock existed comes back draggable',
        () {
      // Absence must not silently pin someone's widget, which is the same trap
      // in the opposite direction.
      final Map<String, dynamic> legacy = WinNotesSettings.defaults.toJson()
        ..remove('widgetPositionLocked');
      expect(WinNotesSettings.fromJson(legacy).widgetPositionLocked, isFalse);
    });

    test('the lock participates in equality', () {
      // SettingsController compares whole objects to decide whether to write
      // and re-push to the runner, so a field left out of == would mean the
      // switch does nothing. Stated in both directions rather than leaning on
      // the default, so flipping the default cannot quietly break this.
      final WinNotesSettings unlocked = WinNotesSettings.defaults;
      final WinNotesSettings locked = unlocked.copyWith(widgetPositionLocked: true);
      expect(locked, isNot(unlocked));
      expect(locked.copyWith(widgetPositionLocked: false), unlocked);
    });

    test('a hand-edited opacity cannot make the widget invisible', () {
      // Clamped rather than trusted: nobody should be able to end up with a
      // widget they cannot see and no obvious way to get it back.
      expect(WinNotesSettings.fromJson(<String, dynamic>{'widgetOpacity': 0}).widgetOpacity, 30);
      expect(WinNotesSettings.fromJson(<String, dynamic>{'widgetOpacity': 500}).widgetOpacity, 100);
      expect(WinNotesSettings.fromJson(<String, dynamic>{'widgetOpacity': -20}).widgetOpacity, 30);
    });

    test('a hand-edited startup delay is bounded', () {
      expect(WinNotesSettings.fromJson(<String, dynamic>{'autoStartDelayMs': -5}).autoStartDelayMs, 0);
      expect(
        WinNotesSettings.fromJson(<String, dynamic>{'autoStartDelayMs': 99999999}).autoStartDelayMs,
        60000,
      );
    });

    test('an unknown theme name falls back to System', () {
      expect(WinNotesSettings.fromJson(<String, dynamic>{'themeMode': 'neon'}).themeMode, ThemeMode.system);
    });

    test('wrongly typed fields are ignored rather than throwing', () {
      final WinNotesSettings restored = WinNotesSettings.fromJson(<String, dynamic>{
        'themeMode': 42,
        'widgetOpacity': 'lots',
        'autoStart': 'yes',
        'autoStartDelayMs': <int>[1],
        'editorHotkey': 'ctrl+n',
      });
      expect(restored.widgetOpacity, 92);
      expect(restored.autoStart, isFalse);
      expect(restored.editorHotkey.display, 'Ctrl+Alt+N');
    });

    test('copyWith changes only what it is given', () {
      final WinNotesSettings s = WinNotesSettings();
      final WinNotesSettings updated = s.copyWith(themeMode: ThemeMode.light);
      expect(updated.themeMode, ThemeMode.light);
      expect(updated.acrylicEnabled, s.acrylicEnabled);
      expect(updated.widgetOpacity, s.widgetOpacity);
    });

    test('two identical settings compare equal, so no needless write', () {
      // SettingsController.update compares old with new and returns early when
      // they match. If equality were identity, dragging the opacity slider would
      // rewrite settings.json and re-register Ctrl+Alt+N on every frame.
      expect(WinNotesSettings(), WinNotesSettings());
      expect(WinNotesSettings(), WinNotesSettings().copyWith());
      expect(
        WinNotesSettings(),
        isNot(WinNotesSettings().copyWith(themeMode: ThemeMode.dark)),
        reason: 'a real change must not compare equal',
      );
      expect(
        WinNotesSettings(),
        isNot(WinNotesSettings().copyWith(widgetOpacity: 30)),
      );
      expect(
        WinNotesSettings(),
        isNot(WinNotesSettings().copyWith(
          editorHotkey: const HotkeyBinding(modifiers: <String>['ctrl'], key: 'K'),
        )),
      );
    });
  });

  group('WidgetWindowState', () {
    test('reports whether a geometry has been recorded', () {
      expect(WidgetWindowState.empty.hasGeometry, isFalse);
      final WidgetWindowState placed = WidgetWindowState.empty.copyWith(left: 10, top: 20, width: 300, height: 400);
      expect(placed.hasGeometry, isTrue);
      // Half a geometry is not a geometry.
      expect(WidgetWindowState.empty.copyWith(left: 10, top: 20).hasGeometry, isFalse);
    });

    test('round trips through JSON', () {
      const WidgetWindowState original = WidgetWindowState(
        left: 1548, top: 12, width: 360, height: 420,
        monitorId: 1, dockEdge: 'right', scrollOffset: 84.5,
      );
      final WidgetWindowState restored = WidgetWindowState.fromJson(original.toJson());
      expect(restored.left, 1548);
      expect(restored.width, 360);
      expect(restored.monitorId, 1);
      expect(restored.dockEdge, 'right');
      expect(restored.scrollOffset, 84.5);
    });

    test('missing fields load as nulls rather than zero', () {
      final WidgetWindowState restored = WidgetWindowState.fromJson(const <String, dynamic>{});
      expect(restored.left, isNull);
      expect(restored.hasGeometry, isFalse);
      expect(restored.scrollOffset, 0);
    });

    test('clearDockEdge removes it instead of keeping the old value', () {
      final WidgetWindowState withEdge = WidgetWindowState.empty.copyWith(dockEdge: 'left');
      expect(withEdge.dockEdge, 'left');
      expect(withEdge.copyWith(clearDockEdge: true).dockEdge, isNull);
    });
  });
}