import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/settings/domain/settings.dart';
import 'package:win_notes/features/widget/domain/widget_state.dart';

import '../../../../../core/platform/shell_channel.dart';
import '../../../../../core/utils/app_providers.dart';
import '../../../../settings/presentation/providers/settings_controller.dart';
import '../../../../settings/presentation/providers/settings_providers.dart';
import '../../providers/widget_controller.dart';
import '../../providers/widget_providers.dart';
import '../../widgets/floating_scroll_rail/floating_scroll_rail.dart';
import '../../widgets/locked_hint/locked_hint.dart';
import '../../widgets/no_notes_chrome/no_notes_chrome.dart';
import '../../widgets/widget_composer/widget_composer.dart';
import '../../widgets/widget_gesture/widget_gesture.dart';
import '../../../../../core/theme/palette.dart';
import '../../../../../core/theme/skin.dart';
import '../../../../../core/theme/theme.dart';
import '../../widgets/widget_note_card/widget_note_card.dart';

/// The widget surface: a frameless, always-on-top column of notes.
/// Paints only content on a translucent surface; acrylic, corners and shadow are composited natively.
class WidgetSurface extends ConsumerStatefulWidget {
  const WidgetSurface({super.key});

  /// Everything this widget needs arrives through `ref`, never as parameters [`AGENTS.md` §0.8].
  /// The palette comes from a provider because the surface replaces the app theme with a bare `ThemeData`.

  @override
  ConsumerState<WidgetSurface> createState() => _WidgetSurfaceState();
}

class _WidgetSurfaceState extends ConsumerState<WidgetSurface> {
  final ScrollController _scroll = ScrollController();
  /// The widget surface's own controller, reached through `ref`.
  /// `read` not `watch`: the notifier is for doing, and watching would rebuild on every edit.
  WidgetNotifier get controller => _notifier;

  /// Captured in [initState]: Riverpod forbids any `ref` use inside `dispose`.
  /// Needed to return the keyboard when torn down with the composer open; see `_EditorScopeState`.
  late final WidgetNotifier _notifier;

  /// The current window state, for handlers outside `build()` (`read` not `watch`).
  WidgetSurfaceState get _state => ref.read(widgetProvider).requireValue;

  /// The palette from a provider for handlers; `build()` watches `accentPaletteProvider` [`provider_pattern.md` §2].
  WinNotesPalette get palette => ref.read(accentPaletteProvider);

  /// For handlers; `build()` watches `widgetSurfaceThemeProvider` explicitly.
  Brightness get brightness => ref.read(widgetSurfaceThemeProvider).brightness;

  /// For handlers; `build()` watches `settingsProvider` and `launchInfoProvider`.
  bool get acrylicAvailable {
    final WinNotesSettings? settings = ref.read(settingsProvider).value?.settings;
    return (settings?.acrylicEnabled ?? false) &&
        ref.read(launchInfoProvider).acrylicSupported;
  }

  void onOpenEditor() =>
      unawaited(ref.read(shellProvider).showEditor());
  final ValueNotifier<double> _thumbOpacity = ValueNotifier<double>(0);

  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(widgetProvider.notifier);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final double offset = ref.read(widgetProvider).value?.window.scrollOffset ?? 0.0;
      if (offset > 0 && _scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      }
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    controller.rememberScroll(_scroll.offset);
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

    /// Double click opens the editor via [Listener], outside the gesture arena.
    /// Drags are recognised here (selection, scroll, lock) and performed in the
    /// runner; the grab band follows DPI in logical pixels.
  void _syncGrabBand(BuildContext? context) {
    final double scale =
        (context == null ? null : MediaQuery.maybeDevicePixelRatioOf(context)) ?? 1.0;
    _grabBand = (14 / scale).clamp(8.0, 24.0).round();
  }

  int _grabBand = 14;
  WidgetGesture? _gesture;

  void _onPointerDown(PointerDownEvent event) {
    _syncGrabBand(_lastContext);
    // While composing, the pointer belongs to the text field; otherwise a click near
    // its edge would resize instead of placing the caret.
    if (_composing.value) return;
    final Size? size = _surfaceSize;
    final GestureEdge edge = size == null
        ? GestureEdge.none
        : _edgeUnder(event.localPosition, size, _grabBand);

    _gesture = WidgetGesture(
      kind: edge == GestureEdge.none ? GestureKind.moveCandidate : GestureKind.resize,
      edge: edge,
      anchor: event.position,
      bounds: _currentBounds(),
    );

    final DateTime now = DateTime.now();
    final bool quick = now.difference(_lastTap) < const Duration(milliseconds: 350);
    final bool near = (event.position - _lastTapPosition).distance < 24;
    if (quick && near) {
      onOpenEditor();
      _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
      return;
    }
    _lastTap = now;
    _lastTapPosition = event.position;
  }

