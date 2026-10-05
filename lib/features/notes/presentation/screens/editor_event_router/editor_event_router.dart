import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/platform/shell_channel.dart';
import '../../../../../core/utils/app_providers.dart';
import '../../providers/notes_controller.dart';
import '../editor_home/editor_home.dart';

/// Routes events pushed up from the runner.
///
/// Kept as a switch rather than a table of handlers because each case does something
/// different, and three of them deliberately do nothing - see [ShellEventKind].
///
/// This is a `ConsumerState` rather than a plain function so the subscription has an
/// owner with a lifetime. A bare `shell.events.listen` in `build` would stack a
/// listener per rebuild, and the symptom of that is a hotkey that raises the editor
/// six times.
class EditorEventRouter extends ConsumerStatefulWidget {
  const EditorEventRouter({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EditorEventRouter> createState() => EditorEventRouterState();
}

class EditorEventRouterState extends ConsumerState<EditorEventRouter> {
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
    // An event can arrive after the tree is torn down, and a `ref` used then
    // throws rather than being ignored. See `EditorBootstrap.start`.
    if (!mounted) return;

    switch (event.kind) {
      case ShellEventKind.hotkey:
        _focusEditor();
      case ShellEventKind.openSettings:
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (!mounted) return;
        unawaited(openSettings(context, ref));
        messenger?.hideCurrentSnackBar();
      case ShellEventKind.toggleCompleted:
        // The widget surface asks rather than writing, because this is the one
        // writer of notes.json. Answering here means the change is made in the same
        // place every other edit is, and the widget sees it through the directory
        // watcher it already uses.
        final id = event.noteId;
        if (id != null) ref.read(notesProvider.notifier).toggleCompleted(id);
      case ShellEventKind.createNote:
        // A note written in the widget, for the same reason as above.
        final incoming = event.newNote;
        if (incoming != null) {
          ref.read(notesProvider.notifier).addNote(
                title: incoming.title,
                body: incoming.body,
              );
        }
      case ShellEventKind.geometry:
      case ShellEventKind.visibility:
      case ShellEventKind.unknown:
        // Not ours. `docs/isolate_pattern.md` §3.4: a future event that arrives at
        // the wrong surface should be ignored loudly in a test, not silently here.
        break;
    }
  }

  void _focusEditor() {
    // Closing the editor hands focus back to the widget, so the hotkey has to bring
    // the editor back properly rather than just showing it.
    unawaited(ref.read(shellProvider).focusWindow('editor'));
    FocusScope.of(context).requestFocus(FocusNode());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
