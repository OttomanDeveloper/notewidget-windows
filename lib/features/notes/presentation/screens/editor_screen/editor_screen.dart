import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/app_providers.dart';
import '../../../domain/note.dart';
import '../../providers/notes_controller.dart';
import '../../widgets/editor_app_bar/editor_app_bar.dart';
import '../../widgets/editor_narrow_body/editor_narrow_body.dart';
import '../../widgets/note_editor_pane/note_editor_pane.dart';
import '../../widgets/note_list_pane/note_list_pane.dart';
import '../corrupt_notes_screen/corrupt_notes_screen.dart';

/// The editor window.
///
/// Two panes on a wide window, one at a time on a narrow one. The break is on
/// width rather than on a device check, because the editor can be resized
/// freely and a pane layout that breaks at 700px is worse than one that
/// responds to it.
class EditorView extends ConsumerStatefulWidget {
  const EditorView({
    super.key,
    required this.onOpenSettings,
    required this.exportNotes,
    required this.importNotes,
  });

  /// A callback, not a controller.
  ///
  /// All three of these are allowed to cross as parameters (`AGENTS.md` §0.8) because
  /// they are behaviour, not state: a function that opens a dialog does not rebuild
  /// when the settings change. What *is* state - the notes, the corrupt-file state,
  /// the channel - is read with `ref`.
  final VoidCallback onOpenSettings;
  final Future<void> Function() exportNotes;
  final Future<List<Note>?> Function() importNotes;

  static const double _narrowBreakpoint = 760;

  @override
  ConsumerState<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends ConsumerState<EditorView> {
  /// Which pane a *narrow* editor is showing.
  ///
  /// A `ValueNotifier` rather than a field on this State, and that is the whole
  /// replacement for six `setState` calls. The line is lifetime: this is true for as
  /// long as the editor stays narrow, and nothing else in the app asks - but it is
  /// not shared either, so it does not belong in a provider where a second reader
  /// would find it and a test would have to seed it.
  ///
  /// Read through a `ValueListenableBuilder` in [build], which rebuilds only the
  /// part of the tree that depends on it.
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
    final notes = ref.watch(
      notesProvider.select((v) => (v.hasValue, v.value?.corrupt)),
    );
    final shell = ref.read(shellProvider);
    final notifier = ref.read(notesProvider.notifier);

    final corrupt = notes.$2;
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
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < EditorView._narrowBreakpoint;

        return ValueListenableBuilder<bool>(
          valueListenable: _showListOnNarrow,
          builder: (context, showListOnNarrow, _) {
            final showList = !narrow || showListOnNarrow;
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
                      children: [
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
      if (mounted) FocusScope.of(context).requestFocus(FocusNode());
    });
  }
}
