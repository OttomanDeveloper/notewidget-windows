import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/note.dart';
import '../../data/notes_repository.dart';
import '../../state/notes_controller.dart';
import '../../state/providers.dart';
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
class EditorView extends ConsumerStatefulWidget {
  const EditorView({
    super.key,
    required this.onOpenSettings,
    required this.exportNotes,
    required this.importNotes,
  });

  /// A callback, not a controller.
  ///
  /// All three of these are allowed to cross as parameters (`AGENTS.md` §0.8) because
  /// they are behaviour, not state: a function that opens a dialog does not rebuild
  /// when the settings change. What *is* state - the notes, the corrupt-file state,
  /// the channel - is read with `ref`.
  final VoidCallback onOpenSettings;
  final Future<void> Function() exportNotes;
  final Future<List<Note>?> Function() importNotes;

  static const double _narrowBreakpoint = 760;

  @override
  ConsumerState<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends ConsumerState<EditorView> {
  /// Which pane a *narrow* editor is showing.
  ///
  /// A `ValueNotifier` rather than a field on this State, and that is the whole
  /// replacement for six `setState` calls. The line is lifetime: this is true for as
  /// long as the editor stays narrow, and nothing else in the app asks - but it is
  /// not shared either, so it does not belong in a provider where a second reader
  /// would find it and a test would have to seed it.
  ///
  /// Read through a `ValueListenableBuilder` in [build], which rebuilds only the
  /// part of the tree that depends on it.
  final ValueNotifier<bool> _showListOnNarrow = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _showListOnNarrow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider);
    final shell = ref.read(shellProvider);
    final notifier = ref.read(notesProvider.notifier);

    final corrupt = notes.value?.corrupt;
    if (corrupt != null) {
      return CorruptNotesScreen(
        error: corrupt,
        hasBackup: notifier.hasBackup,
        onRestore: widget.importNotes,
        onReveal: () => shell.revealPath(corrupt.path),
        onRestoreBackup: notifier.restoreBackup,
        onRetry: notifier.retryLoad,
        onStartFresh: notifier.startFresh,
      );
    }

    // Still loading. A blank frame beats a frame that says "no notes" and then
    // corrects itself - which is exactly the first-launch bug in `AGENTS.md` §5.1,
    // and the reason the loading case is drawn at all.
    if (!notes.hasValue) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < EditorView._narrowBreakpoint;

        return ValueListenableBuilder<bool>(
          valueListenable: _showListOnNarrow,
          builder: (context, showListOnNarrow, _) {
            final showList = !narrow || showListOnNarrow;
            return Scaffold(
              appBar: _buildAppBar(context, narrow, showList),
              body: narrow
                  ? _buildNarrow(showList)
                  : Row(
                      children: [
                        SizedBox(
                          width: 300,
                          child: NoteListPane(
                            onOpenNote: () => _showListOnNarrow.value = false,
                            onNewNote: () {
                              notifier.createNote();
                              if (narrow) _showListOnNarrow.value = false;
                              _focusBody();
                            },
                            onCloseList: () {},
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                        const Expanded(child: NoteEditorPane()),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildNarrow(bool showList) {
    final notifier = ref.read(notesProvider.notifier);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: showList
          ? NoteListPane(
              key: const ValueKey('list'),
              showCloseButton: false,
              onOpenNote: () => _showListOnNarrow.value = false,
              onNewNote: () {
                notifier.createNote();
                _showListOnNarrow.value = false;
                _focusBody();
              },
              onCloseList: () {},
            )
          : NoteEditorPane(
              key: const ValueKey('editor'),
              onBack: () => _showListOnNarrow.value = true,
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
            onPressed: () => _showListOnNarrow.value = true,
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
class CorruptNotesScreen extends ConsumerStatefulWidget {
  const CorruptNotesScreen({
    super.key,
    required this.error,
    required this.onRestore,
    required this.onReveal,
    required this.onRestoreBackup,
    required this.onRetry,
    required this.onStartFresh,
    required this.hasBackup,
  });

  final CorruptDataFileError error;
  final Future<List<Note>?> Function() onRestore;
  final VoidCallback onReveal;
  final Future<RecoveryOutcome> Function() onRestoreBackup;
  final Future<void> Function() onRetry;
  final Future<({RecoveryOutcome outcome, String? keptAt})> Function() onStartFresh;
  final bool hasBackup;

  @override
  ConsumerState<CorruptNotesScreen> createState() => _CorruptNotesScreenState();
}

class _CorruptNotesScreenState extends ConsumerState<CorruptNotesScreen> {
  /// Whether a recovery action is running, and what it last said.
  ///
  /// Two fields rather than one, because they answer different questions and the
  /// screen shows them differently: `_busy` disables every button, `_message` is
  /// read after the action finishes. Folding them into one enum would mean every
  /// message doubled as a "still busy" state, which is wrong the moment two messages
  /// can be showing - or none.
  ///
  /// A `ValueNotifier` and not a provider: this state is true for the length of one
  /// button press and nobody outside this screen will ever ask whether it is true.
  /// That is the `ValueNotifier` half of `AGENTS.md` §0.7.
  final ValueNotifier<bool> _busy = ValueNotifier<bool>(false);
  final ValueNotifier<String?> _message = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _busy.dispose();
    _message.dispose();
    super.dispose();
  }

  /// Runs a recovery action with the buttons disabled and the old message cleared.
  ///
  /// `_busy` is set before the first `await` and cleared in a `finally`, so a thrown
  /// error cannot leave the screen permanently disabled - which is the failure a
  /// `setState` version had available to it and could not have.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy.value) return;
    _busy.value = true;
    _message.value = null;
    try {
      await action();
    } finally {
      _busy.value = false;
    }
  }

  Future<void> _restoreBackup() => _run(() async {
        final outcome = await widget.onRestoreBackup();
        if (!mounted) return;
        _message.value = switch (outcome) {
          RecoveryOutcome.restoredBackup =>
            'Restored the previous version of your notes.',
          RecoveryOutcome.nothingToRecover =>
            'There is no earlier version to go back to.',
          RecoveryOutcome.startedFresh => null,
          RecoveryOutcome.fileIsHeld =>
            'Something else is holding the file. Try again in a moment.',
        };
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
      _message.value = switch (result.outcome) {
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
                ValueListenableBuilder<String?>(
                  valueListenable: _message,
                  builder: (context, message, _) => message == null
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            Text(
                              message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                ),
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
                        onPressed: _busy.value ? null : _restoreBackup,
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('Restore the previous version'),
                      ),
                    if (transient)
                      FilledButton.icon(
                        onPressed: _busy.value ? null : () => _run(widget.onRetry),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Try again'),
                      ),
                    if (!widget.hasBackup && !transient)
                      FilledButton.icon(
                        onPressed: _busy.value
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
                        onPressed: _busy.value
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
                      onPressed: _busy.value ? null : widget.onReveal,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Open the folder'),
                    ),
                    TextButton(
                      onPressed: _busy.value ? null : _startFresh,
                      child: const Text('Start fresh instead'),
                    ),
                    TextButton(
                      onPressed: _busy.value ? null : () => ref.read(shellProvider).quit(),
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
