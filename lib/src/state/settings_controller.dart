import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';

import '../data/settings.dart';
import '../data/settings_repository.dart';
import '../platform/shell_channel.dart';
import 'providers.dart';

/// Everything the settings surface needs to draw and act.
///
/// Immutable, because a Riverpod `Notifier` rebuilds when its state changes and a
/// mutable box would make "did anything actually change" unanswerable. The
/// repository and the channel are *not* here: they are dependencies of the notifier,
/// reached with `ref`, and keeping them out is what lets a test replace one without
/// constructing a whole object graph.
class SettingsState {
  const SettingsState({
    required this.settings,
    this.animationsEnabled = true,
    this.acrylicSupported = false,
    this.hotkeyProblem,
  });

  final WinNotesSettings settings;

  /// Set from what the runner reported at launch, so nothing slides or fades when
  /// Windows says animation is off.
  final bool animationsEnabled;

  /// Whether this build can do the acrylic backdrop at all, which is a property of
  /// the machine rather than a setting.
  final bool acrylicSupported;

  /// Non-null when the last hotkey registration failed, carrying the reason so the
  /// dialog can say "another app already uses Ctrl+Alt+N" instead of silently doing
  /// nothing.
  final String? hotkeyProblem;

  SettingsState copyWith({
    WinNotesSettings? settings,
    bool? animationsEnabled,
    bool? acrylicSupported,
    String? hotkeyProblem,
    bool clearHotkeyProblem = false,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      acrylicSupported: acrylicSupported ?? this.acrylicSupported,
      hotkeyProblem:
          clearHotkeyProblem ? null : (hotkeyProblem ?? this.hotkeyProblem),
    );
  }

  ThemeMode get themeMode => settings.themeMode;
}

/// The editor surface's view of app-wide settings. The only writer of
/// settings.json; the widget surface reads and watches it.
///
/// Was `SettingsController extends ChangeNotifier` until 2026-10-05. The rewrite is
/// not churn for its own sake: `hotkeyProblem` used to be written from inside
/// `_syncPlatform` and published by a bare `notifyListeners()` that attributed
/// itself to nothing, so a listener could not tell which part of the settings had
/// changed and had to rebuild wholesale. One immutable value per change answers that.
class SettingsNotifier extends AsyncNotifier<SettingsState> {
  late final SettingsRepository _repository;
  late final ShellChannel _shell;

  @override
  Future<SettingsState> build() async {
    _repository = ref.watch(settingsRepositoryProvider);
    _shell = ref.watch(shellProvider);

    // Both surfaces watch settings.json. It is written once, by the editor, and
    // either surface may be open, so neither can assume it is current.
    _repository.watch(_onExternalChange);

    final launch = ref.read(launchInfoProvider);
    final loaded = await _repository.load();
    return SettingsState(
      settings: loaded,
      animationsEnabled: launch.animationsEnabled,
      acrylicSupported: launch.acrylicSupported,
    );
  }

  /// The current settings, or null before the first load completes.
  SettingsState? get current => state.value;

  void _onExternalChange() {
    unawaited(_repository.load().then((next) {
      final current = state.value;
      if (current == null || next == current.settings) return;
      state = AsyncData(current.copyWith(settings: next));
    }));
  }

  /// Applies a change, persists it, and pushes whatever the runner owns.
  ///
  /// Named `apply` rather than `update` because `AsyncNotifier` already defines an
  /// `update`, with a completely different meaning. Overriding it to do this would
  /// make every call site lie about what it does, and the compiler would not
  /// complain - the signature is close enough to be tempting and the semantics are
  /// not.
  Future<void> apply(WinNotesSettings Function(WinNotesSettings) mutate) async {
    final current = state.value;
    if (current == null) return;
    final next = mutate(current.settings);
    if (next == current.settings) return;
    state = AsyncData(current.copyWith(settings: next));
    _repository.save(next);

    if (next.editorHotkey != current.settings.editorHotkey ||
        next.autoStart != current.settings.autoStart) {
      await syncPlatform();
    }
  }

  /// Applies the hotkey and the autostart entry to the runner.
  ///
  /// Called both when settings change and at startup, so a missing registry entry or
  /// a hotkey someone else has taken is corrected on every launch rather than only
  /// when the toggle is used.
  Future<void> syncPlatform() async {
    final current = state.value;
    if (current == null) return;

    final binding = current.settings.editorHotkey;
    final registration = await _shell.registerHotkey(
      modifiers: binding.modifiers,
      key: binding.key,
      enabled: binding.enabled,
    );

    final problem = switch (registration.failure) {
      HotkeyFailure.none => null,
      HotkeyFailure.alreadyRegistered =>
        'Another app is already using ${binding.display}.',
      HotkeyFailure.invalid => 'That combination cannot be used.',
      HotkeyFailure.failed => 'Windows would not accept that combination.',
    };

    // Keep the registry and the setting in step. If the entry was removed by hand,
    // the toggle re-adds it; if autostart is off, the entry is removed.
    final registryState = await _repository.currentAutoStartState();
    if (registryState != current.settings.autoStart) {
      await _repository.applyAutoStart(enabled: current.settings.autoStart);
    }

    state = AsyncData(
      current.copyWith(
        hotkeyProblem: problem,
        clearHotkeyProblem: problem == null,
      ),
    );
  }

  Future<void> setAutoStart({required bool enabled}) async {
    final current = state.value;
    if (current == null) return;
    final ok = await _repository.applyAutoStart(enabled: enabled);
    if (!ok) {
      state = AsyncData(
        current.copyWith(
          hotkeyProblem: 'Windows would not let the startup entry be changed.',
        ),
      );
      return;
    }
    await apply((s) => s.copyWith(autoStart: enabled));
  }

  /// Resolves where notes actually live, honouring a custom location.
  String resolveStorageDirectory(String defaultDirectory) {
    final configured = state.value?.settings.storageDirectory.trim() ?? '';
    if (configured.isEmpty) return defaultDirectory;
    return configured;
  }

  Future<void> flush() => _repository.flush();
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);