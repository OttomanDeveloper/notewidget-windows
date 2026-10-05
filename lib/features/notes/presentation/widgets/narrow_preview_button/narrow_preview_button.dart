import 'package:flutter/material.dart';

/// The switch between the rendered preview and the raw source.
///
/// Takes [showsPreview] rather than reading the notifier, so the label cannot
/// drift from the pane above it. The first version read the flag here and went
/// stale - see the note on the `ValueListenableBuilder` in [MarkdownBody].
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
    final theme = Theme.of(context);
    return TextButton.icon(
      onPressed: onToggle,
      icon: Icon(
        showsPreview ? Icons.edit_outlined : Icons.visibility_outlined,
        size: 15,
      ),
      label: Text(showsPreview ? 'Edit source' : 'Preview'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: theme.textTheme.bodySmall,
      ),
    );
  }
}
