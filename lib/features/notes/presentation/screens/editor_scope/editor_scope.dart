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

/// Inside the MaterialApp. Split from [EditorApp] so the `ProviderScope` sits above
/// the `MaterialApp` while widgets below still read providers.
class EditorScope extends ConsumerStatefulWidget {
  const EditorScope({super.key});

  @override
  ConsumerState<EditorScope> createState() => EditorScopeState();
}

class EditorScopeState extends ConsumerState<EditorScope>
    with WidgetsBindingObserver {
    /// Teardown captured while `ref` is readable: Riverpod asserts on any `ref` in
    /// `dispose`, so notifiers are read in [initState] and only objects in [dispose].
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
    // Observes on the State (a Notifier can't): one observer writing one
    // provider is what stopped the two surfaces disagreeing about the theme.
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

/// Startup in load order: settings (theme), notes (first note), selection, then
/// `syncPlatform` to correct the registry entry and hotkey every launch.
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
/// From `EditorScopeState.dispose` only; `onDispose` can't host it (synchronous).
/// Unawaited-write hazard recorded in `AGENTS.md` §4.7, unchanged not fixed.
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
