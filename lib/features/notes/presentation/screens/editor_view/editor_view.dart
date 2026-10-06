import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win_notes/core/platform/shell_channel.dart';
import 'package:win_notes/features/notes/domain/repositories.dart';

import '../../../../../core/utils/app_providers.dart';
import '../../../domain/note.dart';
import '../../providers/notes_controller.dart';
import '../../widgets/editor_app_bar/editor_app_bar.dart';
import '../../widgets/editor_narrow_body/editor_narrow_body.dart';
import '../../widgets/note_editor_pane/note_editor_pane.dart';
import '../../widgets/note_list_pane/note_list_pane.dart';
import '../corrupt_notes_screen/corrupt_notes_screen.dart';

/// The editor window. Two panes wide, one at a time narrow; the break is on
/// width, since the editor resizes freely.
class EditorView extends ConsumerStatefulWidget {
  const EditorView({
    super.key,
    required this.onOpenSettings,
    required this.exportNotes,
    required this.importNotes,
  });

    /// Callbacks, not controllers: behaviour crosses as parameters, state arrives
    /// via `ref` (`AGENTS.md` §0.8).
  final VoidCallback onOpenSettings;
  final Future<void> Function() exportNotes;
  final Future<List<Note>?> Function() importNotes;

  static const double _narrowBreakpoint = 760;

  @override
  ConsumerState<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends ConsumerState<EditorView> {
    /// Which pane a narrow editor shows. A `ValueNotifier`, not provider state:
    /// narrow lifetime only, read through a `ValueListenableBuilder` in [build].
  final ValueNotifier<bool> _showListOnNarrow = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _showListOnNarrow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Narrowed to the two fields this screen branches on. Every keystroke used
    // to rebuild the Scaffold, both panes and the AppBar; now only a load or a
    // corrupt file does.
    final (bool, CorruptDataFileError?) notes = ref.watch(
      notesProvider.select((AsyncValue<NotesState> v) => (v.hasValue, v.value?.corrupt)),
    );
    final ShellChannel shell = ref.read(shellProvider);
    final NotesNotifier notifier = ref.read(notesProvider.notifier);

    final CorruptDataFileError? corrupt = notes.$2;
    if (corrupt != null) {
      return CorruptNotesScreen(
        error: corrupt,
        hasBackup: notifier.hasBackup,
        onRestore: widget.importNotes,
        onReveal: () => shell.revealPath(corrupt.path),
        onRestoreBackup: notifier.restoreBackup,
        onRetry: notifier.retryLoad,
        onStartFresh: notifier.startFresh,
      );
    }

    // Still loading. A blank frame beats a frame that says "no notes" and then
    // corrects itself - which is exactly the first-launch bug in `AGENTS.md` §5.1,
    // and the reason the loading case is drawn at all.
    if (!notes.$1) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < EditorView._narrowBreakpoint;

        return ValueListenableBuilder<bool>(
          valueListenable: _showListOnNarrow,
          builder: (BuildContext context, bool showListOnNarrow, _) {
            final bool showList = !narrow || showListOnNarrow;
            return Scaffold(
              appBar: EditorAppBar(
                narrow: narrow,
                showList: showList,
                onShowList: () => _showListOnNarrow.value = true,
                onOpenSettings: widget.onOpenSettings,
                exportNotes: widget.exportNotes,
                importNotes: widget.importNotes,
              ),
              body: narrow
                  ? EditorNarrowBody(
                      showList: showList,
                      onOpenNote: () => _showListOnNarrow.value = false,
                      onNewNote: () {
                        notifier.createNote();
                        _showListOnNarrow.value = false;
                        _focusBody();
                      },
                      onBack: () => _showListOnNarrow.value = true,
                    )
                  : Row(
                      children: <Widget>[
                        SizedBox(
                          width: 300,
                          child: NoteListPane(
                            onOpenNote: () => _showListOnNarrow.value = false,
                            onNewNote: () {
                              notifier.createNote();
                              if (narrow) _showListOnNarrow.value = false;
                              _focusBody();
                            },
                            onCloseList: () {},
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                        const Expanded(child: NoteEditorPane()),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  void _focusBody() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Drop the caret rather than moving it to a node nobody owns (§7.2).
      if (mounted) FocusManager.instance.primaryFocus?.unfocus();
    });
  }
}
