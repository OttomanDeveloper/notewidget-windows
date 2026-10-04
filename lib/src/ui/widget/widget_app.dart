import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_paths.dart';
import '../../core/atomic_json_file.dart';
import '../../data/notes_repository.dart';
import '../../data/settings_repository.dart';
import '../../platform/shell_channel.dart';
import '../../state/settings_controller.dart';
import '../../state/widget_controller.dart';
import '../theme.dart';
import 'widget_surface.dart';

/// Root widget for the widget surface.
///
/// Runs in its own isolate, reads the same files the editor writes, and never
/// writes notes. There is one writer per file in this app and this side owns
/// only `widget_state.json`.
class WidgetApp extends StatefulWidget {
  const WidgetApp({
    super.key,
    required this.shell,
    required this.launch,
    required this.paths,
  });

  final ShellChannel shell;
  final LaunchInfo launch;
  final AppPaths paths;

  @override
  State<WidgetApp> createState() => _WidgetAppState();
}

class _WidgetAppState extends State<WidgetApp> with WidgetsBindingObserver {
  late final NotesRepository _notesRepo;
  late final WidgetStateRepository _widgetRepo;
  late final SelectionRepository _selectionRepo;
  late final SettingsController _settings;
  late final WidgetController _controller;
  StreamSubscription<ShellEvent>? _events;

  Brightness _brightness = Brightness.light;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final notesRepo = NotesRepository(AtomicJsonFile(widget.paths.notesFile));
    final settingsRepo = SettingsRepository(
      AtomicJsonFile(widget.paths.settingsFile),
      widget.shell,
    );
    final widgetRepo = WidgetStateRepository(
      AtomicJsonFile(widget.paths.widgetStateFile),
    );
    final selectionRepo = SelectionRepository(
      AtomicJsonFile(widget.paths.selectionFile),
    );

    _notesRepo = notesRepo;
    _widgetRepo = widgetRepo;
    _selectionRepo = selectionRepo;

    _settings = SettingsController(
      repository: settingsRepo,
      shell: widget.shell,
      watchExternal: true,
    );
    await _settings.load(
      animationsEnabled: widget.launch.animationsEnabled,
      acrylicSupported: widget.launch.acrylicSupported,
    );

    _brightness = _resolveBrightness();

    _controller = WidgetController(
      shell: widget.shell,
      settings: _settings,
      notesRepo: notesRepo,
      widgetRepo: widgetRepo,
      selectionRepo: selectionRepo,
      isAutostartLaunch: widget.launch.isAutostartLaunch,
      animationsEnabled: widget.launch.animationsEnabled,
      acrylicSupported: widget.launch.acrylicSupported,
      isSystemDark: widget.launch.isSystemDark,
    );

    await _controller.load();

    // Only the autostart launch waits. Launching by hand shows the widget at
    // once, because someone who just clicked the icon is already looking.
    await _controller.applyStartupDelay();
    await _controller.restoreGeometry();

    _events = widget.shell.events.listen(_onEvent);

    if (mounted) setState(() => _ready = true);
  }

  Brightness _resolveBrightness() {
    final mode = _settings.settings.themeMode;
    if (mode == ThemeMode.light) return Brightness.light;
    if (mode == ThemeMode.dark) return Brightness.dark;
    return widget.launch.isSystemDark ? Brightness.dark : Brightness.light;
  }

  void _onEvent(ShellEvent event) {
    switch (event.kind) {
      case ShellEventKind.hotkey:
        // The editor may not have been created on an autostart launch, so ask
        // the runner to raise it rather than assuming it exists.
        unawaited(widget.shell.showEditor());
      case ShellEventKind.geometry:
        final bounds = event.bounds;
        if (bounds != null) _controller.onGeometryChanged(bounds);
      case ShellEventKind.visibility:
        _controller.setWidgetVisibleFromPlatform(event.isVisible);
      case ShellEventKind.openSettings:
        unawaited(widget.shell.openSettings());
      case ShellEventKind.toggleCompleted:
        // Only ever sent to the editor, which owns notes.json. Arriving here
        // would mean the runner routed a write request to the wrong isolate, and
        // re-applying it would put two writers on one file - the exact thing the
        // routing exists to prevent. Notes reach this surface through the
        // directory watcher instead.
        break;
      case ShellEventKind.createNote:
        // Same reasoning: the widget asks, the editor writes.
        break;
      case ShellEventKind.unknown:
        break;
    }
  }

  @override
  void didChangePlatformBrightness() {
    // Windows changed between light and dark while the app was running.
    final systemDark = MediaQueryData.fromView(View.of(context)).platformBrightness == Brightness.dark;
    setState(() {
      _brightness = _resolveBrightnessFor(systemDark);
    });
    unawaited(_settings.syncPlatform());
  }

  Brightness _resolveBrightnessFor(bool systemDark) {
    final mode = _settings.settings.themeMode;
    if (mode == ThemeMode.light) return Brightness.light;
    if (mode == ThemeMode.dark) return Brightness.dark;
    return systemDark ? Brightness.dark : Brightness.light;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel());
    unawaited(_controller.flush());
    _controller.dispose();
    _settings.dispose();
    unawaited(_notesRepo.dispose());
    unawaited(_selectionRepo.dispose());
    unawaited(_widgetRepo.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = buildWinNotesTheme(
      brightness: _brightness,
      highContrast: widget.launch.highContrast,
    );

    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const SizedBox.shrink(),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) {
          final surfaceBrightness = _resolveBrightness();
          return Theme(
            // The widget draws its own surface colour, so the ambient brightness
            // has to follow the widget's, not the window's.
            data: ThemeData(brightness: surfaceBrightness),
            child: WidgetSurface(
              controller: _controller,
              brightness: surfaceBrightness,
              acrylicAvailable: widget.launch.acrylicSupported &&
                  _settings.settings.acrylicEnabled,
              onOpenEditor: () => unawaited(widget.shell.showEditor()),
            ),
          );
        },
      ),
    );
  }
}