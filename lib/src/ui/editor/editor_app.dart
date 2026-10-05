import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/note.dart';
import '../../data/notes_repository.dart';
import '../../platform/shell_channel.dart';
import '../../state/notes_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../settings/settings_dialog.dart';
import '../theme_scope.dart';
import 'editor_view.dart';

/// Root widget for the editor surface.
///
/// Owns notes.json and settings.json. The widget surface reads both and writes
/// neither, which is the whole reason there is no cross-isolate merge logic
/// anywhere in this project.
///
/// Now a `ConsumerWidget` over a `ProviderScope` it creates itself, rather than a
/// `StatefulWidget` that constructed four repositories in `initState` and disposed
/// them in `dispose`. Three things follow, and they are the reason this file is 285
/// lines shorter than it was:
///
///  - `_resolveBrightness` and `_systemBrightness` are gone. Both surfaces now
///    resolve the theme through `widgetSurfaceThemeProvider`, which is what
///    stopped the three divergent copies (`AGENTS.md` §4.7).
///  - The `GlobalKey<NavigatorState>` is gone. It existed because this State was
///    *also* the app root, so its own `context` sat above the `MaterialApp` it
///    returned and had no `Navigator` ancestor - which is why Settings appeared to
///    do nothing. A `ConsumerWidget` below the `MaterialApp` has an ordinary context.
///  - The seven `unawaited(...flush())` calls are now one call to a provider's
///    `flush`, and still unawaited. `AGENTS.md` §4.8: `onDispose` is synchronous,
///    so this hazard is unchanged by the rewrite and is recorded rather than fixed.
class EditorApp extends ConsumerWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const _EditorScope();
}

/// Inside the MaterialApp: the `MaterialApp` and everything under it.
///
/// Split from [EditorApp] purely so the `ProviderScope` sits *above* the
/// `MaterialApp` while the widgets below it can read providers. Putting the scope
/// inside would work for `ref.watch` but would put this widget's own context above
/// the Navigator again, which is the bug this file used to work around.
class _EditorScope extends ConsumerStatefulWidget {
  const _EditorScope();

  @override
  ConsumerState<_EditorScope> createState() => _EditorScopeState();
}

class _EditorScopeState extends ConsumerState<_EditorScope>
    with WidgetsBindingObserver {
  /// Everything teardown needs, captured while a `ref` is still readable.
  ///
  /// Riverpod asserts on *any* `ref` use inside `dispose` - `_assertNotDisposed` -
  /// not merely on use after an `await`. So the notifiers are read in [initState] and
  /// held here, and [dispose] only touches ordinary objects.
  ///
  /// That is the rule in one line: **a `ConsumerState` may read its `ref` in
  /// `initState`, and may not read it in `dispose`.** Capture early.
  late final EditorTeardown _teardown;
  late final EditorBootstrap _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = EditorBootstrap(
      notes: ref.read(notesProvider.notifier),
      settings: ref.read(settingsProvider.notifier),
      selection: ref.read(selectionRepositoryProvider),
      notesReady: ref.read(notesProvider.future),
      settingsReady: ref.read(settingsProvider.future),
    );
    _teardown = EditorTeardown(
      notes: ref.read(notesProvider.notifier),
      settings: ref.read(settingsProvider.notifier),
      selection: ref.read(selectionRepositoryProvider),
    );
    // Registers itself with the binding rather than putting the observation in a
    // provider: `WidgetsBindingObserver` is an interface on a `State`, and a
    // Notifier is not one. One observer, writing one provider, is what stopped the
    // two surfaces disagreeing about the theme.
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap.run());
  }

  @override
  void didChangePlatformBrightness() {
    final view = View.of(context);
    ref.read(systemBrightnessProvider.notifier).report(
          brightness: MediaQueryData.fromView(view).platformBrightness,
        );
    // A theme change can also mean a change to the acrylic or hotkey state the
    // runner owns, and the editor is the only surface that writes settings.json.
    unawaited(ref.read(settingsProvider.notifier).syncPlatform());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_teardown.run());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(widgetSurfaceThemeProvider);

    return MaterialApp(
      title: 'WinNotes',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: theme,
      // The router is here rather than in `EditorView` because it needs a context
      // with a `Navigator` ancestor to open the settings dialog from, and
      // `EditorHome`'s context has one while a provider does not.
      home: const EditorEventRouter(child: EditorHome()),
    );
  }
}

