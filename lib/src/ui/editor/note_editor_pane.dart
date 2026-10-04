import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/note.dart';
import '../../state/notes_controller.dart';
import '../common/completion_toggle.dart';
import '../common/markdown_text.dart';
import '../common/widgets.dart';

/// Key for the per-note Markdown switch, so a test can turn it on without
/// reverse-engineering which icon is which.
const Key markdownToggleKey = ValueKey('editor.markdown.toggle');

/// Width below which the editor shows the source or the preview rather than
/// both.
///
/// Chosen against the editor's own minimum useful width rather than a round
/// number: at 1000px the pane beside a 320px list is around 620, so the side-by-
/// side layout is the normal one and this only bites on a deliberately narrow
/// window.
const double _previewThreshold = 460;

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

  /// Whether the narrow layout is showing the preview rather than the source.
  ///
  /// Reset when the note changes, because carrying "I was reading the preview"
  /// across to a different note would drop someone into a rendered view of text
  /// they did not write, with no caret and nothing to type into.
  bool _narrowShowsPreview = false;

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
      // Back to the source on every note change; see _narrowShowsPreview.
      _narrowShowsPreview = false;
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
                            const SizedBox(width: 8),
                            _markdownToggle(controller, note),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: note.markdown
                              ? _markdownBody(controller, note, theme)
                              : TextField(
                                  controller: _body,
                                  focusNode: _bodyFocus,
                                  onChanged: (_) => _pushToModel(controller),
                                  maxLines: null,
                                  expands: true,
                                  textAlignVertical: TextAlignVertical.top,
                                  keyboardType: TextInputType.multiline,
                                  style: markCompleted(
                                    theme.textTheme.bodyLarge
                                        ?.copyWith(height: 1.55),
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

  /// The per-note Markdown switch, beside the thing it changes.
  ///
  /// Next to the title rather than in a bar above, for the same reason the
  /// completion circle is: a control that belongs to a note belongs next to that
  /// note's content, and "where do I turn this on" has to be answerable without
  /// going looking.
  Widget _markdownToggle(NotesController controller, Note note) {
    return IconButton(
      key: markdownToggleKey,
      onPressed: () => controller.setMarkdown(note.id, !note.markdown),
      tooltip: note.markdown
          ? 'Markdown on. Turn it off to edit this as plain text.'
          : 'Markdown. Turn it on to format this note.',
      icon: Icon(
        note.markdown ? Icons.check_circle : Icons.circle_outlined,
        size: 18,
        color: note.markdown
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.7),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  /// The Markdown body: the source on the left, the rendered note on the right.
  ///
  /// Below [_previewThreshold] there is not room for two panes of prose, so the
  /// preview becomes a switch rather than a column: someone editing a formatted
  /// note in a narrow window needs to see the result, and needs to see the
  /// source, and cannot have both at once. Asking is better than guessing, and
  /// better than silently showing neither.
  Widget _markdownBody(NotesController controller, Note note, ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _previewThreshold;

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // One or the other, not both: at this width two panes of prose
              // side by side are two unreadable columns.
              Expanded(
                child: _narrowShowsPreview
                    ? _previewPane(note, theme)
                    : _sourceField(controller, note, theme),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(width: 2),
                  _narrowPreviewButton(theme),
                ],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _sourceField(controller, note, theme)),
            VerticalDivider(
              width: 1,
              thickness: 1,
              indent: 2,
              endIndent: 2,
              color: theme.dividerColor,
            ),
            Expanded(child: _previewPane(note, theme)),
          ],
        );
      },
    );
  }

  Widget _sourceField(NotesController controller, Note note, ThemeData theme) {
    return TextField(
      controller: _body,
      focusNode: _bodyFocus,
      onChanged: (_) => _pushToModel(controller),
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      keyboardType: TextInputType.multiline,
      style: theme.textTheme.bodyLarge?.copyWith(
        height: 1.55,
        // Monospace while Markdown is on, so the syntax being typed is visible.
        // Source and preview are side by side, and a proportional font makes the
        // asterisks and hashes hard to line up by eye.
        fontFamily: note.markdown ? 'Consolas' : null,
        fontFamilyFallback: note.markdown ? const ['monospace'] : null,
        fontSize: note.markdown ? 13.5 : null,
        decoration: note.isCompleted ? TextDecoration.lineThrough : null,
      ),
      decoration: InputDecoration(
        hintText: note.markdown ? 'Markdown' : 'Start writing',
        filled: false,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _previewPane(Note note, ThemeData theme) {
    final source = _body.text;
    if (source.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Text(
          'Nothing to preview yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // Its own scroll view because the pane does not scroll: the source field
    // beside it expands to fill, and a preview that cannot reach the bottom of
    // its own note is not a preview.
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 0, 6, 12),
        child: DefaultTextStyle(
          style: markCompleted(const TextStyle(), completed: note.isCompleted) ??
              const TextStyle(),
          child: MarkdownText(
            source: source,
            color: theme.colorScheme.onSurface,
            accent: theme.colorScheme.primary,
            mutedColor: theme.colorScheme.onSurfaceVariant,
            selectable: true,
          ),
        ),
      ),
    );
  }

  Widget _narrowPreviewButton(ThemeData theme) {
    return TextButton.icon(
      onPressed: () => setState(() => _narrowShowsPreview = !_narrowShowsPreview),
      icon: Icon(
        _narrowShowsPreview ? Icons.edit_outlined : Icons.visibility_outlined,
        size: 15,
      ),
      label: Text(_narrowShowsPreview ? 'Edit source' : 'Preview'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: theme.textTheme.bodySmall,
      ),
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