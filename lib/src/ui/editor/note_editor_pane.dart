import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/note.dart';
import '../../state/notes_controller.dart';
import '../common/completion_toggle.dart';
import '../common/widgets.dart';

/// Title and body of the selected note, with no toolbar and no save button.
///
/// Editing is plain text because the widget shows plain text too. Rich text
/// would only be readable in one of the two places.
class NoteEditorPane extends StatefulWidget {
  const NoteEditorPane({
    super.key,
    required this.controller,
    this.onBack,
  });

  final NotesController controller;

  /// Only supplied in the narrow layout, where the editor covers the list.
  final VoidCallback? onBack;

  bool get hasBack => onBack != null;

  @override
  State<NoteEditorPane> createState() => _NoteEditorPaneState();
}

class _NoteEditorPaneState extends State<NoteEditorPane> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();

  String? _loadedNoteId;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  /// Loads a note's text into the fields when the selection changes.
  ///
  /// Guarded on [Note.id] rather than on a diff of the text: an incoming change
  /// from the widget surface or an undo has to overwrite the fields even when
  /// the text happens to match, or the caret would sit in stale content.
  void _syncToSelected(NotesController controller, {bool focusBody = false}) {
    final note = controller.selectedNote;
    if (note == null) {
      _loadedNoteId = null;
      _title.clear();
      _body.clear();
      return;
    }
    if (note.id != _loadedNoteId) {
      _loadedNoteId = note.id;
      _title.text = note.title;
      _body.text = note.body;
      _title.selection = TextSelection.collapsed(offset: _title.text.length);
      _body.selection = TextSelection.collapsed(offset: _body.text.length);
    }
    if (focusBody) {
      _bodyFocus.requestFocus();
    }
  }

  void _pushToModel(NotesController controller) {
    final id = _loadedNoteId;
    if (id == null) return;
    controller.updateNote(id, title: _title.text, body: _body.text);
  }

  Future<void> _deleteCurrent(NotesController controller) async {
    final note = controller.selectedNote;
    if (note == null) return;
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete this note?',
      message: '"${note.displayTitle}" will be removed from your desktop. '
          'You can undo this straight afterwards.',
      confirmLabel: 'Delete note',
    );
    // Guarded on this State's own mounted, not on the context, because the
    // dialog await is where this widget can be torn down.
    if (!confirmed || !mounted) return;

    controller.deleteNote(note.id);
    // The undo bar is the safety net for the "no trash" decision, so it appears
    // immediately rather than on the next edit.
    UndoToast.show(
      context,
      message: '"${note.displayTitle}" deleted',
      onUndo: controller.undoDelete,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        _syncToSelected(controller);
        final note = controller.selectedNote;

        if (note == null) {
          return Stack(
            children: [
              Positioned.fill(
                child: EmptyState(
                  icon: Icons.edit_note,
                  title: 'Nothing to edit',
                  message: 'Pick a note from the list, or start a new one.',
                  action: FilledButton.tonalIcon(
                    onPressed: () {
                      controller.createNote();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _bodyFocus.requestFocus();
                      });
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New note'),
                  ),
                ),
              ),
              if (widget.hasBack) _backButton(context),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.hasBack) _backBar(context),
            Expanded(
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.keyS, control: true): _SaveIntent(),
                  // Ctrl+D because it is what every other list-shaped thing on
                  // this planet uses for "done", and because finishing a task
                  // should not require reaching for a 22px circle.
                  SingleActivator(LogicalKeyboardKey.keyD, control: true): _DoneIntent(),
                },
                child: Actions(
                  actions: {
                    // Ctrl+S exists only to say "there is no save button and
                    // there never will be", so it costs nothing and removes a
                    // reflex-driven worry.
                    _SaveIntent: CallbackAction<_SaveIntent>(
                      onInvoke: (_) {
                        _pushToModel(controller);
                        return null;
                      },
                    ),
                    _DoneIntent: CallbackAction<_DoneIntent>(
                      onInvoke: (_) {
                        final selected = controller.selectedNote;
                        if (selected != null) controller.toggleCompleted(selected.id);
                        return null;
                      },
                    ),
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // The one control that says this note is a task
                            // rather than a thought, sitting beside the thing it
                            // applies to rather than in a bar above it.
                            CompletionToggle(
                              completed: note.isCompleted,
                              onToggle: () => controller.toggleCompleted(note.id),
                              diameter: 22,
                              hitTarget: 40,
                              filled: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _title,
                                focusNode: _titleFocus,
                                onChanged: (_) => _pushToModel(controller),
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => _bodyFocus.requestFocus(),
                                maxLines: null,
                                // Struck through while it is finished, so the
                                // editor says the same thing the widget and the
                                // list do rather than needing its own convention.
                                style: markCompleted(
                                  theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  completed: note.isCompleted,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Title',
                                  filled: false,
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TextField(
                            controller: _body,
                            focusNode: _bodyFocus,
                            onChanged: (_) => _pushToModel(controller),
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            keyboardType: TextInputType.multiline,
                            style: markCompleted(
                              theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                              completed: note.isCompleted,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Start writing',
                              filled: false,
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _statusBar(context, theme, controller),
          ],
        );
      },
    );
  }

  Widget _backButton(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to notes',
            onPressed: widget.onBack,
          ),
        ),
      );

  Widget _backBar(BuildContext context) {
    final note = widget.controller.selectedNote;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to notes',
            onPressed: widget.onBack,
          ),
          const Spacer(),
          // The narrow layout has no room for the toggle beside the title, so it
          // lives in the bar instead. Marking a task done has to work the same
          // way in both arrangements, and this is the only place it fits here.
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CompletionToggle(
                completed: note.isCompleted,
                onToggle: () => widget.controller.toggleCompleted(note.id),
                diameter: 20,
                hitTarget: 36,
                filled: true,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete note',
            onPressed: () => _deleteCurrent(widget.controller),
          ),
        ],
      ),
    );
  }

  Widget _statusBar(
    BuildContext context,
    ThemeData theme,
    NotesController controller,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 10, 20, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.check, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Saved to this PC',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (controller.pendingUndo != null)
            TextButton(
              onPressed: controller.undoDelete,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
              child: const Text('Undo delete'),
            ),
          TextButton.icon(
            onPressed: () => _deleteCurrent(widget.controller),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _DoneIntent extends Intent {
  const _DoneIntent();
}