import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/note.dart';
import '../../state/notes_controller.dart';
import '../common/completion_toggle.dart';

/// The list of notes, with search on top.
///
/// Search matches both title and body and filters as the user types. There is
/// no search history and no saved query, because neither has ever been wanted
/// by anyone who just wanted to find the thing they wrote.
class NoteListPane extends StatefulWidget {
  const NoteListPane({
    super.key,
    required this.controller,
    required this.onOpenNote,
    required this.onNewNote,
    required this.onCloseList,
    this.showCloseButton = false,
  });

  final NotesController controller;
  final VoidCallback onOpenNote;
  final VoidCallback onNewNote;

  /// Present only in the narrow layout, where the list covers the editor.
  final VoidCallback onCloseList;
  final bool showCloseButton;

  @override
  State<NoteListPane> createState() => _NoteListPaneState();
}

class _NoteListPaneState extends State<NoteListPane> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Restoring the query keeps the list filter from resetting when the layout
    // swaps between the two-pane and one-pane arrangements.
    _search.text = widget.controller.query;
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _requestFocusSearch() {
    _searchFocus.requestFocus();
    _search.selection = TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final notes = controller.visibleNotes;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Shortcuts(
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.keyF): _SearchIntent(),
                      },
                      child: Actions(
                        actions: {
                          _SearchIntent: CallbackAction<_SearchIntent>(
                            onInvoke: (_) {
                              _requestFocusSearch();
                              return null;
                            },
                          ),
                        },
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          onChanged: controller.setQuery,
                          textInputAction: TextInputAction.search,
                          style: theme.textTheme.bodyMedium,
                          decoration: InputDecoration(
                            hintText: 'Search notes',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: controller.query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _search.clear();
                                      controller.setQuery('');
                                      _searchFocus.requestFocus();
                                    },
                                  ),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.showCloseButton)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back to note',
                      onPressed: widget.onCloseList,
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: notes.isEmpty
                  ? _emptyList(context)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return _NoteListItem(
                          note: note,
                          selected: note.id == controller.selectedNote?.id,
                          onTap: () {
                            controller.select(note.id);
                            widget.onOpenNote();
                          },
                          onToggleCompleted: () =>
                              controller.toggleCompleted(note.id),
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _statusText(controller),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: widget.onNewNote,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New note'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _statusText(NotesController controller) {
    final total = controller.notes.length;
    final shown = controller.visibleNotes.length;
    if (controller.query.trim().isNotEmpty) {
      return shown == total ? '$total notes' : '$shown of $total notes';
    }
    return total == 1 ? '1 note' : '$total notes';
  }

  Widget _emptyList(BuildContext context) {
    final theme = Theme.of(context);
    final filtering = widget.controller.query.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtering ? Icons.search_off : Icons.notes,
              size: 32,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              filtering ? 'Nothing matches that search' : 'No notes yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              filtering
                  ? 'Search looks at titles and bodies, and stops there.'
                  : 'Write something and it appears on the desktop.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Intent for Ctrl+F, so the shortcut has a name rather than a bare closure.
class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _NoteListItem extends StatelessWidget {
  const _NoteListItem({
    required this.note,
    required this.selected,
    required this.onTap,
    required this.onToggleCompleted,
  });

  final Note note;
  final bool selected;
  final VoidCallback onTap;

  /// Separate from [onTap] so ticking a task off does not also open it. Working
  /// through a list means pressing the same small circle a dozen times in a row,
  /// and having the editor jump to each note in turn makes that unusable.
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = note.isCompleted;

    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                // The caret colour marks selection, tying the list to the mark.
                // A finished note gives it up: it is no longer the one to pick up.
                color: selected && !done ? scheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: CompletionToggle(
                  completed: done,
                  onToggle: onToggleCompleted,
                  diameter: 18,
                  hitTarget: 30,
                  color: done ? scheme.primary : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: markCompleted(
                        theme.textTheme.titleSmall?.copyWith(
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: done
                              ? scheme.onSurfaceVariant.withValues(alpha: 0.75)
                              : scheme.onSurface,
                        ),
                        completed: done,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Skipped entirely when there is no body, rather than
                    // rendered as an empty line. See _preview.
                    if (note.body.trim().isNotEmpty)
                      Text(
                        _preview(note),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: markCompleted(
                          theme.textTheme.bodySmall?.copyWith(
                            color: done
                                ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                                : scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                          completed: done,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Falls back to the title when there is no body yet, so a note that has only
  /// been named still shows something useful in the preview slot.
  ///
  /// "No text yet" is reserved for a note with nothing in it at all. A note with
  /// a title and no body has its content right there on the line above, so
  /// claiming otherwise is just wrong - and a note added from the widget's
  /// composer is always in that shape.
  static String _preview(Note note) {
    final body = note.body.trim();
    if (body.isNotEmpty) return body.replaceAll('\n', ' ');
    if (note.title.trim().isNotEmpty) return '';
    return 'No text yet';
  }
}