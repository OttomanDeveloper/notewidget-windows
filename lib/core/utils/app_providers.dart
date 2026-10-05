/// The shared dependency graph: the runner channel, launch facts and paths.
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
/// No `autoDispose` anywhere in this app, deliberately: every provider is scoped
/// to the isolate lifetime (runner channel, launch facts, paths, repositories,
/// controllers, theme), and nothing here is screen-scoped. Ephemeral UI state
/// stays in `ValueNotifier`s with listeners instead - see `no_set_state_test`.
/// If a screen-scoped provider ever appears, it gets `autoDispose` and the reason
/// it must not outlive its screen.
///
/// **Repositories are not built here.** Each feature builds its own in its
/// `presentation/providers/` dir, so this file never imports feature code.
/// Controllers declare their own providers at the bottom of their own files.
/// The theme providers live with the settings they derive from, in the settings
/// feature, for the same one-way reason.
library;

import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';

import './app_paths.dart';
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
    // Watched, not read: a re-resolved launch must reseed rather than stick.
    final seed = ref.watch(launchInfoProvider).isSystemDark;
    return seed ? Brightness.dark : Brightness.light;
  }

  /// Called by the one `WidgetsBindingObserver` in the app.
  void report({required Brightness brightness}) {
    if (state == brightness) return;
    state = brightness;
  }
}