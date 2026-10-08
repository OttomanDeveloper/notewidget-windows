import 'package:flutter/material.dart';

/// The chip that clears the skin. Shows a reset rather than a colour of its
/// own: "no skin" means "what the app has always looked like", and a grey box
/// would claim otherwise.
class NoneSwatch extends StatelessWidget {
  const NoneSwatch({
    super.key,
    required this.isSelected,
    required this.onTap,
  });

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'No skin',
      child: Tooltip(
        message: 'Default',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 52,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Icon(
              Icons.format_color_reset_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
