import 'package:flutter/material.dart';

/// Source/preview switch taking [showsPreview]: the label cannot drift from the
/// pane, unlike the first version that read the flag and went stale.
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
      label: Text(showsPreview ? 'Edit source' : 'Preview'),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: theme.textTheme.bodySmall,
      ),
    );
  }
}
