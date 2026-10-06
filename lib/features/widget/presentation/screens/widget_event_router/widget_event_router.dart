import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/platform/shell_channel.dart';
import '../../../../../core/utils/app_providers.dart';
import '../../providers/widget_controller.dart';

/// Routes runner events. A switch, not a handler table; three kinds are ignored:
/// `toggleCompleted`/`createNote` belong to the editor (one writer per file).
/// See `docs/isolate_pattern.md` §3.4.
class WidgetEventRouter extends ConsumerStatefulWidget {
  const WidgetEventRouter({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WidgetEventRouter> createState() => WidgetEventRouterState();
}

class WidgetEventRouterState extends ConsumerState<WidgetEventRouter> {
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
