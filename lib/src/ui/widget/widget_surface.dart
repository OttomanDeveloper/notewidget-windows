import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../data/settings_repository.dart';
import '../../platform/shell_channel.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../../state/widget_controller.dart';
import '../theme_scope.dart';
import '../palette.dart';
import '../theme.dart';
import 'widget_note_card.dart';

/// The widget surface: a frameless, always-on-top column of notes.
///
/// The window supplies the acrylic, the rounded corners and the shadow, all of
/// which Windows composites natively. What is painted here is only the content,
/// on a translucent surface, so the system backdrop shows through wherever
/// nothing is drawn.
class WidgetSurface extends ConsumerStatefulWidget {
  const WidgetSurface({super.key});

  /// Everything this widget needs arrives through `ref`: the notes, the window
  /// state, the palette, whether acrylic is available. None of it is a parameter.
  /// `AGENTS.md` §0.8 — and this file was the worst offender at 3 injected
  /// parameters and 9 `AnimatedBuilder` subscriptions.
  ///
  /// The palette could not arrive through the theme even if it were passed: this
  /// surface deliberately replaces the app theme with a bare `ThemeData`, because it
  /// is drawn over the desktop rather than over the app's own background.

  @override
  ConsumerState<WidgetSurface> createState() => _WidgetSurfaceState();
}

class _WidgetSurfaceState extends ConsumerState<WidgetSurface> {
  final ScrollController _scroll = ScrollController();
  /// The widget surface's own controller, reached through `ref`.
  ///
  /// A getter rather than a field, so every call site reads `controller`
  /// still meaning "the notifier" - but now from a provider rather than from a
  /// constructor. `read` and not `watch`: the notifier is for *doing*, and watching
  /// it here would rebuild the whole surface on every note edit in addition to the
  /// `watch` further down that already does exactly that.
  WidgetNotifier get controller => _notifier;

  /// Captured in [initState] because Riverpod forbids *any* `ref` use inside
  /// `dispose`, not merely use after an await.
  ///
  /// `dispose` needs the notifier to tell the runner to give the keyboard back when
  /// the surface is torn down with its composer open. Reaching for `ref` there throws
  /// `Bad state: Using "ref" when a widget is about to or has been unmounted`, and
  /// the failure lands during tree finalisation - after the test has already passed -
  /// so it is reported as a separate error and is easy to miss.
  ///
  /// Same rule as the two roots; see `_EditorScopeState`.
  late final WidgetNotifier _notifier;

  /// The current window state, watched where it is drawn.
  WidgetSurfaceState get _state => ref.read(widgetProvider).requireValue;

  /// The palette, from a provider rather than from the theme - see the class doc.
  WinNotesPalette get palette => ref.read(accentPaletteProvider);

  Brightness get brightness => ref.read(widgetSurfaceThemeProvider).brightness;

