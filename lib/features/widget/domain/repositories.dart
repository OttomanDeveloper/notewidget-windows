import './widget_state.dart';

export './widget_state.dart';

/// Where the widget was left, and which monitor it was left on. The interface
/// the widget provider depends on; the file in `data/` is the only implementation.
abstract interface class IWidgetStateRepository {
  Future<WidgetWindowState> load();
  void save(WidgetWindowState state);
  Future<void> flush();
  Future<void> dispose();
}
