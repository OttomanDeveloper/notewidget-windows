import 'dart:async';

import 'package:flutter/material.dart';

import '../data/settings.dart';
import '../data/settings_repository.dart';
import '../platform/shell_channel.dart';

/// App-wide settings, shared by both surfaces.
///
/// The widget surface reads these to decide how to draw itself and how to ask
/// the runner to configure the window. The editor surface is the only writer.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsRepository repository,
    required ShellChannel shell,
    bool watchExternal = false,
  })  : _repository = repository,
        _shell = shell {
    if (watchExternal) repository.watch(_onExternalChange);
  }

  final SettingsRepository _repository;
  final ShellChannel _shell;

  WinNotesSettings _settings = SettingsRepository.defaults;
  bool _loaded = false;

  /// Set when Windows reports animation is off, so nothing slides or fades.
  bool _animationsEnabled = true;
  bool _acrylicSupported = false;
  String? _hotkeyProblem;

  WinNotesSettings get settings => _settings;
  bool get isLoaded => _loaded;
  bool get animationsEnabled => _animationsEnabled;
  bool get acrylicSupported => _acrylicSupported;

  /// Non-null when the last hotkey registration failed, carrying the reason so
  /// the dialog can say "another app already uses Ctrl+Alt+N" instead of
  /// silently doing nothing.
  String? get hotkeyProblem => _hotkeyProblem;

  ThemeMode get themeMode => _settings.themeMode;

  Future<void> load({bool? animationsEnabled, bool? acrylicSupported}) async {
    if (animationsEnabled != null) _animationsEnabled = animationsEnabled;
    if (acrylicSupported != null) _acrylicSupported = acrylicSupported;
    _settings = await _repository.load();
    _loaded = true;
    notifyListeners();
  }

  void _onExternalChange() {
    unawaited(_repository.load().then((next) {
      if (next == _settings) return;
      _settings = next;
      notifyListeners();
    }));
  }

  /// Applies a change, persists it, and pushes whatever the runner owns.
  Future<void> update(WinNotesSettings Function(WinNotesSettings) mutate) async {
    final next = mutate(_settings);
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    _repository.save(next);

    if (next.editorHotkey != _settings.editorHotkey ||
        next.autoStart != _settings.autoStart) {
      await _syncPlatform();
    }
  }

  /// Applies the hotkey and the autostart entry to the runner.
  ///
  /// Called both when settings change and at startup, so a missing registry
  /// entry or a hotkey someone else has taken is corrected on every launch
  /// rather than only when the toggle is used.
  Future<void> syncPlatform() => _syncPlatform();

  Future<void> _syncPlatform() async {
    final binding = _settings.editorHotkey;
    final registration = await _shell.registerHotkey(
      modifiers: binding.modifiers,
      key: binding.key,
      enabled: binding.enabled,
    );
    _hotkeyProblem = switch (registration.failure) {
      HotkeyFailure.none => null,
      HotkeyFailure.alreadyRegistered =>
        'Another app is already using ${binding.display}.',
      HotkeyFailure.invalid => 'That combination cannot be used.',
      HotkeyFailure.failed => 'Windows would not accept that combination.',
    };

    // Keep the registry and the setting in step. If the entry was removed by
    // hand, the toggle re-adds it; if autostart is off, the entry is removed.
    final registryState = await _repository.currentAutoStartState();
    if (registryState != _settings.autoStart) {
      await _repository.applyAutoStart(_settings.autoStart);
    }
    notifyListeners();
  }

  Future<void> setAutoStart(bool enabled) async {
    final ok = await _repository.applyAutoStart(enabled);
    if (!ok) {
      _hotkeyProblem = 'Windows would not let the startup entry be changed.';
      notifyListeners();
      return;
    }
    await update((s) => s.copyWith(autoStart: enabled));
  }

  /// Resolves where notes actually live, honouring a custom location.
  String resolveStorageDirectory(String defaultDirectory) {
    final configured = _settings.storageDirectory.trim();
    if (configured.isEmpty) return defaultDirectory;
    return configured;
  }

  Future<void> flush() => _repository.flush();

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }
}