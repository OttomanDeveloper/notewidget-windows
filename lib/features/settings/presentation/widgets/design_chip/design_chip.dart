import 'package:flutter/material.dart';

/// One choice. A chip rather than a preview swatch on purpose: a swatch would
/// have to draw the design, and a 24px drawing of a ticket is not a ticket.
class DesignChip extends StatelessWidget {
  const DesignChip({
    super.key,
    required this.label,
    required this.chosen,
    required this.onTap,
    required this.color,
  });

  final String label;
  final bool chosen;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: chosen,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: chosen ? color.withValues(alpha: 0.16) : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: chosen ? color : theme.colorScheme.outlineVariant,
              width: chosen ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
              color: chosen ? color : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}