import '../../notes/domain/note.dart';

/// The note rendered large: the explicit selection, else the most recent open
/// note, else the most recent note. One rule shared by the state getter below
/// and the display provider, so the two cannot disagree.
Note? focusedNoteIn(List<Note> notes, String? selectedId) {
  if (selectedId != null) {
    for (final note in notes) {
      if (note.id == selectedId) return note;
    }
  }
  for (final note in notes) {
    if (!note.isCompleted) return note;
  }
  return notes.isEmpty ? null : notes.first;
}

/// Notes in display order: most recent first, focused pulled to the top.
List<Note> displayNotesIn(List<Note> notes, String? selectedId) {
  final focused = focusedNoteIn(notes, selectedId);
  if (focused == null) return const [];
  final rest = notes.where((n) => n.id != focused.id).toList();
  return [focused, ...rest];
}

/// The widget's position, size, monitor and scroll offset.
///
/// [dockEdge] exists so a widget parked against a screen edge can say so
/// explicitly. Windows applies the snap as part of the drag loop, so this is
/// a record of what happened rather than a second, competing source of truth.
/// Named `WidgetWindowState` rather than `WidgetWindowState` because Flutter's own
/// `WidgetWindowState` is exported by material.dart, and a project that imports both
/// cannot use either name unqualified.
class WidgetWindowState {  const WidgetWindowState({
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
