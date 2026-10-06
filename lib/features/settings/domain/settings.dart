import 'package:flutter/material.dart';

import './hotkey_binding.dart';

/// Everything in Settings, in four flat groups and no nesting. One value object,
/// so a change is whole-object replacement; [==] lets writes skip no-change updates.

class WinNotesSettings {
  WinNotesSettings({
    this.themeMode = ThemeMode.system,
    this.accentPalette = '',
    this.widgetOpacity = 92,
    this.acrylicEnabled = true,
    this.alwaysOnTop = true,
    this.widgetPositionLocked = false,
    this.autoStart = false,
    this.autoStartDelayMs = 1500,
    HotkeyBinding? editorHotkey,
    String storageDirectory = '',
    this.widgetDockedToEdge = true,
    String dockEdge = 'right',
    this.editorFontSize = 0,
    this.previewFontSize = 0,
  })  : editorHotkey = editorHotkey ?? HotkeyBinding.defaultBinding,
        storageDirectory = storageDirectory,
        dockEdge = dockEdge;

  static final WinNotesSettings defaults = WinNotesSettings();

  ThemeMode themeMode;

    /// Which colour palette, by id. Empty means "never chose one", so a future
    /// default change cannot pin old files; unvalidated here, resolved at the edge
    /// by `paletteById`.
  String accentPalette;

  /// Percentage, 30-100. A widget that is too solid sits on top of the work
  /// rather than beside it.
  int widgetOpacity;

  bool acrylicEnabled;
  bool alwaysOnTop;
  bool autoStart;

    /// Whether dragging the widget is refused. Off by default and opt-in: the
    /// lock shipped on once, and an immovable widget annoyed more than stray drags.
    /// Resizing is unaffected either way.
  bool widgetPositionLocked;

  /// Only ever applied to the autostart launch. Launching by hand shows the
  /// widget immediately.
  int autoStartDelayMs;

  final bool widgetDockedToEdge;

  HotkeyBinding editorHotkey;

  /// Empty means "the default app data folder".
  String storageDirectory;

  /// Which screen edge the widget parks against when docking is on.
  String dockEdge;

  /// Type size for the note source, in logical pixels. 0 is not a size: it means
  /// "as designed", so a file written before this setting existed needs no key
  /// to keep working and the editor looks exactly as it did.
  int editorFontSize;

  /// Type size for the rendered preview, same units and same 0.
  int previewFontSize;

  /// The sizes the sliders offer. 11 is still readable at 96 dpi; 24 is large
  /// without breaking the editor's two-pane layout on a short window.
  static const int minFontSize = 11;
  static const int maxFontSize = 24;

