import 'package:flutter/material.dart';

import '../../../domain/note.dart';

class SourceField extends StatelessWidget {
  const SourceField({
    super.key,
    required this.field,
    required this.focusNode,
    required this.note,
    required this.onChanged,
  });

  final TextEditingController field;
  final FocusNode focusNode;
  final Note note;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return TextField(
      controller: field,
      focusNode: focusNode,
      onChanged: (_) => onChanged(),
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
        fontFamilyFallback: note.markdown ? const <String>['monospace'] : null,
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
}
