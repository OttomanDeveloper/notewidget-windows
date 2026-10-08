import 'package:flutter/material.dart';

import '../../../../../core/theme/skin.dart';

/// One row in a skin chip's preview, drawn in that skin's shape. Its own file
/// because one file declares one widget (`flutter_architecture_pattern.md` §3.2).
class SkinPreviewRow extends StatelessWidget {
  const SkinPreviewRow({
    super.key,
    required this.look,
    required this.marked,
    required this.accent,
  });

  final SkinLook look;
  final bool marked;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 8,
      // A `Border` with one coloured side cannot carry a `borderRadius`: Flutter
      // rejects non-uniform colours on a rounded border. So the bar is a child.
      decoration: BoxDecoration(
        color: switch (look.focus) {
          SkinFocus.fill when marked => accent.withValues(alpha: 0.35),
          SkinFocus.bar when marked => accent.withValues(alpha: 0.14),
          _ => Colors.transparent,
        },
        borderRadius: look.shape,
        border: marked && look.focus == SkinFocus.outline
            ? Border.all(color: accent, width: 1)
            : Border.all(color: theme.colorScheme.outlineVariant, width: 0.5),
      ),
      child: marked && look.focus == SkinFocus.bar
          ? Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 2, color: accent),
            )
          : null,
    );
  }
}
