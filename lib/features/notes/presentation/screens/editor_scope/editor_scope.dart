import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/app_providers.dart';
import '../../../domain/repositories.dart';
import '../../providers/notes_controller.dart';
import '../../providers/notes_providers.dart';
import '../../../../settings/presentation/providers/settings_controller.dart';
import '../../../../settings/presentation/providers/settings_providers.dart';
import '../editor_event_router/editor_event_router.dart';
import '../editor_home/editor_home.dart';

/// Inside the MaterialApp: the `MaterialApp` and everything under it.
///
/// Split from [EditorApp] purely so the `ProviderScope` sits *above* the
/// `MaterialApp` while the widgets below it can read providers. Putting the scope
/// inside would work for `ref.watch` but would put this widget's own context above
/// the Navigator again, which is the bug this file used to work around.
class EditorScope extends ConsumerStatefulWidget {
  const EditorScope({super.key});

  @override
  ConsumerState<EditorScope> createState() => EditorScopeState();
}

class EditorScopeState extends ConsumerState<EditorScope>
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
  /// later - see `EditorScopeState`.
  final NotesNotifier notes;
  final SettingsNotifier settings;
  final ISelectionRepository selection;

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
/// Called from `EditorScopeState.dispose` and nowhere else. `onDispose` would be
/// the obvious home and cannot be: it is synchronous, and flushing is not.
///
/// `AGENTS.md` §4.7 records that these writes are unawaited and that the hazard
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
  final ISelectionRepository selection;

  Future<void> run() async {
    await notes.flush();
    await settings.flush();
    await selection.flush();
  }
}
