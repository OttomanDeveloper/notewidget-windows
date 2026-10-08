import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../brand_glyph/brand_glyph.dart';

/// The editor's bar: mark, menu, list toggle. Stateless; behaviour crosses as
/// callbacks, state arrives via `ref`.
class EditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EditorAppBar({
    super.key,
    required this.narrow,
    required this.showList,
    required this.onToggleList,
    required this.onOpenSettings,
    required this.exportNotes,
    required this.importNotes,
  });

  final bool narrow;
  final bool showList;

  /// Shown only while the list is hidden. Narrow, that means going back to it;
  /// wide, that means expanding the collapsed drawer.
  final VoidCallback onToggleList;
  final VoidCallback onOpenSettings;
  final Future<void> Function() exportNotes;
  final Future<List<Note>?> Function() importNotes;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppBar(
      titleSpacing: narrow ? 12 : 20,
      title: Row(
        children: <Widget>[
          const BrandGlyph(size: 22),
          const SizedBox(width: 10),
          Text(
            'WinNotes',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          if (!narrow) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              'Everything lives on this PC',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        // Narrow: the button goes back to the list. Wide: it collapses the list.
        // Two flat branches, not `if (narrow) if (...) A else B` - the `else`
        // binds to the *inner* if, which left wide with no button at all.
        if (narrow && !showList)
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Show notes',
            onPressed: onToggleList,
          )
        else if (!narrow)
          IconButton(
            icon: const Icon(Icons.menu_open),
            tooltip: showList ? 'Hide notes' : 'Show notes',
            onPressed: onToggleList,
          ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (String value) async {
            switch (value) {
              case 'settings':
                onOpenSettings();
              case 'export':
                await exportNotes();
              case 'import':
                await importNotes();
            }
          },
          itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'settings',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.settings_outlined, size: 18),
                title: Text('Settings'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'export',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.file_upload_outlined, size: 18),
                title: Text('Export as text'),
              ),
            ),
            PopupMenuItem<String>(
              value: 'import',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.file_download_outlined, size: 18),
                title: Text('Import from text'),
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
      backgroundColor: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: theme.dividerColor),
      ),
    );
  }
}
