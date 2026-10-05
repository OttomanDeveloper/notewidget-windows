import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/shell_channel.dart';
import '../../state/providers.dart';
import '../../state/widget_controller.dart';
import '../theme_scope.dart';
import 'widget_surface.dart';

/// Root widget for the widget surface.
///
/// Runs in its own isolate, reads the same files the editor writes, and never
/// writes notes. There is one writer per file in this app and this side owns only
/// `widget_state.json`.
///
/// Now a `ConsumerWidget` creating its own `ProviderScope`, against the same
/// declarations the editor uses. That is what `docs/isolate_pattern.md` §3.1 asked
/// for: the two surfaces build one graph rather than each writing its own, so the
/// three copies of `_resolveBrightness` that disagreed with each other are now one
/// provider (`AGENTS.md` §4.7).
class WidgetApp extends ConsumerWidget {
  const WidgetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const _WidgetScope();
}

/// The MaterialApp and the widget: the `MaterialApp` and the widget itself.
class _WidgetScope extends ConsumerStatefulWidget {
  const _WidgetScope();

  @override
  ConsumerState<_WidgetScope> createState() => _WidgetScopeState();
}

class _WidgetScopeState extends ConsumerState<_WidgetScope>
    with WidgetsBindingObserver {
  /// Read in `initState` because Riverpod asserts on any `ref` use inside
  /// `dispose`. See `_EditorScopeState` for the full rule.
  late final WidgetNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(widgetProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  /// The startup ladder, in the order it has to happen.
  ///
  /// The delay comes after the load because it is the autostart delay: on an
  /// autostart launch the widget waits before appearing, and launching by hand shows
  /// it at once, because someone who just clicked the icon is already looking.
  Future<void> _start() async {
    // Read before the first await; a WidgetRef held across one throws once the
    // widget is gone. See EditorBootstrap.start for the full explanation.
    final notifier = ref.read(widgetProvider.notifier);

    await ref.read(widgetProvider.future);
    await notifier.applyStartupDelay();
    await notifier.restoreGeometry();
  }

  @override
  void didChangePlatformBrightness() {
    ref.read(systemBrightnessProvider.notifier).report(
          brightness:
              MediaQueryData.fromView(View.of(context)).platformBrightness,
        );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // `_notifier`, captured in `initState`, and not `ref.read(...)` here: Riverpod
    // asserts on any `ref` use inside `dispose`, so the latter throws during tree
    // finalisation - after the test that closed the surface has already passed.
    //
    // `onDispose` cannot await either, so the flush is an explicit call from a place
    // that knows the isolate is ending. `AGENTS.md` §4.8: the hazard predates the
    // provider work and is unchanged by it.
    unawaited(_notifier.flush());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(widgetSurfaceThemeProvider);

    final ready = ref.watch(widgetProvider).hasValue;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      // Blank rather than a spinner: the window is frameless and translucent, and
      // a spinner on a desktop widget would be the first thing anyone saw at boot.
      home: ready
          ? WidgetEventRouter(
              child: Theme(
                // The widget draws its own surface colour, so the ambient brightness
                // has to follow the widget's, not the window's.
                data: ThemeData(brightness: theme.brightness),
                child: const WidgetSurface(),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Routes events pushed up from the runner.
///
/// Three of the six event kinds are deliberately ignored here, and the reason is the
/// whole design: `toggleCompleted` and `createNote` are *requests* addressed to the
/// editor, which owns notes.json. Acting on them from this isolate would put two
/// writers on one file - precisely what the runner's routing exists to prevent.
/// `docs/isolate_pattern.md` §3.4.
class WidgetEventRouter extends ConsumerStatefulWidget {
  const WidgetEventRouter({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WidgetEventRouter> createState() => _WidgetEventRouterState();
}

class _WidgetEventRouterState extends ConsumerState<WidgetEventRouter> {
  StreamSubscription<ShellEvent>? _events;

  @override
  void initState() {
    super.initState();
    _events = ref.read(shellProvider).events.listen(_onEvent);
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  void _onEvent(ShellEvent event) {
    // See `EditorEventRouter._onEvent`: a `ref` used after unmount throws
    // than being ignored, and an event can arrive during teardown.
    if (!mounted) return;
    final notifier = ref.read(widgetProvider.notifier);
    final shell = ref.read(shellProvider);

    switch (event.kind) {
      case ShellEventKind.hotkey:
        // The editor may not have been created on an autostart launch, so ask the
        // runner to raise it rather than assuming it exists.
        unawaited(shell.showEditor());
      case ShellEventKind.geometry:
        final bounds = event.bounds;
        if (bounds != null) notifier.onGeometryChanged(bounds);
      case ShellEventKind.visibility:
        notifier.setWidgetVisibleFromPlatform(visible: event.isVisible);
      case ShellEventKind.openSettings:
        // Asking the runner rather than opening a dialog here: on the widget surface
        // there is no window to put a dialog on.
        unawaited(shell.openSettings());
      case ShellEventKind.toggleCompleted:
      case ShellEventKind.createNote:
        // Not ours. See the class doc.
        break;
      case ShellEventKind.unknown:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