  bool get acrylicAvailable {
    final settings = ref.read(settingsProvider).value?.settings;
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
      final offset = ref.read(widgetProvider).value?.window.scrollOffset ?? 0.0;
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
    // While the composer is open, the pointer belongs to the text field. The
    // grab band runs along the very bottom of the widget, which is exactly where
    // the field sits, so without this a click near its edge would resize the
    // window instead of placing the caret - and dragging the widget while
    // halfway through typing a note is nobody's intention.
    if (_composing.value) return;
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
      onOpenEditor();
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
    final resizeEdge = _toResizeEdge(gesture.edge);
    unawaited(controller.beginResize(resizeEdge, gesture.anchor));
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
    final state = _state.window;
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

  final ValueNotifier<bool> _lockedHint = ValueNotifier<bool>(false);
  Timer? _hintTimer;

  /// The add-a-note field, and whether it is open.
  ///
  /// Open means the widget is holding the keyboard, which is a real thing to be
  /// responsible for: the runner drops the window's WS_EX_NOACTIVATE so the text
  /// field can work at all, and puts it back the moment this goes false. Every
  /// path out of here - saved, cancelled, disposed - has to close it, or the
  /// widget keeps the caret for the rest of the session.
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
    final raw = _compose.text.trim();
    if (raw.isEmpty) {
      _closeComposer();
      return;
    }
    // First line is the title, the rest is the body. It is the same shape the
    // widget already displays - a line, then a preview - so a note jotted here
    // looks like a note written in the editor, with no second box to fill in.
    final split = raw.indexOf('\n');
    final title = split < 0 ? raw : raw.substring(0, split).trim();
    final body = split < 0 ? '' : raw.substring(split + 1).trim();
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
    // Closing rather than disposing leaves the window as it found it. A widget
    // that kept WS_EX_NOACTIVATE dropped would hold the caret with no field
    // visible to type into.
    // Read once, here, while the element is still alive.
    //
    // Riverpod asserts on *any* `ref` use inside `dispose`, so a call routed through
    // the [controller] getter throws `Bad state: Using "ref" when a widget is about
    // to or has been unmounted`. The notifier is captured instead, which is the same
    // rule the two roots follow - see `_EditorScopeState`.
    //
    // Worth noting what this protects: a widget torn down while its composer is open
    // would otherwise leave the native window holding the keyboard with no field
    // visible to type into, and the only symptom would be a desktop widget that
    // swallows typing.
    if (_composing.value) unawaited(_notifier.setComposeMode(active: false));
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _thumbOpacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = brightness == Brightness.dark;
    // Resolved through the palette rather than read from the theme, so the
    // focused card's bar, the tick and the composer's border cannot disagree
    // with the editor about what the accent is.
    final accent = palette.accentFor(brightness);

    // One `watch` on the surface state, and everything below rebuilds from it.
    // The previous version had nine `AnimatedBuilder`s over the same controller, so
    // a single keystroke in a note ran nine rebuilds of overlapping subtrees.
    final surface = ref.watch(widgetProvider).value;
    final notes = surface?.displayNotes ?? const [];

    // Three `ValueNotifier`s that were `setState` fields until 2026-10-05, merged
    // into one listener so the surface repaints when any of them changes.
    //
    // **This listener is not optional.** Without it the notifiers were written and
    // nothing listened: a refused drag set `_lockedHint` and the "Locked in place"
    // hint never appeared. `no_set_state_test` cannot catch that - it checks that
    // `setState` is gone, not that its replacement rebuilds. Two of these three were
    // read from inside another builder and one was not, which is the shape a
    // mechanical rewrite leaves behind and the reason the missing one is named here.
    return ListenableBuilder(
      listenable: Listenable.merge([_hovering, _composing, _lockedHint]),
      builder: (context, _) {
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
              children: [
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
                    child: _FloatingScrollRail(
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
                    child: _LockedHint(visible: _lockedHint.value, dark: dark),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _Composer(
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

/// The add-a-note affordance, and the field it turns into.
///
/// One slot, two states, rather than a button that reveals a panel somewhere
/// else. The thing you click is the thing that appears where you clicked, so
/// there is nothing to hunt for and nothing new to remember - and because it
/// lives in the bottom strip it never disturbs the cards, which is what the
/// widget is for.
///
/// Collapsed it is a circle that is nearly invisible until the pointer is over
/// the widget. Faint rather than absent, because a control that only exists on
/// hover is a control half the people who could use it will never find - and an
/// always-visible button in the corner of every note list is worse.
///
/// Open, the widget is a text field, which means it is holding your keyboard.
/// It gives it straight back when the note is saved or cancelled, and the runner
/// returns focus to whatever had it rather than leaving the caret in a corner of
/// the desktop.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.open,
    required this.revealed,
    required this.field,
    required this.focusNode,
    required this.dark,
    required this.accent,
    required this.onOpen,
    required this.onClose,
    required this.onSubmit,
  });

  final bool open;
  final bool revealed;
  /// The note field's own controller. Named for what it is rather than controller,
  /// because a generic name here reads as shared state and it is not: this widget
  /// creates it, hands it to a TextField and disposes it.
  final TextEditingController field;
  final FocusNode focusNode;
  final bool dark;
  final Color accent;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = widgetMutedColor(dark ? Brightness.dark : Brightness.light);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          // Grows downwards from the bottom edge, so the field appears to come
          // out of where the button was rather than sliding in from nowhere.
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      // Escape, because a text field that cannot be dismissed with the keyboard
      // traps the keyboard - and this one is holding it. Clicking away does not
      // help: the widget has focus precisely so that typing works, so the click
      // that dismisses it has to be inside the widget too.
      child: CallbackShortcuts(
        bindings: open
            ? <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
              }
            : const <ShortcutActivator, VoidCallback>{},
        child: open ? _field(context, theme, muted) : _button(context, muted),
      ),
    );
  }

  Widget _button(BuildContext context, Color muted) {
    return Align(
      alignment: Alignment.bottomRight,
      child: AnimatedOpacity(
        // Never fully gone: see the class comment.
        opacity: revealed ? 1 : 0.28,
        duration: const Duration(milliseconds: 140),
        child: Semantics(
          button: true,
          label: 'Add a note',
          child: Tooltip(
            message: 'Add a note',
            // The SizedBox is outside the Material on purpose. A Material with a
            // clip shape expands to fill whatever it is given, so the circle
            // would silently become the full width of the widget and swallow
            // taps meant for the cards above it.
            child: SizedBox(
              width: 30,
              height: 30,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  // Keyed rather than found by label: the Semantics above and
                  // the Tooltip's own both answer to "Add a note", so a
                  // label-based finder is ambiguous about which box it means -
                  // and the ambiguity is invisible until the tap misses.
                  key: addNoteButtonKey,
                  onTap: onOpen,
                  customBorder: const CircleBorder(),
                  child: Icon(Icons.add, size: 17, color: muted),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(BuildContext context, ThemeData theme, Color muted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widgetBodyColor(dark ? Brightness.dark : Brightness.light)
              .withValues(alpha: dark ? 0.10 : 0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: addNoteFieldKey,
                  controller: field,
                  focusNode: focusNode,
                  // One line, and Enter saves. A note with several lines is a
                  // note being written, not a note being jotted down, and that
                  // is what the editor is for.
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSubmit(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: widgetBodyColor(
                      dark ? Brightness.dark : Brightness.light,
                    ),
                    height: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add a note',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 15),
                tooltip: 'Cancel',
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                color: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keys for the add-a-note controls, so they can be driven without guessing at
/// which of two same-labelled semantics nodes is meant.
///
/// Public because a widget test is a consumer of this widget, and a finder that
/// has to reverse-engineer the layout to aim at a 30-pixel circle in the corner
/// is a finder that will silently start hitting the wrong thing.
const Key addNoteButtonKey = ValueKey('winnotes.widget.addNote');
const Key addNoteFieldKey = ValueKey('winnotes.widget.addNoteField');

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
    required this.scroll,
    required this.opacity,
  });

  final ScrollController scroll;
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
                  listenable: scroll,
                  builder: (context, _) {
                    if (!scroll.hasClients) return const SizedBox.shrink();
                    final position = scroll.position;
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
