import 'dart:async';

import '../../../core/utils/atomic_json_file.dart';
import '../../../core/platform/shell_channel.dart';
import '../domain/repositories.dart';
import '../domain/settings.dart';

/// Reads and writes `settings.json`.
///
/// The editor surface owns this file. The widget surface reads it, which is why
/// a change to opacity or theme reaches the widget without either side having
/// to message the other.
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

  /// Applies a change to the registry so the widget comes back after a reboot.
  ///
  /// Turning autostart off removes the entry rather than leaving it disabled
  /// somewhere, so Task Manager and the app can never disagree about the state.
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