import './settings.dart';

/// Reads and writes `settings.json`. The interface the settings provider
/// depends on; the file in `data/` is the only implementation.
abstract interface class ISettingsRepository {
  Future<WinNotesSettings> load();
  void save(WinNotesSettings settings);
  Future<void> saveNow(WinNotesSettings settings);
  Future<bool> applyAutoStart({required bool enabled});
  Future<bool> currentAutoStartState();
  void watch(void Function() onChanged);
  String get path;
  Future<void> flush();
  Future<void> dispose();
}
