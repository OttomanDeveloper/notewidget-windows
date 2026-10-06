import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../domain/note.dart';
import '../../../domain/text_sizes.dart';
import '../../providers/notes_controller.dart';
import '../../providers/notes_providers.dart';
import '../../../../settings/data/settings_repository.dart';
import '../../../../settings/domain/settings.dart';
import '../../../../settings/presentation/providers/settings_controller.dart';
import '../../../../../core/widgets/completion_toggle/completion_toggle.dart';
import '../../../../../core/widgets/confirm_dialog/confirm_dialog.dart';
import '../../../../../core/widgets/undo_toast_body/undo_toast_body.dart';
import '../editor_back_bar/editor_back_bar.dart';
import '../editor_back_button/editor_back_button.dart';
import '../empty_state/empty_state.dart';
import '../editor_status_bar/editor_status_bar.dart';
import '../markdown_body/markdown_body.dart';
import '../markdown_toggle_button/markdown_toggle_button.dart';

/// Title and body of the selected note, with no toolbar and no save button.
///
/// Plain text, because the widget shows plain text too.
class NoteEditorPane extends ConsumerStatefulWidget {
  const NoteEditorPane({
    super.key,
    this.onBack,
  });


  /// Only supplied in the narrow layout, where the editor covers the list.
  ///
  /// A callback because the narrow layout owns which pane shows.
  final VoidCallback? onBack;

  bool get hasBack => onBack != null;

  @override
  ConsumerState<NoteEditorPane> createState() => _NoteEditorPaneState();
}

