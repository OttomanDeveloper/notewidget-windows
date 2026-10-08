import 'package:flutter/material.dart';

/// The thin strip left on the edge when the note list is collapsed. There
/// is a handle as well as the app bar button: the list is hidden *to write*,
/// so the user is looking at the editor, not the toolbar.
class ListDrawerHandle extends StatelessWidget {
  const ListDrawerHandle({super.key, required this.onExpand});

  final VoidCallback onExpand;

  /// Wide enough to hit without aiming, narrow enough that it does not read as
  /// a panel that failed to open.
  static const double width = 16;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: 'Show notes',
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: 'Show notes',
          child: InkWell(
            onTap: onExpand,
            // Full height, so the whole edge opens it and not just the icon.
            child: SizedBox(
              width: ListDrawerHandle.width,
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: Center(
                  child: Icon(
                    Icons.list,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
