import 'package:flutter/material.dart';

import '../../../../../core/theme/theme.dart';

/// The key for the add-a-note field, for the same reason as the button's.
const Key addNoteFieldKey = ValueKey('winnotes.widget.addNoteField');

/// The open add-a-note field.
class ComposerField extends StatelessWidget {
  const ComposerField({
    super.key,
    required this.field,
    required this.focusNode,
    required this.dark,
    required this.accent,
    required this.onClose,
    required this.onSubmit,
  });

  final TextEditingController field;
  final FocusNode focusNode;
  final bool dark;
  final Color accent;
  final VoidCallback onClose;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = widgetMutedColor(dark ? Brightness.dark : Brightness.light);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widgetBodyColor(dark ? Brightness.dark : Brightness.light)
              .withValues(alpha: dark ? 0.10 : 0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: addNoteFieldKey,
                  controller: field,
                  focusNode: focusNode,
                  // One line, and Enter saves. A note with several lines is a
                  // note being written, not a note being jotted down, and that
                  // is what the editor is for.
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSubmit(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: widgetBodyColor(
                      dark ? Brightness.dark : Brightness.light,
                    ),
                    height: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add a note',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 15),
                tooltip: 'Cancel',
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                color: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