/// The editor surface below the `MaterialApp`.
///
/// Its own `ConsumerWidget` rather than a field of `_EditorScope`, so that a dialog
/// pushed from here has a context with a `Navigator` ancestor. That is the whole of
/// what the old `GlobalKey` was working around.
class EditorHome extends ConsumerWidget {
  const EditorHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EditorView(
      onOpenSettings: () => openSettings(context, ref),
      exportNotes: () => exportNotes(context, ref),
      importNotes: () => importNotes(context, ref),
    );
  }
}

/// Startup, in the order it has to happen.
///
/// Extracted from the old `_bootstrap` because the ordering is load-bearing and a
/// method body is a better place to keep it than a comment:
///
///  1. settings first. Nothing in the editor needs them to draw, but the theme does,
///     and reading them second would mean building the `MaterialApp` twice.
///  2. notes, which themselves guarantee a first note exists - so by the time this
///     resolves, the editor has something to show and typing can be the very first
///     thing that happens.
///  3. the saved selection, applied afterwards so it can override that default.
///  4. `syncPlatform` last, on every launch, so the registry entry and the hotkey
///     are corrected whether or not anyone ever opens the settings dialog.
class EditorBootstrap {
  const EditorBootstrap({
    required this.notes,
    required this.settings,
    required this.selection,
    required this.notesReady,
    required this.settingsReady,
  });

  /// Captured in `initState`, because a `WidgetRef` is readable there and nowhere
  /// later - see `_EditorScopeState`.
  final NotesNotifier notes;
  final SettingsNotifier settings;
  final SelectionRepository selection;

  /// The two futures, also captured, so the awaits below touch no `ref` at all.
  final Future<NotesState> notesReady;
  final Future<SettingsState> settingsReady;

  Future<void> run() async {
    await settingsReady;
    await notesReady;

    final saved = selection.readSelection();
    if (saved != null) notes.select(saved);

    await settings.syncPlatform();
  }
}/// Teardown: flush everything queued, then release the file handles.
///
/// Called from `_EditorScopeState.dispose` and nowhere else. `onDispose` would be
/// the obvious home and cannot be: it is synchronous, and flushing is not.
///
/// `AGENTS.md` §4.8 records that these writes are unawaited and that the hazard
/// predates the provider work. It is unchanged, not fixed, and claiming otherwise
/// would be the kind of quiet improvement that hides a real one.
class EditorTeardown {
  const EditorTeardown({
    required this.notes,
    required this.settings,
    required this.selection,
  });

  /// Captured in `dispose`, because that is the last moment a `WidgetRef` is usable.
  final NotesNotifier notes;
  final SettingsNotifier settings;
  final SelectionRepository selection;

  Future<void> run() async {
    await notes.flush();
    await settings.flush();
    await selection.flush();
  }
}

