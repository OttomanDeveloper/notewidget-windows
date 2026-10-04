import 'dart:async';

import '../core/atomic_json_file.dart';
import '../platform/shell_channel.dart';
import 'settings.dart';

/// Reads and writes `settings.json`.
///
/// The editor surface owns this file. The widget surface reads it, which is why
/// a change to opacity or theme reaches the widget without either side having
/// to message the other.
class SettingsRepository {
  SettingsRepository(this._file, this._shell);

  final AtomicJsonFile _file;
  final ShellChannel _shell;

  static final WinNotesSettings defaults = WinNotesSettings();

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

  void save(WinNotesSettings settings) => _file.write(settings.toJson());

  Future<void> saveNow(WinNotesSettings settings) => _file.writeNow(settings.toJson());

  /// Applies a change to the registry so the widget comes back after a reboot.
  ///
  /// Turning autostart off removes the entry rather than leaving it disabled
  /// somewhere, so Task Manager and the app can never disagree about the state.
  Future<bool> applyAutoStart(bool enabled) => _shell.setAutoStart(enabled);

  Future<bool> currentAutoStartState() => _shell.queryAutoStart();

  void watch(void Function() onChanged) => _file.watch(onChanged);

  String get path => _file.path;

  Future<void> flush() => _file.flushPending();
  Future<void> dispose() => _file.dispose();
}

/// Which edge or corner a resize gesture is dragging.
enum ResizeEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get movesLeft => this == left || this == topLeft || this == bottomLeft;
  bool get movesRight =>
      this == right || this == topRight || this == bottomRight;
  bool get movesTop => this == top || this == topLeft || this == topRight;
  bool get movesBottom =>
      this == bottom || this == bottomLeft || this == bottomRight;
}

/// Wire values for [ResizeEdge], matching the EdgeCode enum in the runner.
///
/// Explicit rather than `index + 1`, so reordering the Dart enum cannot quietly
/// change which edge the native loop resizes.
class ResizeEdgeCode {
  const ResizeEdgeCode._();

  static const Map<ResizeEdge, int> value = {
    ResizeEdge.left: 1,
    ResizeEdge.right: 2,
    ResizeEdge.top: 3,
    ResizeEdge.bottom: 4,
    ResizeEdge.topLeft: 5,
    ResizeEdge.topRight: 6,
    ResizeEdge.bottomLeft: 7,
    ResizeEdge.bottomRight: 8,
  };
}

/// Where the widget was left, and which monitor it was left on.
///
/// Owned by the widget surface. The editor never writes it, so the two sides
/// cannot disagree about where the widget is.
class WidgetStateRepository {
  WidgetStateRepository(this._file);

  final AtomicJsonFile _file;

  static const WidgetWindowState empty = WidgetWindowState();

  Future<WidgetWindowState> load() async {
    try {
      final json = await _file.read();
      if (json.isEmpty) return WidgetWindowState.empty;
      return WidgetWindowState.fromJson(json);
    } on CorruptDataFile {
      return WidgetWindowState.empty;
    }
  }

  void save(WidgetWindowState state) => _file.write(state.toJson());

  Future<void> flush() => _file.flushPending();
  Future<void> dispose() => _file.dispose();
}

/// The widget's position, size, monitor and scroll offset.
///
/// [dockEdge] exists so a widget parked against a screen edge can say so
/// explicitly. Windows applies the snap as part of the drag loop, so this is
/// a record of what happened rather than a second, competing source of truth.
/// Named `WidgetWindowState` rather than `WidgetWindowState` because Flutter's own
/// `WidgetWindowState` is exported by material.dart, and a project that imports both
/// cannot use either name unqualified.
class WidgetWindowState {
  const WidgetWindowState({
    this.left,
    this.top,
    this.width,
    this.height,
    this.monitorId,
    this.dockEdge,
    this.scrollOffset = 0,
  });

  /// No geometry recorded yet, so the runner picks the default placement.
  static const WidgetWindowState empty = WidgetWindowState();

  final int? left;
  final int? top;
  final int? width;
  final int? height;
  final int? monitorId;
  final String? dockEdge;
  final double scrollOffset;

  bool get hasGeometry => left != null && top != null && width != null && height != null;

  WidgetWindowState copyWith({
    int? left,
    int? top,
    int? width,
    int? height,
    int? monitorId,
    String? dockEdge,
    bool clearDockEdge = false,
    double? scrollOffset,
  }) =>
      WidgetWindowState(
        left: left ?? this.left,
        top: top ?? this.top,
        width: width ?? this.width,
        height: height ?? this.height,
        monitorId: monitorId ?? this.monitorId,
        dockEdge: clearDockEdge ? null : (dockEdge ?? this.dockEdge),
        scrollOffset: scrollOffset ?? this.scrollOffset,
      );

  Map<String, dynamic> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
        'monitorId': monitorId,
        'dockEdge': dockEdge,
        'scrollOffset': scrollOffset,
      };

  static WidgetWindowState fromJson(Map<String, dynamic> json) {
    int? readInt(String key) => (json[key] as num?)?.toInt();
    return WidgetWindowState(
      left: readInt('left'),
      top: readInt('top'),
      width: readInt('width'),
      height: readInt('height'),
      monitorId: readInt('monitorId'),
      dockEdge: json['dockEdge'] as String?,
      scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0,
    );
  }
}