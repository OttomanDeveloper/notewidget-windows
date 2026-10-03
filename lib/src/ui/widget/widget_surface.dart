import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  void _onPointerDown(PointerDownEvent event) {
    final now = DateTime.now();
    final quick = now.difference(_lastTap) < const Duration(milliseconds: 350);
    final near = (event.position - _lastTapPosition).distance < 24;
    if (quick && near) {
      widget.onOpenEditor();
      // Reset so a triple click does not immediately reopen it again.
      _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
      return;
    }
    _lastTap = now;
    _lastTapPosition = event.position;
    _dragAnchor = event.position;
  }

  /// Explains a refused drag instead of swallowing it.
  ///
  /// When the widget is locked the native window reports HTCLIENT, so the
  /// pointer arrives here rather than starting a Windows move loop. Without
  /// this, dragging a locked widget does nothing at all and there is no way to
  /// tell that the lock is the reason - the one thing someone in that moment
  /// needs to know. The hint shows itself on the first attempt, so it only ever
  /// appears for someone who has just tried and failed.
  void _onPointerMove(PointerMoveEvent event) {
    if (!widget.controller.positionLocked || _hintTimer != null) return;
    final anchor = _dragAnchor;
    if (anchor == null) return;
    if ((event.position - anchor).distance < 12) return;

    _dragAnchor = null;
    setState(() => _lockedHint = true);
    // A cancellable timer, not Future.delayed: a pending delay outlives dispose
    // and fails a widget test outright.
    _hintTimer = Timer(const Duration(milliseconds: 2600), () {
      _hintTimer = null;
      if (mounted) setState(() => _lockedHint = false);
    });
  }

  Offset? _dragAnchor;
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
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
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