  /// Whether the list takes this gesture, decided from scroll extent not `ScrollStart`.
  /// Scroll while there is more to read; at the end the widget moves with the drag.
  bool _listCanScroll(double dy) {
    if (!_scroll.hasClients) return false;
    final ScrollPosition position = _scroll.position;
    // Half-pixel slack avoids claiming the gesture over rounding; up moves toward the end.
    // Down moves toward the start; reversed hands scrolls to the window.
    const double slack = 0.5;
    if (dy < 0) {
      return position.pixels < position.maxScrollExtent - slack;
    }
    if (dy > 0) {
      return position.pixels > position.minScrollExtent + slack;
    }
    return false;
  }

  /// Hands a recognised drag to the runner once; past this the native loop owns the pointer.
  void _onPointerMove(PointerMoveEvent event) {
    final WidgetGesture? gesture = _gesture;
    if (gesture == null || gesture.kind == GestureKind.handedOff) return;
    if ((event.position - gesture.anchor).distance < widgetDragThreshold) return;

    if (gesture.kind == GestureKind.moveCandidate) {
      if (_listCanScroll(event.position.dy - gesture.anchor.dy)) {
        _gesture = null;
        return;
      }
      if (_state.positionLocked) {
        _gesture = null;
        _explainLockedDrag();
        return;
      }
      unawaited(controller.beginMove(gesture.anchor));
      _gesture = _gesture?.handedOff();
      return;
    }

    // Resizing is never locked: the lock is about position, and a corner drag
    // is a deliberate act rather than an accidental one.
    final ResizeEdge resizeEdge = toResizeEdge(gesture.edge);
    unawaited(controller.beginResize(resizeEdge, gesture.anchor));
    _gesture = _gesture?.handedOff();
  }

  void _onPointerUp(PointerUpEvent event) {
    _gesture = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _gesture = null;
  }

  /// Says why a locked drag did nothing, shown only after an actual attempt.
  /// Names where to change it, not just that it is locked.
  void _explainLockedDrag() {
    if (_hintTimer != null) return;
    _lockedHint.value = true;
    // A cancellable timer, not Future.delayed: a pending delay outlives dispose
    // and fails a widget test outright.
    _hintTimer = Timer(const Duration(milliseconds: 2600), () {
      _hintTimer = null;
      if (mounted) _lockedHint.value = false;
    });
  }

  Size? _surfaceSize;
  BuildContext? _lastContext;

  NativeBounds? _currentBounds() {
    final WidgetWindowState state = _state.window;
    if (!state.hasGeometry) return null;
    return NativeBounds(
      left: state.left ?? 0,
      top: state.top ?? 0,
      width: state.width ?? 0,
      height: state.height ?? 0,
    );
  }

  static GestureEdge _edgeUnder(Offset p, Size size, int band) {
    final bool left = p.dx < band;
    final bool right = p.dx > size.width - band;
    final bool top = p.dy < band;
    final bool bottom = p.dy > size.height - band;
    if (top && left) return GestureEdge.topLeft;
    if (top && right) return GestureEdge.topRight;
    if (bottom && left) return GestureEdge.bottomLeft;
    if (bottom && right) return GestureEdge.bottomRight;
    if (left) return GestureEdge.left;
    if (right) return GestureEdge.right;
    if (top) return GestureEdge.top;
    if (bottom) return GestureEdge.bottom;
    return GestureEdge.none;
  }

  final ValueNotifier<bool> _lockedHint = ValueNotifier<bool>(false);
  Timer? _hintTimer;

  /// The add-a-note field; open means the widget holds the keyboard (`WS_EX_NOACTIVATE` dropped).
  /// Every exit path must close it or the caret is kept with no field visible.
  final TextEditingController _compose = TextEditingController();
  final FocusNode _composeFocus = FocusNode();
  final ValueNotifier<bool> _composing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _hovering = ValueNotifier<bool>(false);

  void _setHovering(bool value) {
    if (_hovering.value == value) return;
    _hovering.value = value;
  }