  /// A stored size outside the range is clamped rather than trusted, the same as
  /// [widgetOpacity]: a hand-edited file should not be able to render a note
  /// invisible or fill a pane.
  static int normaliseFontSize(int value) {
    if (value == 0) return 0;
    if (value < minFontSize) return minFontSize;
    if (value > maxFontSize) return maxFontSize;
    return value;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WinNotesSettings &&
          other.themeMode == themeMode &&
          other.accentPalette == accentPalette &&
          other.widgetOpacity == widgetOpacity &&
          other.acrylicEnabled == acrylicEnabled &&
          other.alwaysOnTop == alwaysOnTop &&
          other.widgetPositionLocked == widgetPositionLocked &&
          other.autoStart == autoStart &&
          other.autoStartDelayMs == autoStartDelayMs &&
          other.editorHotkey == editorHotkey &&
          other.storageDirectory == storageDirectory &&
          other.widgetDockedToEdge == widgetDockedToEdge &&
          other.dockEdge == dockEdge &&
          other.editorFontSize == editorFontSize &&
          other.previewFontSize == previewFontSize;

  @override
  int get hashCode => Object.hash(
        themeMode,
        accentPalette,
        widgetOpacity,
        acrylicEnabled,
        alwaysOnTop,
        widgetPositionLocked,
        autoStart,
        autoStartDelayMs,
        editorHotkey,
        storageDirectory,
        widgetDockedToEdge,
        dockEdge,
        editorFontSize,
        previewFontSize,
      );

  WinNotesSettings copyWith({
    ThemeMode? themeMode,
    String? accentPalette,
    int? widgetOpacity,
    bool? acrylicEnabled,
    bool? alwaysOnTop,
    bool? widgetPositionLocked,
    bool? autoStart,
    int? autoStartDelayMs,
    HotkeyBinding? editorHotkey,
    String? storageDirectory,
    bool? widgetDockedToEdge,
    String? dockEdge,
    int? editorFontSize,
    int? previewFontSize,
  }) =>
      WinNotesSettings(
        themeMode: themeMode ?? this.themeMode,
        accentPalette: accentPalette ?? this.accentPalette,
        widgetOpacity: widgetOpacity ?? this.widgetOpacity,
        acrylicEnabled: acrylicEnabled ?? this.acrylicEnabled,
        alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
        widgetPositionLocked: widgetPositionLocked ?? this.widgetPositionLocked,
        autoStart: autoStart ?? this.autoStart,
        autoStartDelayMs: autoStartDelayMs ?? this.autoStartDelayMs,
        editorHotkey: editorHotkey ?? this.editorHotkey,
        storageDirectory: storageDirectory ?? this.storageDirectory,
        widgetDockedToEdge: widgetDockedToEdge ?? this.widgetDockedToEdge,
        dockEdge: dockEdge ?? this.dockEdge,
        editorFontSize: editorFontSize ?? this.editorFontSize,
        previewFontSize: previewFontSize ?? this.previewFontSize,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'themeMode': themeMode.name,
        // Omitted rather than written as '' when unset, for the same reason
        // completedAt is: a file that never mentioned the setting stays
        // byte-identical to one written before the setting existed.
        if (accentPalette.isNotEmpty) 'accentPalette': accentPalette,
        'widgetOpacity': widgetOpacity,
        'acrylicEnabled': acrylicEnabled,
        'alwaysOnTop': alwaysOnTop,
        'widgetPositionLocked': widgetPositionLocked,
        'autoStart': autoStart,
        'autoStartDelayMs': autoStartDelayMs,
        'editorHotkey': editorHotkey.toJson(),
        'storageDirectory': storageDirectory,
        'widgetDockedToEdge': widgetDockedToEdge,
        'dockEdge': dockEdge,
        // Omitted when 0, for the same reason as accentPalette: 0 means
        // "as designed", and writing it would put a key in files that had
        // never heard of the setting.
        if (editorFontSize != 0) 'editorFontSize': editorFontSize,
        if (previewFontSize != 0) 'previewFontSize': previewFontSize,
      };

  static WinNotesSettings fromJson(Map<String, dynamic> json) {
    final WinNotesSettings fallback = defaults;
    T pick<T>(String key, T fallbackValue) {
      final value = json[key];
      return value is T ? value : fallbackValue;
    }

    final themeName = json['themeMode'];
    final ThemeMode theme = ThemeMode.values.firstWhere(
      (ThemeMode m) => m.name == themeName,
      orElse: () => fallback.themeMode,
    );

    final hotkeyJson = json['editorHotkey'];
    final int delay = pick<int>('autoStartDelayMs', fallback.autoStartDelayMs);

    return WinNotesSettings(
      themeMode: theme,
      accentPalette: pick<String>('accentPalette', fallback.accentPalette),
      // Clamped rather than trusted: a hand-edited file should not be able to
      // produce a fully invisible widget.
      widgetOpacity:
          pick<int>('widgetOpacity', fallback.widgetOpacity).clamp(30, 100),
      acrylicEnabled: pick<bool>('acrylicEnabled', fallback.acrylicEnabled),
      alwaysOnTop: pick<bool>('alwaysOnTop', fallback.alwaysOnTop),
      widgetPositionLocked:
          pick<bool>('widgetPositionLocked', fallback.widgetPositionLocked),
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
      editorFontSize: normaliseFontSize(
        pick<int>('editorFontSize', fallback.editorFontSize),
      ),
      previewFontSize: normaliseFontSize(
        pick<int>('previewFontSize', fallback.previewFontSize),
      ),
    );
  }
}