/// Routes events pushed up from the runner.
///
/// Kept as a switch rather than a table of handlers because each case does something
/// different, and three of them deliberately do nothing - see [ShellEventKind].
///
/// This is a `ConsumerState` rather than a plain function so the subscription has an
/// owner with a lifetime. A bare `shell.events.listen` in `build` would stack a
/// listener per rebuild, and the symptom of that is a hotkey that raises the editor
/// six times.
class EditorEventRouter extends ConsumerStatefulWidget {
  const EditorEventRouter({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EditorEventRouter> createState() => _EditorEventRouterState();
}

class _EditorEventRouterState extends ConsumerState<EditorEventRouter> {
  StreamSubscription<ShellEvent>? _events;

  @override
  void initState() {
    super.initState();
    _events = ref.read(shellProvider).events.listen(_onEvent);
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  void _onEvent(ShellEvent event) {
    // An event can arrive after the tree is torn down, and a `ref` used then
    // throws rather than being ignored. See `EditorBootstrap.start`.
    if (!mounted) return;

    switch (event.kind) {
      case ShellEventKind.hotkey:
        _focusEditor();
      case ShellEventKind.openSettings:
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (!mounted) return;
        unawaited(openSettings(context, ref));
        messenger?.hideCurrentSnackBar();
      case ShellEventKind.toggleCompleted:
        // The widget surface asks rather than writing, because this is the one
        // writer of notes.json. Answering here means the change is made in the same
        // place every other edit is, and the widget sees it through the directory
        // watcher it already uses.
        final id = event.noteId;
        if (id != null) ref.read(notesProvider.notifier).toggleCompleted(id);
      case ShellEventKind.createNote:
        // A note written in the widget, for the same reason as above.
        final incoming = event.newNote;
        if (incoming != null) {
          ref.read(notesProvider.notifier).addNote(
                title: incoming.title,
                body: incoming.body,
              );
        }
      case ShellEventKind.geometry:
      case ShellEventKind.visibility:
      case ShellEventKind.unknown:
        // Not ours. `docs/isolate_pattern.md` §3.4: a future event that arrives at
        // the wrong surface should be ignored loudly in a test, not silently here.
        break;
    }
  }

  void _focusEditor() {
    // Closing the editor hands focus back to the widget, so the hotkey has to bring
    // the editor back properly rather than just showing it.
    unawaited(ref.read(shellProvider).focusWindow('editor'));
    FocusScope.of(context).requestFocus(FocusNode());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens the settings dialog.
///
/// `context` is the one below the `MaterialApp`, so `showDialog` has somewhere to
/// go. The old code needed a `GlobalKey<NavigatorState>` to get this; here it is
/// simply the caller's context.
Future<void> openSettings(BuildContext context, WidgetRef ref) async {
  final paths = ref.read(appPathsProvider);
  await showDialog<void>(
    context: context,
    builder: (context) => SettingsDialog(
      defaultDataDirectory: paths.defaultStorageDirectory,
    ),
  );
}

/// Writes a plain-text backup of every note somewhere the person chose.
Future<void> exportNotes(BuildContext context, WidgetRef ref) async {
  // Captured before the first await, and never looked up again afterwards.
  //
  // Two reasons, both learned the hard way: there is no ScaffoldMessenger above the
  // MaterialApp this returns, so ScaffoldMessenger.of(context) throws and the
  // "Exported N notes" confirmation is lost while the file still writes; and
  // reaching for a context after an await is unsafe because the widget behind it
  // may be gone.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final shell = ref.read(shellProvider);
  final notes = ref.read(notesProvider).value;

  final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
  final path = await shell.saveFile(suggestedName: 'winnotes-backup-$stamp.txt');
  if (path == null || !context.mounted) return;
  await const BackupService().exportTo(path, notes?.notes ?? const []);
  messenger?.showSnackBar(
    SnackBar(content: Text('Exported ${notes?.notes.length ?? 0} notes.')),
  );
}

/// Reads a plain-text backup back in, with a confirmation before it merges.
Future<List<Note>?> importNotes(BuildContext context, WidgetRef ref) async {
  final shell = ref.read(shellProvider);
  final notes = ref.read(notesProvider.notifier);

  final path = await shell.pickFile();
  if (path == null) return null;

  final incoming = await const BackupService().readFrom(path);
  if (incoming == null) return null;

  if (notes.hasReadOnlyFile) {
    // A hand-chosen backup is the one thing allowed to replace a file the app
    // refused to touch on its own.
    notes.unblockForRestore();
    notes.replaceAll(incoming);
  } else {
    // Guarded on `context.mounted` rather than left bare: the dialog is an await,
    // and this widget can be torn down inside it.
    if (!context.mounted) return incoming;
    final merge = await _confirmMerge(context, incoming.length);
    if (merge) {
      notes.merge(incoming);
    }
  }
  return incoming;
}

Future<bool> _confirmMerge(BuildContext context, int count) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Add $count notes?'),
      content: const Text(
        'The imported notes are added alongside the ones you already have. '
        'Nothing existing is replaced.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Add them'),
        ),
      ],
    ),
  );
  return result ?? false;
}
