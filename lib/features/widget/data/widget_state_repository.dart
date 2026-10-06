import 'dart:async';

import '../../../core/utils/atomic_json_file.dart';
import '../domain/repositories.dart';

export '../domain/repositories.dart';
export '../domain/widget_state.dart';

/// Where the widget was left, and on which monitor. Widget-owned: the editor
/// never writes it, so the two sides cannot disagree.
class WidgetStateRepository implements IWidgetStateRepository {
  WidgetStateRepository(this._file);

  final AtomicJsonFile _file;

  static const WidgetWindowState empty = WidgetWindowState();

  @override
  Future<WidgetWindowState> load() async {
    try {
      final json = await _file.read();
      if (json.isEmpty) return WidgetWindowState.empty;
      return WidgetWindowState.fromJson(json);
    } on CorruptDataFile {
      return WidgetWindowState.empty;
    }
  }

  @override
  void save(WidgetWindowState state) => _file.write(state.toJson());

  @override
  Future<void> flush() => _file.flushPending();
  @override
  Future<void> dispose() => _file.dispose();
}