  void _openComposer() {
    if (_composing.value) return;
    _composing.value = true;
    unawaited(controller.setComposeMode(active: true));
    // After the frame, so the window has actually taken the keyboard before
    // Flutter is asked to put the caret in the field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _composing.value) _composeFocus.requestFocus();
    });
  }

  void _closeComposer() {
    if (!_composing.value) return;
    _composing.value = false;
    _compose.clear();
    _composeFocus.unfocus();
    unawaited(controller.setComposeMode(active: false));
  }

  Future<void> _submitComposer() async {
    final String raw = _compose.text.trim();
    if (raw.isEmpty) {
      _closeComposer();
      return;
    }
    // First line is the title, the rest is the body. It is the same shape the
    // widget already displays - a line, then a preview - so a note jotted here
    // looks like a note written in the editor, with no second box to fill in.
    final int split = raw.indexOf('\n');
    final String title = split < 0 ? raw : raw.substring(0, split).trim();
    final String body = split < 0 ? '' : raw.substring(split + 1).trim();
    // Close first, so the keyboard goes back before the write is even attempted.
    // Waiting on the round trip would leave the caret parked in the widget while
    // nothing is happening, which is the thing this whole design is avoiding.
    _closeComposer();
    await controller.addNote(title: title, body: body);
  }

  Future<void> setComposeMode({required bool active}) =>
      controller.setComposeMode(active: active);

  @override
  void dispose() {
    _railFadeTimer?.cancel();
    _hintTimer?.cancel();
    _compose.dispose();
    _composeFocus.dispose();
    // Closing returns the keyboard; read the notifier once here while the element is alive.
    // Riverpod asserts on any `ref` in `dispose` via [controller]; see `_EditorScopeState`.
    // A torn-down composer would otherwise leave the native window holding the keyboard.
    if (_composing.value) unawaited(_notifier.setComposeMode(active: false));
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _thumbOpacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watched where drawn (`provider_pattern.md` §2, `flutter_architecture_pattern.md`
    // §5.2): the getters above are `read` for handlers, which cannot watch.
    final Brightness brightness = ref.watch(widgetSurfaceThemeProvider).brightness;
    final WinNotesPalette palette = ref.watch(accentPaletteProvider);
    final WinNotesSkin? skin = ref.watch(skinProvider);
    final bool? acrylicEnabled = ref.watch(
      settingsProvider.select((AsyncValue<SettingsState> v) => v.value?.settings.acrylicEnabled),
    );
    final bool acrylicSupported = ref.watch(
      launchInfoProvider.select((LaunchInfo v) => v.acrylicSupported),
    );
    final bool acrylicAvailable = (acrylicEnabled ?? false) && acrylicSupported;
    final bool dark = brightness == Brightness.dark;
    // Resolved through the palette rather than read from the theme, so the
    // focused card's bar, the tick and the composer's border cannot disagree
    // with the editor about what the accent is.
    final Color accent = palette.accentFor(brightness);
    final SkinLook look = lookOf(skin);

    // The display list, derived in its provider: geometry, scroll and
    // visibility changes leave the cards alone, and each card watches only
    // its own note, so typing in one rebuilds one.
    final List<Note> notes = ref.watch(widgetDisplayNotesProvider);

    // Three former `setState` fields merged into one listener so the surface repaints.
    // Without it writes never rebuild; `no_set_state_test` cannot catch that.
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable?>[_hovering, _composing, _lockedHint]),
      builder: (BuildContext context, _) {
        return ClipRRect(
          // Matches the native rounded region so the painted edge and the
          // composited edge are the same curve rather than two approximations.
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: widgetSurfaceColor(
              brightness: brightness,
              acrylicAvailable: acrylicAvailable,
              opacityPercent: 92,
              palette: palette,
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: _onPointerCancel,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => _setHovering(true),
                      onExit: (_) => _setHovering(false),
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          // Remembered so a pointer-down can tell which edge it
                          // landed on without a second layout pass, and so the
                          // grab band can be scaled to the display.
                          _surfaceSize = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          _lastContext = context;

                          // Decided from the widget's own size: scroll metrics are unreadable during sliver layout.
                          final bool roomy = constraints.maxHeight >= 240 &&
                              constraints.maxWidth >= 200;

                          if (notes.isEmpty) {
                            return NoNotesChrome(dark: dark);
                          }
                          return NotificationListener<ScrollNotification>(
                            onNotification: _onScrollNotification,
                            child: ListView.separated(
                              controller: _scroll,
                              // Once handed to the runner it takes mouse capture, so the list sees no further events.
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                              itemCount: notes.length,
                              separatorBuilder: (BuildContext context, int index) => switch (look.separator) {
                                SkinSeparator.hairline => Divider(
                                    height: 1,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                SkinSeparator.gap => const SizedBox(height: 2),
                                SkinSeparator.none => const SizedBox.shrink(),
                              },
                              itemBuilder: (BuildContext context, int index) {
                                final Note note = notes[index];
                                return WidgetNoteCard(
                                  key: ValueKey<String>(note.id),
                                  noteId: note.id,
                                  focused: index == 0,
                                  dark: dark,
                                  accent: accent,
                                  roomy: roomy,
                                  skin: skin,
                                  onTap: () => controller.focusNote(note.id),
                                  onToggleCompleted: () =>
                                      unawaited(controller.toggleCompleted(note.id)),
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
                    child: FloatingScrollRail(
                      scroll: _scroll,
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
                    child: LockedHint(visible: _lockedHint.value, dark: dark),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: WidgetComposer(
                    open: _composing.value,
                    revealed: _hovering.value || _composing.value,
                    field: _compose,
                    focusNode: _composeFocus,
                    dark: dark,
                    accent: accent,
                    onOpen: _openComposer,
                    onClose: _closeComposer,
                    onSubmit: _submitComposer,
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


const double widgetDragThreshold = 8;
