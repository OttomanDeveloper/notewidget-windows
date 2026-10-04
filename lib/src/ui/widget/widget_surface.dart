import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/settings_repository.dart';
import '../../platform/shell_channel.dart';
import '../../state/widget_controller.dart';
import '../theme.dart';
import 'widget_note_card.dart';

/// The widget surface: a frameless, always-on-top column of notes.
///
/// The window supplies the acrylic, the rounded corners and the shadow, all of
/// which Windows composites natively. What is painted here is only the content,
/// on a translucent surface, so the system backdrop shows through wherever
/// nothing is drawn.
class WidgetSurface extends StatefulWidget {
  const WidgetSurface({
    super.key,
    required this.controller,
    required this.brightness,
    required this.acrylicAvailable,
    required this.onOpenEditor,
  });

  final WidgetController controller;
  final Brightness brightness;
  final bool acrylicAvailable;
  final VoidCallback onOpenEditor;

  @override
  State<WidgetSurface> createState() => _WidgetSurfaceState();
}

class _WidgetSurfaceState extends State<WidgetSurface> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _thumbOpacity = ValueNotifier<double>(0);

  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final offset = widget.controller.state.scrollOffset;
      if (offset > 0 && _scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      }
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    widget.controller.rememberScroll(_scroll.offset);
    // The rail fades in while scrolling and back out once it stops, so it does
    // not permanently eat into a card that is only a few lines tall.
    _thumbOpacity.value = 1;
    // Held as a cancellable Timer rather than a bare Future.delayed: a pending
    // delay survives dispose, and a widget test fails outright on any timer
    // still outstanding when it finishes.
    _railFadeTimer?.cancel();
    _railFadeTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !_scrolling) _thumbOpacity.value = 0;
    });
  }

  Timer? _railFadeTimer;

  bool _scrolling = false;

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _scrolling = true;
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
    }
    return false;
  }

  /// Double click opens the editor.
  ///
  /// Implemented with [Listener] rather than a GestureDetector overlay on top
  /// of the list: a Listener never enters the gesture arena, so cards stay
  /// tappable and the list stays scrollable. A translucent GestureDetector
  /// sitting above them would compete for every pointer event.
  /// Recognising a widget drag and handing it to the runner.
  ///
  /// The gesture is *detected* here and *performed* in the runner. Flutter
  /// reports pointer positions relative to the view, so a window that follows
  /// the cursor shrinks its own delta: computing the drag in Dart lands the
  /// widget at a little over 40% of the distance asked for, however carefully
  /// it is done, and no amount of care in Dart fixes it. The screen-space
  /// cursor exists only in the runner, so the loop that moves the window lives
  /// there.
  ///
  /// Deciding *what* the gesture is stays here, because it cannot move out: the
  /// same pixels also have to select a card and scroll the list, and the
  /// position lock is a Dart-side setting.
  ///
  /// The grab band is in logical pixels, so it has to follow DPI. It also has
  /// to clear the window's own rounded corner, because the native region clips
  /// those pixels away and a grab aimed at the literal corner arrives at
  /// nothing at all.
  void _syncGrabBand(BuildContext? context) {
    final scale =
        (context == null ? null : MediaQuery.maybeDevicePixelRatioOf(context)) ?? 1.0;
    _grabBand = (14 / scale).clamp(8.0, 24.0).round();
  }

  int _grabBand = 14;
  _Gesture? _gesture;

  void _onPointerDown(PointerDownEvent event) {
    _syncGrabBand(_lastContext);
    final size = _surfaceSize;
    final edge = size == null
        ? _Edge.none
        : _edgeUnder(event.localPosition, size, _grabBand);

    _gesture = _Gesture(
      kind: edge == _Edge.none ? _GestureKind.moveCandidate : _GestureKind.resize,
      edge: edge,
      anchor: event.position,
      bounds: _currentBounds(),
    );

    final now = DateTime.now();
    final quick = now.difference(_lastTap) < const Duration(milliseconds: 350);
    final near = (event.position - _lastTapPosition).distance < 24;
    if (quick && near) {
      widget.onOpenEditor();
      _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
      return;
    }
    _lastTap = now;
    _lastTapPosition = event.position;
  }

  /// Whether the list should take this gesture rather than the window.
  ///
  /// Decided from the scroll extent, not from whether a scroll has started yet.
  /// Ordering against the notification is a race: the first move past the
  /// threshold often arrives before Flutter has delivered ScrollStart, and a list
  /// that has nothing left to scroll never delivers one at all - which is
  /// exactly the case where moving the window is the right answer.
  ///
  /// The rule is the one people already expect from a sidebar or a list: scroll
  /// while there is more to read, and once the list is at its end, keep going and
  /// the widget comes with you.
  bool _listCanScroll(double dy) {
    if (!_scroll.hasClients) return false;
    final position = _scroll.position;
    // Half a pixel of slack, so a list already at its end does not go on
    // claiming the gesture over a rounding error.
    //
    // Dragging up pushes the offset *up*, towards the end of the list, and
    // dragging down brings it back towards the start. Getting that backwards
    // hands every upward drag to the window, which is the direction people most
    // often use to scroll.
    const slack = 0.5;
    if (dy < 0) {
      return position.pixels < position.maxScrollExtent - slack;
    }
    if (dy > 0) {
      return position.pixels > position.minScrollExtent + slack;
    }
    return false;
  }

  /// Hands a recognised drag to the runner, once and only once.
  ///
  /// Past this point the pointer belongs to the native loop. Flutter stops
  /// getting useful coordinates the moment the window starts following the
  /// cursor, so there is nothing further to do here but stay out of the way.
  void _onPointerMove(PointerMoveEvent event) {
    final gesture = _gesture;
    if (gesture == null || gesture.kind == _GestureKind.handedOff) return;
    if ((event.position - gesture.anchor).distance < _dragThreshold) return;

    if (gesture.kind == _GestureKind.moveCandidate) {
      if (_listCanScroll(event.position.dy - gesture.anchor.dy)) {
        _gesture = null;
        return;
      }
      if (widget.controller.positionLocked) {
        _gesture = null;
        _explainLockedDrag();
        return;
      }
      unawaited(widget.controller.beginMove(gesture.anchor));
      _gesture = _gesture?.handedOff();
      return;
    }

    // Resizing is never locked: the lock is about position, and a corner drag
    // is a deliberate act rather than an accidental one.
    final resizeEdge = _toResizeEdge(gesture.edge);
    unawaited(widget.controller.beginResize(resizeEdge, gesture.anchor));
    _gesture = _gesture?.handedOff();
  }

  void _onPointerUp(PointerUpEvent event) {
    _gesture = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _gesture = null;
  }

  /// Says why a drag did nothing instead of swallowing it.
  ///
  /// Only ever shown after someone has actually tried to drag a locked widget,
  /// which is the only moment the answer is wanted. Naming the place to change
  /// it matters as much as saying it is locked: "locked" alone leaves the next
  /// question unanswered.
  void _explainLockedDrag() {
    if (_hintTimer != null) return;
    setState(() => _lockedHint = true);
    // A cancellable timer, not Future.delayed: a pending delay outlives dispose
    // and fails a widget test outright.
    _hintTimer = Timer(const Duration(milliseconds: 2600), () {
      _hintTimer = null;
      if (mounted) setState(() => _lockedHint = false);
    });
  }

  Size? _surfaceSize;
  BuildContext? _lastContext;

  NativeBounds? _currentBounds() {
    final state = widget.controller.state;
    if (!state.hasGeometry) return null;
    return NativeBounds(
      left: state.left ?? 0,
      top: state.top ?? 0,
      width: state.width ?? 0,
      height: state.height ?? 0,
    );
  }

  static _Edge _edgeUnder(Offset p, Size size, int band) {
    final left = p.dx < band;
    final right = p.dx > size.width - band;
    final top = p.dy < band;
    final bottom = p.dy > size.height - band;
    if (top && left) return _Edge.topLeft;
    if (top && right) return _Edge.topRight;
    if (bottom && left) return _Edge.bottomLeft;
    if (bottom && right) return _Edge.bottomRight;
    if (left) return _Edge.left;
    if (right) return _Edge.right;
    if (top) return _Edge.top;
    if (bottom) return _Edge.bottom;
    return _Edge.none;
  }

  bool _lockedHint = false;
  Timer? _hintTimer;

  @override
  void dispose() {
    _railFadeTimer?.cancel();
    _hintTimer?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _thumbOpacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.brightness == Brightness.dark;
    final accent = dark ? WinNotesColors.coralSoft : WinNotesColors.coral;
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final notes = controller.displayNotes;

        return ClipRRect(
          // Matches the native rounded region so the painted edge and the
          // composited edge are the same curve rather than two approximations.
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: widgetSurfaceColor(
              brightness: widget.brightness,
              acrylicAvailable: widget.acrylicAvailable,
              opacityPercent: 92,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: _onPointerCancel,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Remembered so a pointer-down can tell which edge it
                          // landed on without a second layout pass, and so the
                          // grab band can be scaled to the display.
                          _surfaceSize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          _lastContext = context;

                          // The one real design decision in this project, decided from the
                          // widget's own size rather than from scroll metrics:
                          // those are not readable during sliver layout, which
                          // is when this list builds its children.
                          final roomy = constraints.maxHeight >= 240 &&
                              constraints.maxWidth >= 200;

                          if (notes.isEmpty) {
                            return _NoNotesChrome(dark: dark);
                          }
                          return NotificationListener<ScrollNotification>(
                            onNotification: _onScrollNotification,
                            child: ListView.separated(
                              controller: _scroll,
                              // Nothing to disable here. Once the drag is handed
                              // to the runner, the runner takes the mouse capture
                              // and the list never sees another pointer event, so
                              // the two cannot fight over it.
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                              itemCount: notes.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 2),
                              itemBuilder: (context, index) {
                                final note = notes[index];
                                return WidgetNoteCard(
                                  note: note,
                                  focused: index == 0,
                                  dark: dark,
                                  accent: accent,
                                  roomy: roomy,
                                  onTap: () => controller.focusNote(note.id),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: _FloatingScrollRail(
                      controller: _scroll,
                      opacity: _thumbOpacity,
                    ),
                  ),
                ),
                // Sits above the cards and ignores pointers, so it can never
                // swallow the tap that dismissed it.
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: IgnorePointer(
                    child: _LockedHint(visible: _lockedHint, dark: dark),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Which edge or corner a resize gesture grabbed.
enum _Edge { none, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }

ResizeEdge _toResizeEdge(_Edge edge) => switch (edge) {
      _Edge.left => ResizeEdge.left,
      _Edge.right => ResizeEdge.right,
      _Edge.top => ResizeEdge.top,
      _Edge.bottom => ResizeEdge.bottom,
      _Edge.topLeft => ResizeEdge.topLeft,
      _Edge.topRight => ResizeEdge.topRight,
      _Edge.bottomLeft => ResizeEdge.bottomLeft,
      _Edge.bottomRight => ResizeEdge.bottomRight,
      _Edge.none => ResizeEdge.right,
    };

enum _GestureKind { moveCandidate, resize, handedOff }

class _Gesture {
  _Gesture({
    required this.kind,
    required this.anchor,
    required this.bounds,
    this.edge = _Edge.none,
  });

  final _GestureKind kind;
  final Offset anchor;
  final NativeBounds? bounds;
  final _Edge edge;

  _Gesture handedOff() => _Gesture(
        kind: _GestureKind.handedOff,
        anchor: anchor,
        bounds: bounds,
        edge: edge,
      );
}

/// How far the pointer must travel before a press becomes a drag.
///
/// Small enough that a drag feels immediate, large enough that pressing on a
/// card and moving slightly - or a shaky click - still selects the card.
const double _dragThreshold = 8;

/// Says why a drag did nothing.
///
/// Only ever visible after someone has dragged a locked widget, which is the
/// only moment the answer is wanted. Naming the place to change it matters as
/// much as saying it is locked: "locked" alone leaves the next question
/// unanswered.
class _LockedHint extends StatelessWidget {
  const _LockedHint({required this.visible, required this.dark});

  final bool visible;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    // Not an AnimatedOpacity at zero. An invisible widget is still in the tree,
    // which means a screen reader would read "Locked in place" out loud on a
    // widget that is perfectly draggable, and it keeps a string of hidden text
    // in every widget surface for no reason.
    if (!visible) return const SizedBox.shrink();

    final foreground = dark ? const Color(0xFFEDEBF5) : const Color(0xFF23202E);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          // Opaque, not translucent: this is the one thing on the widget that
          // has to stay readable over an arbitrary wallpaper.
          color: dark ? const Color(0xFF2E2748) : const Color(0xFFFBFAF6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.10),
          ),
        ),
        child: Text(
          'Locked in place · turn it off in Settings',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foreground.withValues(alpha: 0.92),
            fontSize: 11.5,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

/// A minimal scroll rail that appears while scrolling and fades out after.
///
/// Hand-rolled rather than [Scrollbar] because the built-in one either paints a
/// permanent track that narrows the cards or needs hover to show at all, and
/// this widget is too small for either.
class _FloatingScrollRail extends StatelessWidget {
  const _FloatingScrollRail({
    required this.controller,
    required this.opacity,
  });

  final ScrollController controller;
  final ValueListenable<double> opacity;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<double>(
      valueListenable: opacity,
      builder: (context, value, _) {
        if (value <= 0.01) return const SizedBox.shrink();
        return AnimatedOpacity(
          opacity: value,
          duration: const Duration(milliseconds: 220),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 3),
              child: SizedBox(
                width: 4,
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    if (!controller.hasClients) return const SizedBox.shrink();
                    final position = controller.position;
                    final total = position.maxScrollExtent + position.viewportDimension;
                    if (total <= 0) return const SizedBox.shrink();
                    final fraction = position.viewportDimension / total;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: FractionallySizedBox(
                        heightFactor: fraction.clamp(0.08, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.45)
                                : Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoNotesChrome extends StatelessWidget {
  const _NoNotesChrome({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final muted = widgetMutedColor(dark ? Brightness.dark : Brightness.light);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No notes',
          style: TextStyle(color: muted, fontSize: 13),
        ),
      ),
    );
  }
}