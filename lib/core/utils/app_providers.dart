/// The shared dependency graph: runner channel, launch facts and paths.
/// Both surfaces share this declaration, not its results [see
/// `docs/isolate_pattern.md` §3.1]; repos/theme live in features, no `autoDispose`.
library;

import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';

import './app_paths.dart';
import '../platform/shell_channel.dart';

// --- Values that come from the runner ------------------------------------------
// `throw UnimplementedError`, not a default: reading one without the root's
// override is a wiring mistake a default would hide [see `docs/isolate_pattern.md` §3.2].

final Provider<ShellChannel> shellProvider = Provider<ShellChannel>((Ref ref) {
  throw UnimplementedError(
    'shellProvider must be overridden at the root. Both surfaces get a real '
    'ShellChannel from main(); see docs/isolate_pattern.md 3.2.',
  );
});

final Provider<LaunchInfo> launchInfoProvider = Provider<LaunchInfo>((Ref ref) {
  throw UnimplementedError(
    'launchInfoProvider must be overridden at the root with what bootstrap() '
    'returned. See docs/isolate_pattern.md 3.2.',
  );
});

final Provider<AppPaths> appPathsProvider = Provider<AppPaths>((Ref ref) {
  throw UnimplementedError(
    'appPathsProvider must be overridden at the root. See '
    'docs/isolate_pattern.md 3.2.',
  );
});

// --- Facts about this isolate ---------------------------------------------------

/// Which surface this isolate is drawing.
/// From the same `LaunchInfo` that picked the root widget, so the graph
/// cannot disagree with the tree above it.
final Provider<bool> isWidgetSurfaceProvider = Provider<bool>((Ref ref) {
  return ref.watch(launchInfoProvider).isWidgetSurface;
});

/// Whether Windows is currently in dark mode.
/// Seeded from `LaunchInfo.isSystemDark`, kept live by the one
/// `WidgetsBindingObserver` in the app.
final NotifierProvider<SystemBrightnessNotifier, Brightness> systemBrightnessProvider =
    NotifierProvider<SystemBrightnessNotifier, Brightness>(
  SystemBrightnessNotifier.new,
);

class SystemBrightnessNotifier extends Notifier<Brightness> {
  @override
  Brightness build() {
    // Watched, not read: a re-resolved launch must reseed rather than stick.
    final bool seed = ref.watch(launchInfoProvider).isSystemDark;
    return seed ? Brightness.dark : Brightness.light;
  }

  /// Called by the one `WidgetsBindingObserver` in the app.
  void report({required Brightness brightness}) {
    if (state == brightness) return;
    state = brightness;
  }
}