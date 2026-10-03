import 'package:flutter/material.dart';

import 'hotkey_binding.dart';

/// Everything in Settings, in four flat groups and no nesting.
///
/// Held as one value object so a change is a whole-object replacement rather
/// than a set of individual dirty flags. [==] compares every field, which is
/// what lets SettingsController decide "did anything actually change?" before
/// writing the file and re-registering the hotkey.
///

class WinNotesSettings {
  WinNotesSettings({
    this.themeMode = ThemeMode.system,
    this.widgetOpacity = 92,
    this.acrylicEnabled = true,
    this.alwaysOnTop = true,
    this.autoStart = false,
    this.autoStartDelayMs = 1500,
    HotkeyBinding? editorHotkey,
    String storageDirectory = '',
    this.widgetDockedToEdge = true,
    String dockEdge = 'right',
  })  : editorHotkey = editorHotkey ?? HotkeyBinding.defaultBinding,
        storageDirectory = storageDirectory,
        dockEdge = dockEdge;

  static final WinNotesSettings defaults = WinNotesSettings();

  ThemeMode themeMode;

  /// Percentage, 30-100. A widget that is too solid sits on top of the work
  /// rather than beside it.
  int widgetOpacity;

  bool acrylicEnabled;
  bool alwaysOnTop;
  bool autoStart;

  /// Only ever applied to the autostart launch. Launching by hand shows the
  /// widget immediately.
  int autoStartDelayMs;

  final bool widgetDockedToEdge;

  HotkeyBinding editorHotkey;

  /// Empty means "the default app data folder".
  String storageDirectory;

  /// Which screen edge the widget parks against when docking is on.
  String dockEdge;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WinNotesSettings &&
          other.themeMode == themeMode &&
          other.widgetOpacity == widgetOpacity &&
          other.acrylicEnabled == acrylicEnabled &&
          other.alwaysOnTop == alwaysOnTop &&
          other.autoStart == autoStart &&
          other.autoStartDelayMs == autoStartDelayMs &&
          other.editorHotkey == editorHotkey &&
          other.storageDirectory == storageDirectory &&
          other.widgetDockedToEdge == widgetDockedToEdge &&
          other.dockEdge == dockEdge;

  @override
  int get hashCode => Object.hash(
        themeMode,
        widgetOpacity,
        acrylicEnabled,
        alwaysOnTop,
        autoStart,
        autoStartDelayMs,
        editorHotkey,
        storageDirectory,
        widgetDockedToEdge,
        dockEdge,
      );

  WinNotesSettings copyWith({
    ThemeMode? themeMode,
    int? widgetOpacity,
    bool? acrylicEnabled,
    bool? alwaysOnTop,
    bool? autoStart,
    int? autoStartDelayMs,
    HotkeyBinding? editorHotkey,
    String? storageDirectory,
    bool? widgetDockedToEdge,
    String? dockEdge,
  }) =>
      WinNotesSettings(
        themeMode: themeMode ?? this.themeMode,
        widgetOpacity: widgetOpacity ?? this.widgetOpacity,
        acrylicEnabled: acrylicEnabled ?? this.acrylicEnabled,
        alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
        autoStart: autoStart ?? this.autoStart,
        autoStartDelayMs: autoStartDelayMs ?? this.autoStartDelayMs,
        editorHotkey: editorHotkey ?? this.editorHotkey,
        storageDirectory: storageDirectory ?? this.storageDirectory,
        widgetDockedToEdge: widgetDockedToEdge ?? this.widgetDockedToEdge,
        dockEdge: dockEdge ?? this.dockEdge,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'themeMode': themeMode.name,
        'widgetOpacity': widgetOpacity,
        'acrylicEnabled': acrylicEnabled,
        'alwaysOnTop': alwaysOnTop,
        'autoStart': autoStart,
        'autoStartDelayMs': autoStartDelayMs,
        'editorHotkey': editorHotkey.toJson(),
        'storageDirectory': storageDirectory,
        'widgetDockedToEdge': widgetDockedToEdge,
        'dockEdge': dockEdge,
      };

  static WinNotesSettings fromJson(Map<String, dynamic> json) {
    final fallback = defaults;
    T pick<T>(String key, T fallbackValue) {
      final value = json[key];
      return value is T ? value : fallbackValue;
    }

    final themeName = json['themeMode'];
    final theme = ThemeMode.values.firstWhere(
      (m) => m.name == themeName,
      orElse: () => fallback.themeMode,
    );

    final hotkeyJson = json['editorHotkey'];
    final delay = pick<int>('autoStartDelayMs', fallback.autoStartDelayMs);

    return WinNotesSettings(
      themeMode: theme,
      // Clamped rather than trusted: a hand-edited file should not be able to
      // produce a fully invisible widget.
      widgetOpacity:
          pick<int>('widgetOpacity', fallback.widgetOpacity).clamp(30, 100),
      acrylicEnabled: pick<bool>('acrylicEnabled', fallback.acrylicEnabled),
      alwaysOnTop: pick<bool>('alwaysOnTop', fallback.alwaysOnTop),
      autoStart: pick<bool>('autoStart', fallback.autoStart),
      autoStartDelayMs: delay.clamp(0, 60000),
      editorHotkey: hotkeyJson is Map<String, dynamic>
          ? HotkeyBinding.fromJson(hotkeyJson, fallback: fallback.editorHotkey)
          : fallback.editorHotkey,
      storageDirectory:
          pick<String>('storageDirectory', fallback.storageDirectory),
      widgetDockedToEdge:
          pick<bool>('widgetDockedToEdge', fallback.widgetDockedToEdge),
      dockEdge: pick<String>('dockEdge', fallback.dockEdge),
    );
  }
}