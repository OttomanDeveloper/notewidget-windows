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
  }

  @override
  void dispose() {
    _railFadeTimer?.cancel();
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
              ],
            ),
          ),
        );
      },
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