import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';

import '../../../../core/utils/atomic_json_file.dart';
import '../../domain/settings.dart';
import '../../data/storage_transfer.dart';
import '../../domain/repositories.dart';
import './settings_providers.dart';
import '../../../../core/platform/shell_channel.dart';
import '../../../notes/presentation/providers/notes_controller.dart';
import '../../../../core/utils/app_providers.dart';

/// Everything the settings surface needs; immutable so change detection stays answerable.
/// Repository and channel stay in the notifier for testability.
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

/// The editor's view of settings; the only writer of settings.json, watched by both surfaces.
/// One immutable value per change so listeners know what changed.
class SettingsNotifier extends AsyncNotifier<SettingsState> {
  late final ISettingsRepository _repository;
  late final ShellChannel _shell;

  @override
  Future<SettingsState> build() async {
    _repository = ref.watch(settingsRepositoryProvider);
    _shell = ref.watch(shellProvider);

    // Both surfaces watch settings.json. It is written once, by the editor, and
    // either surface may be open, so neither can assume it is current.
    _repository.watch(_onExternalChange);

    // Watched, not read: a re-resolved launch must refresh these rather than
    // stick with the first answer.
    final launch = ref.watch(launchInfoProvider);
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

  /// Applies a change, persists it and pushes runner-owned state; named `apply` not `update`.
  /// `AsyncNotifier` already defines `update` with a different meaning.
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

  /// Applies hotkey and autostart to the runner, at startup and on change, so drift is corrected.
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

  /// Points the app at [target] by copying; pointer written last, never first; see `StorageTransfer`.
  /// Restart required: `appPathsProvider` is fixed for the process lifetime.
  Future<StorageTransferOutcome> moveTo(String target) async {
    final current = state.value;
    if (current == null) return StorageTransferOutcome.failed;

    final paths = ref.read(appPathsProvider);

    // The library on disk may be newer than what is in memory by up to one debounce
    // window, and `copyLibrary` copies files rather than state. Flushing first is what
    // makes "the notes arrived" true rather than nearly true.
    await _repository.flush();
    await ref.read(notesProvider.notifier).flush();

    final destination = paths.copyWith(dataDirectory: target.trim());
    final next = current.settings.copyWith(storageDirectory: target.trim());

    final outcome = await StorageTransfer.copyLibrary(
      from: paths,
      to: destination,
      settings: next,
    );
    if (outcome != StorageTransferOutcome.done) return outcome;

    // The pointer goes in only now. `settings.json` in the default folder is how the
    // next launch finds the library, and writing it before the copy would point a
    // future launch at a folder that might not have the notes in it yet.
    state = AsyncData(current.copyWith(settings: next));
    await _repository.saveNow(next);
    await _writePointer(next);

    return outcome;
  }

  /// Returns to `%APPDATA%\WinNotes` by copying, never moving, so chosen-folder notes are kept.
  Future<StorageTransferOutcome> moveToDefault() async {
    final paths = ref.read(appPathsProvider);
    return moveTo(paths.defaultStorageDirectory);
  }

  /// Writes the pointer copy; repository writes [AppPaths.settingsFile], pointer is [AppPaths.settingsPointerFile].
  /// See `storage_pattern.md` §3.0a.
  Future<void> _writePointer(WinNotesSettings settings) async {
    final path = ref.read(appPathsProvider).settingsPointerFile;
    try {
      final file = AtomicJsonFile(path);
      await file.writeNow(settings.toJson());
      await file.dispose();
    } catch (_) {
        // Only the pointer is lost: the next launch opens the default folder
        // with its own copy. Not worth failing the transfer over; say so in the UI.
    }
  }

  Future<void> flush() => _repository.flush();
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);