import 'package:flutter/material.dart';

/// A short-lived bar offering to put a deleted note back.
/// Undo is time-boxed, never persisted; the toast removes itself so a rebuild
/// underneath cannot leave it stranded on screen.
class UndoToast {
  const UndoToast._();

  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
    Duration duration = const Duration(seconds: 6),
  }) {
    dismiss();

    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) => UndoToastBody(
        message: message,
        duration: duration,
        onUndo: () {
          dismiss();
          onUndo();
        },
        onExpired: dismiss,
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  static void dismiss() {
    _current?.remove();
    _current = null;
  }
}

class UndoToastBody extends StatefulWidget {
  const UndoToastBody({
    super.key,
    required this.message,
    required this.duration,
    required this.onUndo,
    required this.onExpired,
  });

  final String message;
  final Duration duration;
  final VoidCallback onUndo;
  final VoidCallback onExpired;

  @override
  State<UndoToastBody> createState() => _UndoToastBodyState();
}

class _UndoToastBodyState extends State<UndoToastBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.duration, widget.onExpired);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Center(
        child: FadeTransition(
          opacity: _controller,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.inverseSurface,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        widget.message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onInverseSurface,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onUndo,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.inversePrimary,
                    ),
                    child: const Text('Undo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
