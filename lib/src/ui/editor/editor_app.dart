import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_paths.dart';
import '../../core/atomic_json_file.dart';
import '../../data/note.dart';
import '../../data/notes_repository.dart';
import '../../data/settings_repository.dart';
import '../../platform/shell_channel.dart';
import '../../state/notes_controller.dart';
import '../../state/settings_controller.dart';
import '../settings/settings_dialog.dart';
import '../theme.dart';
import 'editor_view.dart';

/// Root widget for the editor surface.
///
/// Owns notes.json and settings.json. The widget surface reads both and writes
/// neither, which is the whole reason there is no cross-isolate merge logic
/// anywhere in this project.
class EditorApp extends StatefulWidget {
  const EditorApp({
    super.key,
    required this.shell,
    required this.launch,
    required this.paths,
  });

  final ShellChannel shell;
  final LaunchInfo launch;
  final AppPaths paths;

  @override
  State<EditorApp> createState() => _EditorAppState();
}

class _EditorAppState extends State<EditorApp> with WidgetsBindingObserver {
  late final NotesRepository _notesRepo;
  late final SettingsRepository _settingsRepo;
  late final SelectionRepository _selectionRepo;
  late final NotesController _notes;
  late final SettingsController _settings;
  StreamSubscription<ShellEvent>? _events;

  bool _settingsOpen = false;
  Brightness _systemBrightness = Brightness.light;

  BackupService get _backup => const BackupService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    _notesRepo = NotesRepository(AtomicJsonFile(widget.paths.notesFile));
    _settingsRepo = SettingsRepository(
      AtomicJsonFile(widget.paths.settingsFile),
      widget.shell,
    );
    _selectionRepo = SelectionRepository(
      AtomicJsonFile(widget.paths.selectionFile),
    );

    _notes = NotesController(repository: _notesRepo, watchExternal: false);
    _settings = SettingsController(
      repository: _settingsRepo,
      shell: widget.shell,
      watchExternal: true,
    );

    await _settings.load(
      animationsEnabled: widget.launch.animationsEnabled,
      acrylicSupported: widget.launch.acrylicSupported,
    );

    await _notes.load();

    // Corresponds to the first launch opening with a note already focused, so
    // typing is the very first thing that happens.
    if (_notes.corrupt == null) {
      _notes.ensureAtLeastOneNote();
      _notes.select(_selectionRepo.readSelection());
    }

    // Corrects the registry entry and the hotkey on every launch, so neither
    // has to be toggled to be right.
    await _settings.syncPlatform();

    _events = widget.shell.events.listen(_onEvent);
  }

  void _onEvent(ShellEvent event) {
    switch (event.kind) {
      case ShellEventKind.hotkey:
        _focusEditor();
      case ShellEventKind.openSettings:
        _openSettings();
      case ShellEventKind.geometry:
      case ShellEventKind.visibility:
      case ShellEventKind.unknown:
        break;
    }
  }

  void _focusEditor() {
    if (!mounted) return;
    // Closing the editor hands focus back to the widget, so the hotkey has to
    // bring the editor back properly rather than just showing it.
    unawaited(widget.shell.focusWindow('editor'));
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _openSettings() {
    if (!mounted || _settingsOpen) return;
    setState(() => _settingsOpen = true);
    showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        controller: _settings,
        shell: widget.shell,
        defaultDataDirectory: widget.paths.defaultStorageDirectory,
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _settingsOpen = false);
    });
  }

  Future<void> _export() async {
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
    final path = await widget.shell.saveFile(
      suggestedName: 'winnotes-backup-$stamp.txt',
    );
    if (path == null) return;
    final text = _backup.export(_notes.notes);
    await File(path).writeAsString(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${_notes.notes.length} notes.')),
    );
  }

  Future<List<Note>?> _import() async {
    final path = await widget.shell.pickFile();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;

    final incoming = _backup.import(await file.readAsString());
    if (incoming.isEmpty) return null;

    if (_notes.corrupt != null) {
      // A hand-chosen backup is the one thing allowed to replace a file the app
      // refused to touch on its own.
      _notesRepo.unblock();
      _notes.replaceAll(incoming);
    } else {
      final merge = await _confirmMerge(incoming.length);
      if (merge) {
        _notes.merge(incoming);
      }
    }
    return incoming;
  }

  Future<bool> _confirmMerge(int count) async {
    if (!mounted) return false;
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

  @override
  void didChangePlatformBrightness() {
    setState(() {
      _systemBrightness =
          MediaQueryData.fromView(View.of(context)).platformBrightness;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel());
    // Anything still queued has to reach disk before the isolate goes away,
    // because there is no quit hook to do it later.
    unawaited(_notes.flush());
    unawaited(_settings.flush());
    unawaited(_selectionRepo.flush());
    _notes.dispose();
    _settings.dispose();
    unawaited(_notesRepo.dispose());
    unawaited(_settingsRepo.dispose());
    unawaited(_selectionRepo.dispose());
    super.dispose();
  }

  Brightness _resolveBrightness() {
    final mode = _settings.settings.themeMode;
    if (mode == ThemeMode.light) return Brightness.light;
    if (mode == ThemeMode.dark) return Brightness.dark;
    return widget.launch.isSystemDark ? Brightness.dark : _systemBrightness;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        final brightness = _resolveBrightness();
        return MaterialApp(
          title: 'WinNotes',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.light,
          theme: buildWinNotesTheme(
            brightness: brightness,
            highContrast: widget.launch.highContrast,
          ),
          home: EditorView(
            controller: _notes,
            shell: widget.shell,
            onOpenSettings: _openSettings,
            exportNotes: _export,
            importNotes: _import,
          ),
        );
      },
    );
  }
}