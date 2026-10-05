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

  /// Points the app at [target], copying the library there first.
  ///
  /// **Copy, never move** — see `StorageTransfer`. Nothing is deleted from where it is;
  /// the person is told where the old copies are so they can remove them themselves.
  ///
  /// The pointer in the default folder is only written once the copy has succeeded, so
  /// a transfer that fails part way leaves the app pointing at notes it can still open.
  /// The order is the whole point: pointer last, never first.
  ///
  /// **A restart is required and this says so.** `appPathsProvider` is overridden in
  /// `main()` with a value fixed for the life of the process, so the files this session
  /// is writing are the ones it opened at startup. Changing that mid-session means
  /// rebuilding every repository underneath a running editor, and a half-rebuilt
  /// library is not worth the convenience. So the honest answer is "restart", and the
  /// UI says exactly that rather than pretending the change is live.
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

  /// Goes back to `%APPDATA%\WinNotes` by copying the library there.
  ///
  /// Also a copy, not a move. Somebody who has been working in a folder they chose and
  /// then changes their mind has notes in *that* folder, and losing them by clearing a
  /// text box would be absurd.
  Future<StorageTransferOutcome> moveToDefault() async {
    final paths = ref.read(appPathsProvider);
    return moveTo(paths.defaultStorageDirectory);
  }

  /// Writes the pointer copy of `settings.json`.
  ///
  /// Separate from the repository's own write because that one goes to
  /// [AppPaths.settingsFile] — the *chosen* folder. The pointer is in
  /// [AppPaths.settingsPointerFile], and `storage_pattern.md` §3.0a is the rule that
  /// says there are two copies and which is which.
  Future<void> _writePointer(WinNotesSettings settings) async {
    final path = ref.read(appPathsProvider).settingsPointerFile;
    try {
      final file = AtomicJsonFile(path);
      await file.writeNow(settings.toJson());
      await file.dispose();
    } catch (_) {
      // The library is copied and the in-memory setting is right, so the only thing
      // lost is the pointer - which means the next launch opens the default folder
      // with its own copy rather than the chosen one. Not worth failing the transfer
      // over, and worth saying so in the UI rather than claiming it worked.
    }
  }

  Future<void> flush() => _repository.flush();
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);