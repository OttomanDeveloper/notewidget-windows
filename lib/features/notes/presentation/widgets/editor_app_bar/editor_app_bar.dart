import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../brand_glyph/brand_glyph.dart';

/// The editor's bar: the mark, the overflow menu, and the list toggle.
///
/// Stateless, with behaviour crossing as callbacks: showing the list is a
/// `ValueNotifier` owned by the screen, and opening settings or importing is
/// work the app does, not state this bar holds.
class EditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EditorAppBar({
    super.key,
    required this.narrow,
    required this.showList,
    required this.onShowList,
    required this.onOpenSettings,
    required this.exportNotes,
    required this.importNotes,
  });

  final bool narrow;
  final bool showList;
  final VoidCallback onShowList;
  final VoidCallback onOpenSettings;
  final Future<void> Function() exportNotes;
  final Future<List<Note>?> Function() importNotes;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      titleSpacing: narrow ? 12 : 20,
      title: Row(
        children: [
          const BrandGlyph(size: 22),
          const SizedBox(width: 10),
          Text(
            'WinNotes',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          if (!narrow) ...[
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
      actions: [
        if (narrow && !showList)
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Show notes',
            onPressed: onShowList,
          ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'settings':
                onOpenSettings();
              case 'export':
                await exportNotes();
              case 'import':
                await importNotes();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'settings',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.settings_outlined, size: 18),
                title: Text('Settings'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'export',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.file_upload_outlined, size: 18),
                title: Text('Export as text'),
              ),
            ),
            PopupMenuItem(
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