class _NoteEditorPaneState extends ConsumerState<NoteEditorPane> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();

  String? _loadedNoteId;

  /// Whether the narrow layout is showing the preview rather than the source.
  ///
  /// Reset on note change so a new note never opens in a stale preview.
  final ValueNotifier<bool> _narrowShowsPreview = ValueNotifier<bool>(false);

  /// What the preview renders. Debounced (250ms) from the body field: Markdown
  /// parsing is this pane's most expensive work (§7.1).
  final ValueNotifier<String> _previewSource = ValueNotifier<String>('');
  Timer? _previewDebounce;

  @override
  void initState() {
    super.initState();
    _body.addListener(_schedulePreview);
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    // A cancellable timer, not a bare Future.delayed: a pending delay outlives
    // dispose and fails a widget test outright.
    _previewDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _previewSource.value = _body.text;
    });
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _previewSource.dispose();
    _narrowShowsPreview.dispose();
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

    /// Loads a note's text into the fields when the selection changes. Guarded
    /// on [Note.id]: overwrites even matching text, or the caret sits in stale content.
  void _syncToSelected(NotesState? state, NotesNotifier notifier, {bool focusBody = false}) {
    final Note? note = state?.selectedNote;
    if (note == null) {
      _loadedNoteId = null;
      _title.clear();
      _body.clear();
      _previewDebounce?.cancel();
      _previewSource.value = '';
      return;
    }
    if (note.id != _loadedNoteId) {
      _loadedNoteId = note.id;
      _title.text = note.title;
      _body.text = note.body;
      // Immediately: switching notes must show the new preview at once, not
      // after the typing debounce.
      _previewDebounce?.cancel();
      _previewSource.value = note.body;
      _narrowShowsPreview.value = false;
      _title.selection = TextSelection.collapsed(offset: _title.text.length);
      _body.selection = TextSelection.collapsed(offset: _body.text.length);
    }
    if (focusBody) {
      _bodyFocus.requestFocus();
    }
  }

  void _pushToModel(NotesNotifier notifier) {
    final String? id = _loadedNoteId;
    if (id == null) return;
    notifier.updateNote(id, title: _title.text, body: _body.text);
  }

  /// Ctrl+wheel, written straight through to the setting so the gesture and the
  /// slider cannot disagree and the size survives a restart. The base is the size
  /// on screen, not the stored 0, so the first notch starts from what is shown.
  void _stepFontSize({required bool preview, required int delta}) {
    final Note? note = ref.read(selectedNoteProvider);
    final WinNotesSettings settings =
        ref.read(settingsProvider).value?.settings ?? SettingsRepository.defaults;
    final int chosen = preview ? settings.previewFontSize : settings.editorFontSize;

    final double rendered = preview
        ? TextSizes.preview(chosen)
        : TextSizes.source(
            chosen: chosen,
            markdown: note?.markdown ?? false,
            plainSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
          );

    final int next = WinNotesSettings.normaliseFontSize((rendered + delta).round());
    ref.read(settingsProvider.notifier).apply(
          (WinNotesSettings s) => preview
              ? s.copyWith(previewFontSize: next)
              : s.copyWith(editorFontSize: next),
        );
  }

  Future<void> _deleteCurrent(NotesNotifier notifier) async {
    final Note? note = ref.read(selectedNoteProvider);
    if (note == null) return;
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete this note?',
      message: '"${note.displayTitle}" will be removed from your desktop. '
          'You can undo this straight afterwards.',
      confirmLabel: 'Delete note',
    );
    if (!confirmed || !mounted) return;
    notifier.deleteNote(note.id);
    // The undo bar is the safety net for the "no trash" decision, so it appears
    // immediately rather than on the next edit.
    UndoToast.show(
      context,
      message: '"${note.displayTitle}" deleted',
      onUndo: notifier.undoDelete,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NotesState? state = ref.watch(notesProvider).value;
    final NotesNotifier notifier = ref.read(notesProvider.notifier);

    // `Consumer` so `_syncToSelected` runs before drawing: it loads the text
    // into the fields, ordered against the build without a post-frame callback.
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        _syncToSelected(state, notifier);
        final Note? note = state?.selectedNote;

        // Two numbers, watched as a slice so a palette change does not rebuild
        // the editor's text. 0 here means "as designed" - see `TextSizes`.
        final (int, int) sizes = ref.watch(
          settingsProvider.select(
            (AsyncValue<SettingsState> v) => (
              v.value?.settings.editorFontSize ?? 0,
              v.value?.settings.previewFontSize ?? 0,
            ),
          ),
        );

        if (note == null) {
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: EmptyState(
                  icon: Icons.edit_note,
                  title: 'Nothing to edit',
                  message: 'Pick a note from the list, or start a new one.',
                  action: FilledButton.tonalIcon(
                    onPressed: () {
                      notifier.createNote();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _bodyFocus.requestFocus();
                      });
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New note'),
                  ),
                ),
              ),
              if (widget.hasBack) EditorBackButton(onBack: widget.onBack),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.hasBack)
              EditorBackBar(
                note: note,
                onToggleCompleted: () =>
                    ref.read(notesProvider.notifier).toggleCompleted(note.id),
                onDelete: () =>
                    _deleteCurrent(ref.read(notesProvider.notifier)),
                onBack: widget.onBack,
              ),
            Expanded(
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.keyS, control: true): _SaveIntent(),
                  // Ctrl+D because it is what every other list-shaped thing on
                  // this planet uses for "done", and because finishing a task
                  // should not require reaching for a 22px circle.
                  SingleActivator(LogicalKeyboardKey.keyD, control: true): _DoneIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    // Ctrl+S exists only to say "there is no save button and
                    // there never will be", so it costs nothing and removes a
                    // reflex-driven worry.
                    _SaveIntent: CallbackAction<_SaveIntent>(
                      onInvoke: (_) {
                        _pushToModel(notifier);
                        return null;
                      },
                    ),
                    _DoneIntent: CallbackAction<_DoneIntent>(
                      onInvoke: (_) {
                        final Note? selected = state?.selectedNote;
                        if (selected != null) notifier.toggleCompleted(selected.id);
                        return null;
                      },
                    ),
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            // The one control that says this note is a task
                            // rather than a thought, sitting beside the thing it
                            // applies to rather than in a bar above it.
                            CompletionToggle(
                              completed: note.isCompleted,
                              onToggle: () => notifier.toggleCompleted(note.id),
                              diameter: 22,
                              hitTarget: 40,
                              filled: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _title,
                                focusNode: _titleFocus,
                                onChanged: (_) => _pushToModel(notifier),
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
                            MarkdownToggleButton(
                              markdown: note.markdown,
                              onToggle: () => notifier.setMarkdown(
                                note.id,
                                enabled: !note.markdown,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: note.markdown
                              ? MarkdownBody(
                                  note: note,
                                  field: _body,
                                  focusNode: _bodyFocus,
                                  previewSource: _previewSource,
                                  showsPreview: _narrowShowsPreview,
                                  editorFontSize: sizes.$1,
                                  previewFontSize: sizes.$2,
                                  onEditorFontStep: (int delta) =>
                                      _stepFontSize(preview: false, delta: delta),
                                  onPreviewFontStep: (int delta) =>
                                      _stepFontSize(preview: true, delta: delta),
                                  onChanged: () => _pushToModel(notifier),
                                )
                              : TextField(
                                  controller: _body,
                                  focusNode: _bodyFocus,
                                  onChanged: (_) => _pushToModel(notifier),
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
            EditorStatusBar(
              hasPendingUndo: state?.pendingUndo != null,
              onUndo: notifier.undoDelete,
              onDelete: () => _deleteCurrent(ref.read(notesProvider.notifier)),
            ),
          ],
        );
      },
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _DoneIntent extends Intent {
  const _DoneIntent();
}
