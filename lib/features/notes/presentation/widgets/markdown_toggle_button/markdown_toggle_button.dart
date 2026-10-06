import 'package:flutter/material.dart';

/// Key for the per-note Markdown switch, so a test can turn it on without
/// reverse-engineering which icon is which.
const Key markdownToggleKey = ValueKey<String>('editor.markdown.toggle');

/// The per-note Markdown switch, beside the thing it changes. It carries a
/// visible word because it was an 18px circle beside the completion circle, and
/// two bare circles in one row read as two checkboxes. See widget_pattern.md.
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    // The word does not change with the state, so the row does not jump sideways
    // as it is toggled; fill, border and icon carry the state instead.
    final Color accent = markdown ? colors.primary : colors.onSurfaceVariant;
    final Color border = markdown
        ? colors.primary.withValues(alpha: 0.55)
        : colors.onSurfaceVariant.withValues(alpha: 0.38);

    return Semantics(
      button: true,
      toggled: markdown,
      label: markdown
          ? 'Markdown preview on. Turn it off to edit this as plain text.'
          : 'Markdown preview off. Turn it on to see a preview.',
      child: Tooltip(
        message: markdown
            ? 'Markdown on. Turn it off to edit this as plain text.'
            : 'Markdown. Turn it on to format this note.',
        child: Material(
          key: markdownToggleKey,
          color: markdown
              ? colors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    markdown
                        ? Icons.visibility
                        : Icons.visibility_outlined,
                    size: 15,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Preview',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: markdown ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}