import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The editor's layout for this session: the source/preview split, the note
/// list's width, and whether the list is showing. Not `settings.json`; see
/// `docs/widget_pattern.md` §3.24.
class EditorLayout {
  const EditorLayout({
    this.sourceFraction = defaultSourceFraction,
    this.listWidth = defaultListWidth,
    this.listCollapsed = false,
  });

  /// Half and half, which is what the equal `Expanded`s gave before.
  static const double defaultSourceFraction = 0.5;

  /// The width `PROJECT.md` §77 describes the row layout as designed for.
  static const double defaultListWidth = 300;

  /// Neither pane may be dragged out of recognition, and both ends are far
  /// enough from the edge that a stray drag cannot strand one of them.
  static const double minSourceFraction = 0.2;
  static const double maxSourceFraction = 0.8;
  static const double minListWidth = 200;

  /// The editor's floor is 520 wide (`PROJECT.md` §87), so the list can never
  /// take more than that minus something for the editor to live in.
  static const double maxListWidth = 420;

  /// Share of the body given to the source, 0.2 to 0.8.
  final double sourceFraction;

  /// Width of the note list in logical pixels.
  final double listWidth;

  /// Whether the list is collapsed to its edge handle.
  final bool listCollapsed;

  EditorLayout copyWith({
    double? sourceFraction,
    double? listWidth,
    bool? listCollapsed,
  }) {
    return EditorLayout(
      sourceFraction: sourceFraction ?? this.sourceFraction,
      listWidth: listWidth ?? this.listWidth,
      listCollapsed: listCollapsed ?? this.listCollapsed,
    );
  }

  /// The source share, kept inside its bounds. Clamped here rather than at
  /// each call site: a drag reports every position it passes through.
  double clampSource(double value) =>
      value.clamp(minSourceFraction, maxSourceFraction).toDouble();

  /// The list width, kept inside its bounds.
  double clampListWidth(double value) =>
      value.clamp(minListWidth, maxListWidth).toDouble();
}

/// Narrows to the three fields, so dragging a divider cannot rebuild the panes
/// it is dragging between.
class EditorLayoutNotifier extends Notifier<EditorLayout> {
  @override
  EditorLayout build() => const EditorLayout();

  void setSourceFraction(double value) {
    final double next = state.clampSource(value);
    if (next == state.sourceFraction) return;
    state = state.copyWith(sourceFraction: next);
  }

  void setListWidth(double value) {
    final double next = state.clampListWidth(value);
    if (next == state.listWidth) return;
    state = state.copyWith(listWidth: next);
  }

  void toggleList() => setListCollapsed(collapsed: !state.listCollapsed);

  void setListCollapsed({required bool collapsed}) {
    if (collapsed == state.listCollapsed) return;
    state = state.copyWith(listCollapsed: collapsed);
  }

  /// Back to half and half, for the reset the divider's context menu offers.
  void resetSplit() => state = state.copyWith(
        sourceFraction: EditorLayout.defaultSourceFraction,
        listWidth: EditorLayout.defaultListWidth,
      );
}

final NotifierProvider<EditorLayoutNotifier, EditorLayout> editorLayoutProvider =
    NotifierProvider<EditorLayoutNotifier, EditorLayout>(EditorLayoutNotifier.new);
