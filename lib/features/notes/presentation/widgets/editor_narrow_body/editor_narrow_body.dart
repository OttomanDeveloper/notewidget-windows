import 'package:flutter/material.dart';

import '../note_editor_pane/note_editor_pane.dart';
import '../note_list_pane/note_list_pane.dart';

/// The narrow editor: the list and the note, one at a time.
///
/// Stateless: visibility is a value from the screen, and creating a note is a
/// callback. The screen owns the field focus and the list flag.
class EditorNarrowBody extends StatelessWidget {
  const EditorNarrowBody({
    super.key,
    required this.showList,
    required this.onOpenNote,
    required this.onNewNote,
    required this.onBack,
  });

  final bool showList;
  final VoidCallback onOpenNote;
  final VoidCallback onNewNote;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: showList
          ? NoteListPane(
              key: const ValueKey('list'),
              showCloseButton: false,
              onOpenNote: onOpenNote,
              onNewNote: onNewNote,
              onCloseList: () {},
            )
          : NoteEditorPane(
              key: const ValueKey('editor'),
              onBack: onBack,
            ),
    );
  }
}
