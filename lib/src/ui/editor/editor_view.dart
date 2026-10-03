import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/note.dart';
import '../../platform/shell_channel.dart';
import '../../state/notes_controller.dart';
import '../theme.dart';
import 'note_editor_pane.dart';
import 'note_list_pane.dart';

/// The editor window.
///
/// Two panes on a wide window, one at a time on a narrow one. The break is on
/// width rather than on a device check, because the editor can be resized
/// freely and a pane layout that breaks at 700px is worse than one that
/// responds to it.
class EditorView extends StatefulWidget {
  const EditorView({
    super.key,
    required this.controller,
    required this.shell,
    required this.onOpenSettings,
    required this.exportNotes,
    required this.importNotes,
  });

  final NotesController controller;
  final ShellChannel shell;
  final VoidCallback onOpenSettings;
  final Future<void> Function() exportNotes;
  final Future<List<Note>?> Function() importNotes;

  static const double _narrowBreakpoint = 760;

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  bool _showListOnNarrow = true;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.corrupt != null) {
          return CorruptNotesScreen(
            error: controller.corrupt!,
            shell: widget.shell,
            onRestore: widget.importNotes,
            onReveal: () => widget.shell.revealPath(controller.corrupt!.path),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < EditorView._narrowBreakpoint;
            final showList = !narrow || _showListOnNarrow;

            return Scaffold(
              appBar: _buildAppBar(context, narrow, showList),
              body: narrow
                  ? _buildNarrow(showList)
                  : Row(
                      children: [
                        SizedBox(
                          width: 300,
                          child: NoteListPane(
                            controller: controller,
                            onOpenNote: () => setState(() => _showListOnNarrow = false),
                            onNewNote: () {
                              controller.createNote();
                              if (narrow) setState(() => _showListOnNarrow = false);
                              _focusBody();
                            },
                            onCloseList: () {},
                          ),
                        ),
                        VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
                        Expanded(
                          child: NoteEditorPane(
                            controller: controller,
                          ),
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildNarrow(bool showList) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: showList
          ? NoteListPane(
              key: const ValueKey('list'),
              controller: widget.controller,
              showCloseButton: false,
              onOpenNote: () => setState(() => _showListOnNarrow = false),
              onNewNote: () {
                widget.controller.createNote();
                setState(() => _showListOnNarrow = false);
                _focusBody();
              },
              onCloseList: () {},
            )
          : NoteEditorPane(
              key: const ValueKey('editor'),
              controller: widget.controller,
              onBack: () => setState(() => _showListOnNarrow = true),
            ),
    );
  }

  void _focusBody() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(FocusNode());
    });
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool narrow, bool showList) {
    final theme = Theme.of(context);
    return AppBar(
      titleSpacing: narrow ? 12 : 20,
      title: Row(
        children: [
          _BrandGlyph(size: 22),
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
            onPressed: () => setState(() => _showListOnNarrow = true),
          ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'settings':
                widget.onOpenSettings();
              case 'export':
                await widget.exportNotes();
              case 'import':
                await widget.importNotes();
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

/// The app's mark, drawn from the same geometry as the icon file.
class _BrandGlyph extends StatelessWidget {
  const _BrandGlyph({this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [WinNotesColors.indigoDeep, Color(0xFF332A6B), WinNotesColors.indigo],
          ),
        ),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.56,
            heightFactor: 0.56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WinNotesColors.parchment,
                borderRadius: BorderRadius.circular(size * 0.14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the editor when notes.json exists but cannot be read.
///
/// The app refuses to start rather than replacing the file with an empty one.
/// This screen is that refusal made visible, with the two ways out: point at a
/// backup, or go and look at the file by hand.
class CorruptNotesScreen extends StatelessWidget {
  const CorruptNotesScreen({
    super.key,
    required this.error,
    required this.shell,
    required this.onRestore,
    required this.onReveal,
  });

  final CorruptDataFileError error;
  final ShellChannel shell;
  final Future<List<Note>?> Function() onRestore;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: theme.colorScheme.error, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your notes file could not be read',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'WinNotes has not changed anything on disk. It stopped rather '
                  'than start with an empty list, because notes that were never '
                  'read are worse than notes that take a moment longer to open.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _DetailCard(error: error),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        final restored = await onRestore();
                        if (restored != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Restored ${restored.length} notes.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Restore from a backup'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onReveal,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Open the folder'),
                    ),
                    TextButton(
                      onPressed: () => shell.quit(),
                      child: const Text('Quit'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'If you would rather keep this exact file and start fresh, '
                  'rename it to notes.json.broken and WinNotes will create a new '
                  'one on the next launch.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.error});
  final CorruptDataFileError error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('File', style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          SelectableText(
            error.path,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Consolas'),
          ),
          const SizedBox(height: 12),
          Text('Problem', style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(error.reason, style: theme.textTheme.bodySmall),
          if (File(error.path).existsSync()) ...[
            const SizedBox(height: 12),
            Text(
              '${File(error.path).lengthSync()} bytes, last changed '
              '${_stamp(File(error.path).lastModifiedSync())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _stamp(DateTime when) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${when.year}-${two(when.month)}-${two(when.day)} '
        '${two(when.hour)}:${two(when.minute)}';
  }
}