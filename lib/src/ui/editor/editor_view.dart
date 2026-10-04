import 'package:flutter/material.dart';

import '../../data/note.dart';
import '../../data/notes_repository.dart';
import '../../platform/shell_channel.dart';
import '../../state/notes_controller.dart';
import '../common/widgets.dart';
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
            hasBackup: controller.hasBackup,
            onRestore: widget.importNotes,
            onReveal: () => widget.shell.revealPath(controller.corrupt!.path),
            onRestoreBackup: controller.restoreBackup,
            onRetry: controller.retryLoad,
            onStartFresh: controller.startFresh,
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
/// The app refuses to start rather than replacing the file with an empty one,
/// and that refusal is only defensible if every screen has a way out. This one
/// offers four, in the order they are worth trying:
///
/// 1. Put the rolling backup back. Costs the person nothing - no backup they had
///    to remember to make, no file to go and find - and since writes are atomic,
///    the backup is a file this app wrote itself.
/// 2. Try again, when the file is merely being held open. Antivirus holding a
///    file for a moment is not damage, and treating it as damage is both alarming
///    and wrong.
/// 3. Restore from a backup they chose.
/// 4. Start fresh, keeping the damaged file under a new name.
///
/// The last one used to exist only as a sentence of small print at the bottom,
/// telling someone to rename a file in Explorer by hand and restart. That is the
/// right instruction for someone who reads it calmly and the wrong experience for
/// someone whose notes have just failed them, so it is a button now.
class CorruptNotesScreen extends StatefulWidget {
  const CorruptNotesScreen({
    super.key,
    required this.error,
    required this.shell,
    required this.onRestore,
    required this.onReveal,
    required this.onRestoreBackup,
    required this.onRetry,
    required this.onStartFresh,
    required this.hasBackup,
  });

  final CorruptDataFileError error;
  final ShellChannel shell;
  final Future<List<Note>?> Function() onRestore;
  final VoidCallback onReveal;
  final Future<RecoveryOutcome> Function() onRestoreBackup;
  final Future<void> Function() onRetry;
  final Future<({RecoveryOutcome outcome, String? keptAt})> Function() onStartFresh;
  final bool hasBackup;

  @override
  State<CorruptNotesScreen> createState() => _CorruptNotesScreenState();
}

class _CorruptNotesScreenState extends State<CorruptNotesScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() => _run(() async {
        final outcome = await widget.onRestoreBackup();
        if (!mounted) return;
        setState(() {
          _message = switch (outcome) {
            RecoveryOutcome.restoredBackup =>
              'Restored the previous version of your notes.',
            RecoveryOutcome.nothingToRecover =>
              'There is no earlier version to go back to.',
            RecoveryOutcome.startedFresh => null,
            RecoveryOutcome.fileIsHeld =>
              'Something else is holding the file. Try again in a moment.',
          };
        });
      });

  Future<void> _startFresh() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Start fresh?',
      message: 'The file that cannot be read will be kept, renamed with today\'s '
          'time on the end, so nothing is thrown away. WinNotes then starts a new '
          'empty notes file beside it.',
      confirmLabel: 'Keep it and start fresh',
      cancelLabel: 'Go back',
    );
    if (!confirmed || !mounted) return;

    await _run(() async {
      final result = await widget.onStartFresh();
      if (!mounted) return;
      setState(() {
        _message = switch (result.outcome) {
          RecoveryOutcome.startedFresh => result.keptAt == null
              ? 'The unreadable file was already gone. Starting a new one.'
              : 'The unreadable file was kept as '
                  '"${result.keptAt!.split('\\').last}".',
          RecoveryOutcome.fileIsHeld =>
            'Something else is holding the file, so it could not be moved aside. '
                'Try again in a moment.',
          RecoveryOutcome.restoredBackup => null,
          RecoveryOutcome.nothingToRecover => null,
        };
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transient = widget.error.transient;
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
                    Icon(
                      transient ? Icons.hourglass_top_rounded : Icons.warning_amber_rounded,
                      color: transient ? theme.colorScheme.tertiary : theme.colorScheme.error,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        transient
                            ? 'Something is holding your notes file'
                            : 'Your notes file could not be read',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  transient
                      ? 'WinNotes has not changed anything on disk. This is usually '
                          'antivirus, a backup tool or a sync app looking at the file '
                          'at this moment - your notes are almost certainly fine and '
                          'will open as soon as it lets go.'
                      : 'WinNotes has not changed anything on disk. It stopped rather '
                          'than start with an empty list, because notes that were '
                          'never read are worse than notes that take a moment longer '
                          'to open.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _DetailCard(error: widget.error),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _message!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // First, because it is the only route that asks nothing of the
                    // person holding the problem. Hidden rather than disabled when
                    // there is no backup: a greyed-out button invites the question
                    // "of what?", and the honest answer is easier to just not ask.
                    if (widget.hasBackup)
                      FilledButton.icon(
                        onPressed: _busy ? null : _restoreBackup,
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('Restore the previous version'),
                      ),
                    if (transient)
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _run(widget.onRetry),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Try again'),
                      ),
                    if (!widget.hasBackup && !transient)
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                  final restored = await widget.onRestore();
                                  if (restored != null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('Restored ${restored.length} notes.')),
                                    );
                                  }
                                }),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Restore from a backup'),
                      ),
                    if (widget.hasBackup)
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                  final restored = await widget.onRestore();
                                  if (restored != null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text('Restored ${restored.length} notes.')),
                                    );
                                  }
                                }),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Restore from a backup'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : widget.onReveal,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Open the folder'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _startFresh,
                      child: const Text('Start fresh instead'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => widget.shell.quit(),
                      child: const Text('Quit'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Nothing here deletes anything. Starting fresh keeps the file that '
                  'could not be read, renamed with the time on the end, in the same '
                  'folder.',
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
          if (NotesRepository.describeFile(error.path) case final details?) ...[
            const SizedBox(height: 12),
            Text(
              '${details.bytes} bytes, last changed '
              '${_stamp(details.changed)}',
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
