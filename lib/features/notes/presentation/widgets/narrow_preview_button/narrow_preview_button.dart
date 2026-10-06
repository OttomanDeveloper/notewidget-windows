import 'package:flutter/material.dart';

/// Source/preview switch taking [showsPreview]: the label cannot drift from the
/// pane. "Show preview" rather than "Preview", because the per-note Markdown
/// switch beside the title already says `Preview` and both are on screen at once.
class NarrowPreviewButton extends StatelessWidget {
  const NarrowPreviewButton({
    super.key,
    required this.showsPreview,
    required this.onToggle,
  });

  final bool showsPreview;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return TextButton.icon(
      onPressed: onToggle,
      icon: Icon(
        showsPreview ? Icons.edit_outlined : Icons.visibility_outlined,
        size: 15,
      ),
      label: Text(showsPreview ? 'Edit source' : 'Show preview'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: theme.textTheme.bodySmall,
      ),
    );
  }
}
