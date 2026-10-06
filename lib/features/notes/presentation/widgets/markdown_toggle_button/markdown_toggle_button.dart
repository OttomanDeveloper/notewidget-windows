import 'package:flutter/material.dart';

/// Key for the per-note Markdown switch, so a test can turn it on without
/// reverse-engineering which icon is which.
const Key markdownToggleKey = ValueKey('editor.markdown.toggle');

/// The per-note Markdown switch, beside the thing it changes: placement answers
/// "where do I turn this on" without going looking.
class MarkdownToggleButton extends StatelessWidget {
  const MarkdownToggleButton({
    super.key,
    required this.markdown,
    required this.onToggle,
  });

  final bool markdown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: markdownToggleKey,
      onPressed: onToggle,
      tooltip: markdown
          ? 'Markdown on. Turn it off to edit this as plain text.'
          : 'Markdown. Turn it on to format this note.',
      icon: Icon(
        markdown ? Icons.check_circle : Icons.circle_outlined,
        size: 18,
        color: markdown
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
