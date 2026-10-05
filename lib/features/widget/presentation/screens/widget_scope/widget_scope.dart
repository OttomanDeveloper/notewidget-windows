import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/app_providers.dart';
import '../../providers/widget_controller.dart';
import '../../../../settings/presentation/providers/settings_providers.dart';
import '../widget_surface/widget_surface.dart';
import '../widget_event_router/widget_event_router.dart';

/// The MaterialApp and the widget: the `MaterialApp` and the widget itself.
class WidgetScope extends ConsumerStatefulWidget {
  const WidgetScope({super.key});

  @override
  ConsumerState<WidgetScope> createState() => WidgetScopeState();
}

class WidgetScopeState extends ConsumerState<WidgetScope>
    with WidgetsBindingObserver {
  /// Read in `initState` because Riverpod asserts on any `ref` use inside
  /// `dispose`. See `EditorScopeState` for the full rule.
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
    // that knows the isolate is ending. `AGENTS.md` §4.7: the hazard predates the
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
