import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:win_notes/features/notes/domain/note.dart';

import '../../providers/notes_controller.dart';
import '../../providers/notes_providers.dart';
import '../../../../../core/theme/skin.dart';
import '../../../../settings/presentation/providers/settings_providers.dart';
import '../note_list_item/note_list_item.dart';

/// The list of notes, with search on top.
///
/// Search matches title and body as you type; no history, no saved query.
class NoteListPane extends ConsumerStatefulWidget {
  const NoteListPane({
    super.key,
    required this.onOpenNote,
    required this.onNewNote,
    required this.onCloseList,
    this.showCloseButton = false,
  });

    /// Callbacks, not a controller: behaviour crosses as parameters, state via
    /// `ref` (`AGENTS.md` §0.8).
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
    // Restores the query so the filter survives layout swaps. `read`, not
    // `watch`: `initState` has no widget yet to rebuild.
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
    final ThemeData theme = Theme.of(context);

    // Narrowed to the three fields this pane draws. Typing in a note's body
    // used to rebuild the whole list; now only a visible-list, query or
    // selection change does.
    final List<Note> notes = ref.watch(visibleNotesProvider);
    final WinNotesSkin? skin = ref.watch(skinProvider);
    final SkinLook look = lookOf(skin);
    // The editor separates with a hairline where the widget uses a gap, so the
    // built-in look means both rather than one number for both.
    final SkinSeparator rows = SkinLook.forEditor(look.separator);
    final String query = ref.watch(notesProvider.select((AsyncValue<NotesState> v) => v.value?.query ?? ''));
    final String? selectedId =
        ref.watch(notesProvider.select((AsyncValue<NotesState> v) => v.value?.selectedId));
    final int total =
        ref.watch(notesProvider.select((AsyncValue<NotesState> v) => v.value?.notes.length ?? 0));
    final NotesNotifier notifier = ref.read(notesProvider.notifier);

    return Column(
      children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Shortcuts(
                      shortcuts: const <ShortcutActivator, Intent>{
                        SingleActivator(LogicalKeyboardKey.keyF): _SearchIntent(),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
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
                          children: <Widget>[
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
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: notes.length,
                      separatorBuilder: (BuildContext context, int index) => switch (rows) {
                        SkinSeparator.hairline => Divider(
                            height: 1,
                            color: Theme.of(context).dividerColor,
                          ),
                        SkinSeparator.gap => const SizedBox(height: 2),
                        SkinSeparator.none => const SizedBox.shrink(),
                      },
                      itemBuilder: (BuildContext context, int index) {
                        final Note note = notes[index];
                        return NoteListItem(
                          key: ValueKey<String>(note.id),
                          note: note,
                          selected: note.id == selectedId,
                          skin: skin,
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
                children: <Widget>[
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
