import 'package:flutter/material.dart';

/// Asks before doing something that cannot be undone from within the app.
///
/// Used for deleting a note, which is the one action with no recovery path once
/// the undo window closes. The destructive style is not decoration: it is the
/// only signal that separates "Delete" from "Discard changes".
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC0392B),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// A short-lived bar offering to put a deleted note back.
///
/// Undo is deliberately time-boxed and never persisted. A Recently Deleted
/// list would fight the plainness the app is built around, but "delete is
/// unrecoverable" is genuinely harsh for a place people leave things without
/// thinking, so a few seconds of grace is the middle ground.
///
/// The toast removes itself rather than waiting for a timeout callback, so
/// rebuilding the tree underneath it cannot leave it stranded on screen.
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

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (context) => _UndoToastBody(
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

class _UndoToastBody extends StatefulWidget {
  const _UndoToastBody({
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
  State<_UndoToastBody> createState() => _UndoToastBodyState();
}

class _UndoToastBodyState extends State<_UndoToastBody>
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
    final theme = Theme.of(context);
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
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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

/// Shown instead of an empty list or an empty widget.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}