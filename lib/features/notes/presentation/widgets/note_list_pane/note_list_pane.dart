import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../providers/notes_controller.dart';
import '../../providers/notes_providers.dart';
import '../note_list_item/note_list_item.dart';

/// The list of notes, with search on top.
///
/// Search matches both title and body and filters as the user types. There is
/// no search history and no saved query, because neither has ever been wanted
/// by anyone who just wanted to find the thing they wrote.
class NoteListPane extends ConsumerStatefulWidget {
  const NoteListPane({
    super.key,
    required this.onOpenNote,
    required this.onNewNote,
    required this.onCloseList,
    this.showCloseButton = false,
  });

  /// Callbacks, not a controller.
  ///
  /// All three are allowed to cross as parameters (`AGENTS.md` §0.8) because they
  /// are behaviour rather than state: a callback that opens a note does not rebuild
  /// when the notes change. What *is* state is read with `ref`.
  final VoidCallback onOpenNote;
  final VoidCallback onNewNote;

  /// Present only in the narrow layout, where the list covers the editor.
  final VoidCallback onCloseList;
  final bool showCloseButton;

  @override
  ConsumerState<NoteListPane> createState() => _NoteListPaneState();
}

class _NoteListPaneState extends ConsumerState<NoteListPane> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Restoring the query keeps the list filter from resetting when the layout
    // swaps between the two-pane and one-pane arrangements.
    //
    // `read` and not `watch`: this runs before the first frame, and watching a
    // provider inside `initState` is the thing Riverpod warns about - there is no
    // widget yet to rebuild.
    _search.text = ref.read(notesProvider).value?.query ?? '';
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

    // Narrowed to the three fields this pane draws. Typing in a note's body
    // used to rebuild the whole list; now only a visible-list, query or
    // selection change does.
    final notes = ref.watch(visibleNotesProvider);
    final query = ref.watch(notesProvider.select((v) => v.value?.query ?? ''));
    final selectedId =
        ref.watch(notesProvider.select((v) => v.value?.selectedId));
    final total =
        ref.watch(notesProvider.select((v) => v.value?.notes.length ?? 0));
    final notifier = ref.read(notesProvider.notifier);

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
                          onChanged: notifier.setQuery,
                          textInputAction: TextInputAction.search,
                          style: theme.textTheme.bodyMedium,
                          decoration: InputDecoration(
                            hintText: 'Search notes',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _search.clear();
                                      notifier.setQuery('');
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
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              query.trim().isNotEmpty
                                  ? Icons.search_off
                                  : Icons.notes,
                              size: 32,
                              color: theme.colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              query.trim().isNotEmpty
                                  ? 'Nothing matches that search'
                                  : 'No notes yet',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              query.trim().isNotEmpty
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
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return NoteListItem(
                          note: note,
                          selected: note.id == selectedId,
                          onTap: () {
                            notifier.select(note.id);
                            widget.onOpenNote();
                          },
                          onToggleCompleted: () =>
                              notifier.toggleCompleted(note.id),
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
                      _statusText(
                          query: query, shown: notes.length, total: total),
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
  }

  String _statusText({
    required String query,
    required int shown,
    required int total,
  }) {
    if (query.trim().isNotEmpty) {
      return shown == total ? '$total notes' : '$shown of $total notes';
    }
    return total == 1 ? '1 note' : '$total notes';
  }
}

/// Intent for Ctrl+F, so the shortcut has a name rather than a bare closure.
class _SearchIntent extends Intent {
  const _SearchIntent();
}
