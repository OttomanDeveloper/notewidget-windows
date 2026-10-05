/// The dependency graph. The only place a repository is built.
///
/// `docs/isolate_pattern.md` §3.1 exists because `EditorApp` and `WidgetApp` each
/// used to construct the same five things by hand, and the duplication had already
/// produced a live divergence: `_resolveBrightness` had forked into three copies
/// across the two files and they disagreed about what "system" brightness means
/// when Windows has not reported one yet.
///
/// Everything here is shared by both surfaces. Each isolate gets its own container
/// - `main()` runs in both - so the two never share an instance, which is the whole
/// point. What they share is this *declaration*, not its results.
///
/// **Controllers are not here.** Each one declares its own provider at the bottom
/// of its own file, so `settings_controller.dart` can reach `shellProvider` without
/// this file importing it back. The alternative - a central list of every provider -
/// reads tidily and creates an import cycle through three files, which is a worse
/// trade than finding a controller by its name.
///
/// Nothing here imports `ui/`. The theme provider is in `ui/theme_scope.dart` for
/// the same reason `AGENTS.md` §3 draws the arrows one way.
library;

import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';

import '../core/app_paths.dart';
import '../core/atomic_json_file.dart';
import '../data/notes_repository.dart';
import '../data/settings_repository.dart';
import '../platform/shell_channel.dart';

// --- Values that come from the runner ------------------------------------------
//
// Each is `throw UnimplementedError` rather than a default, because reading one
// without the root having overridden it is a wiring mistake, and a default would
// hide it as a null shell that fails somewhere less obvious. Each root overrides
// all three in a single `ProviderScope`. See `docs/isolate_pattern.md` §3.2.

final shellProvider = Provider<ShellChannel>((ref) {
  throw UnimplementedError(
    'shellProvider must be overridden at the root. Both surfaces get a real '
    'ShellChannel from main(); see docs/isolate_pattern.md 3.2.',
  );
});

final launchInfoProvider = Provider<LaunchInfo>((ref) {
  throw UnimplementedError(
    'launchInfoProvider must be overridden at the root with what bootstrap() '
    'returned. See docs/isolate_pattern.md 3.2.',
  );
});

final appPathsProvider = Provider<AppPaths>((ref) {
  throw UnimplementedError(
    'appPathsProvider must be overridden at the root. See '
    'docs/isolate_pattern.md 3.2.',
  );
});

// --- Repositories ---------------------------------------------------------------
//
// Plain classes over `AtomicJsonFile`, constructed here and read by the notifiers.
// The one-writer-per-file rule in `docs/storage_pattern.md` is unchanged by any of
// this; a repository knows nothing about which surface it is in.

/// `notes.json`. Written only by the editor surface.
final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  return NotesRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).notesFile),
  );
});

/// `settings.json`. Written only by the editor surface, watched by both.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).settingsFile),
    ref.watch(shellProvider),
  );
});

/// `selection.json`. The one file both surfaces write - it is a single value, and a
/// file is cheaper than a channel round trip.
final selectionRepositoryProvider = Provider<SelectionRepository>((ref) {
  return SelectionRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).selectionFile),
  );
});

/// `widget_state.json`. Written only by the widget surface.
final widgetStateRepositoryProvider = Provider<WidgetStateRepository>((ref) {
  return WidgetStateRepository(
    AtomicJsonFile(ref.watch(appPathsProvider).widgetStateFile),
  );
});

// --- Facts about this isolate ---------------------------------------------------

/// Which surface this isolate is drawing.
///
/// Not a global and not inferred: it comes from the same `LaunchInfo` that decided
/// which root widget `main()` ran, so the graph cannot disagree with the tree above
/// it.
final isWidgetSurfaceProvider = Provider<bool>((ref) {
  return ref.watch(launchInfoProvider).isWidgetSurface;
});

/// Whether Windows is currently in dark mode.
///
/// Seeded from `LaunchInfo.isSystemDark`, then kept live by the one
/// `WidgetsBindingObserver` in the app.
///
/// This exists because the two roots each registered their own observer and updated
/// a field in their own `State`, which is how the two came to disagree about the
/// theme - three copies of `_resolveBrightness`, two different answers.
/// `AGENTS.md` §4.7.
final systemBrightnessProvider =
    NotifierProvider<SystemBrightnessNotifier, Brightness>(
  SystemBrightnessNotifier.new,
);

class SystemBrightnessNotifier extends Notifier<Brightness> {
  @override
  Brightness build() {
    final seed = ref.read(launchInfoProvider).isSystemDark;
    return seed ? Brightness.dark : Brightness.light;
  }

  /// Called by the one `WidgetsBindingObserver` in the app.
  void report({required Brightness brightness}) {
    if (state == brightness) return;
    state = brightness;
  }
}