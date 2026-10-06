import 'dart:async';

import '../../../core/utils/atomic_json_file.dart';
import '../../../core/platform/shell_channel.dart';
import '../domain/repositories.dart';
import '../domain/settings.dart';

/// Reads and writes `settings.json`. The editor owns it; the widget reads it,
/// so opacity and theme changes arrive with no messaging between surfaces.
class SettingsRepository implements ISettingsRepository {
  SettingsRepository(this._file, this._shell);

  final AtomicJsonFile _file;
  final ShellChannel _shell;

  static final WinNotesSettings defaults = WinNotesSettings();

  @override
  Future<WinNotesSettings> load() async {
    try {
      final json = await _file.read();
      if (json.isEmpty) return defaults;
      return WinNotesSettings.fromJson(json);
    } on CorruptDataFile {
      // Settings are preferences, not data. Falling back to defaults and
      // letting the next write replace them is the right call here, unlike for
      // notes where it would be data loss.
      return defaults;
    }
  }

  @override
  void save(WinNotesSettings settings) => _file.write(settings.toJson());

  @override
  Future<void> saveNow(WinNotesSettings settings) => _file.writeNow(settings.toJson());

    /// Applies a registry change so the widget comes back after reboot. Off
    /// removes the entry: Task Manager and the app cannot disagree.
  @override
  Future<bool> applyAutoStart({required bool enabled}) =>
      _shell.setAutoStart(enabled: enabled);

  @override
  Future<bool> currentAutoStartState() => _shell.queryAutoStart();

  @override
  void watch(void Function() onChanged) => _file.watch(onChanged);

  @override
  String get path => _file.path;

  @override
  Future<void> flush() => _file.flushPending();
  @override
  Future<void> dispose() => _file.dispose();
}