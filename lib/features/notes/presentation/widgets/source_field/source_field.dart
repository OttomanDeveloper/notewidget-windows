import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../../../domain/text_sizes.dart';

class SourceField extends StatelessWidget {
  const SourceField({
    super.key,
    required this.field,
    required this.focusNode,
    required this.note,
    required this.onChanged,
    this.fontSize = 0,
  });

  final TextEditingController field;
  final FocusNode focusNode;
  final Note note;
  final VoidCallback onChanged;

  /// The user's chosen size, or 0 for "as designed". Resolved against the note
  /// and the theme here rather than by the caller, so the monospace case and
  /// the plain case cannot disagree about what "as designed" means.
  final int fontSize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double size = TextSizes.source(
      chosen: fontSize,
      markdown: note.markdown,
      plainSize: theme.textTheme.bodyLarge?.fontSize,
    );
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
        // Monospace while Markdown is on, so the syntax being typed is visible. Source
        // and preview are side by side, and a proportional font makes the
        // asterisks and hashes hard to line up by eye.
        fontFamily: note.markdown ? 'Consolas' : null,
        // Only alongside a family: a fallback with no family *is* the family,
        // which would silently make every plain note monospace.
        fontFamilyFallback:
            note.markdown ? const <String>['monospace'] : null,
        fontSize: size,
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
