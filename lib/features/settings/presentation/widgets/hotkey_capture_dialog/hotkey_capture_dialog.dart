import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/hotkey_binding.dart';

/// Captures a key combination by waiting for the next keystroke. Not a TextField:
/// typing "ctrl+alt+n" is ambiguous about modifier characters.
class HotkeyCaptureDialog extends StatefulWidget {
  const HotkeyCaptureDialog({super.key, required this.initial});
  final HotkeyBinding initial;

  @override
  State<HotkeyCaptureDialog> createState() => _HotkeyCaptureDialogState();
}

class _HotkeyCaptureDialogState extends State<HotkeyCaptureDialog> {
    /// The combination captured so far. A `ValueNotifier`, not a provider or
    /// `setState`: dialog lifetime only, read by nothing outside it (`AGENTS.md` §0.7).
  late final ValueNotifier<HotkeyBinding> _pending;

  @override
  void initState() {
    super.initState();
    _pending = ValueNotifier<HotkeyBinding>(widget.initial);
  }

  // Modifier keys, as a plain final Set rather than a const one:
  // LogicalKeyboardKey overrides == and hashCode, which Dart forbids in a
  // constant set.
  final Set<LogicalKeyboardKey> _allowed = {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  KeyEventResult _handle(KeyEvent event) {
    final key = event.logicalKey;

    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      if (_allowed.contains(key)) {
        final name = switch (key) {
          LogicalKeyboardKey.control ||
          LogicalKeyboardKey.controlLeft ||
          LogicalKeyboardKey.controlRight =>
            'ctrl',
          LogicalKeyboardKey.alt ||
          LogicalKeyboardKey.altLeft ||
          LogicalKeyboardKey.altRight =>
            'alt',
          LogicalKeyboardKey.shift ||
          LogicalKeyboardKey.shiftLeft ||
          LogicalKeyboardKey.shiftRight =>
            'shift',
          _ => 'win',
        };
        // Which physical modifier is held does not matter; only which ones.
        final next = {..._pending.value.modifiers};
        if (next.contains(name)) {
          next.remove(name);
        } else {
          next.add(name);
        }
        _pending.value = _pending.value.copyWith(modifiers: next.toList());
        return KeyEventResult.handled;
      }

      final character = event.character;
      if (character != null && character.isNotEmpty) {
        _pending.value = _pending.value.copyWith(key: character);
        return KeyEventResult.handled;
      }
      final named = _nameFor(key);
      if (named != null) {
        _pending.value = _pending.value.copyWith(key: named);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.handled;
  }

  static String? _nameFor(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.isEmpty) return null;
    // Single printable characters arrive with no character but do have a label.
    if (label.length == 1) return label;
    if (key.keyId >= LogicalKeyboardKey.f1.keyId &&
        key.keyId <= LogicalKeyboardKey.f12.keyId) {
      return label.toUpperCase();
    }
    return switch (key) {
      LogicalKeyboardKey.space => 'Space',
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.escape => 'Escape',
      LogicalKeyboardKey.tab => 'Tab',
      LogicalKeyboardKey.backspace => 'Backspace',
      LogicalKeyboardKey.delete => 'Delete',
      LogicalKeyboardKey.insert => 'Insert',
      LogicalKeyboardKey.home => 'Home',
      LogicalKeyboardKey.end => 'End',
      LogicalKeyboardKey.pageUp => 'PageUp',
      LogicalKeyboardKey.pageDown => 'PageDown',
      LogicalKeyboardKey.arrowLeft => 'Left',
      LogicalKeyboardKey.arrowRight => 'Right',
      LogicalKeyboardKey.arrowUp => 'Up',
      LogicalKeyboardKey.arrowDown => 'Down',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
      // The draft, read through a listener: the first version read it bare, so the
      // dialog kept showing the combination it opened with (`no_set_state_test` caught
      // it; key events are not tappable by tests).
    return ListenableBuilder(
      listenable: _pending,
      builder: (context, _) {
        final registrable = _pending.value.isRegistrable;

        return AlertDialog(

      title: const Text('Set the shortcut'),
      content: Focus(
        autofocus: true,
        onKeyEvent: (node, event) => _handle(event),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Center(
                child: Text(
                  _pending.value.display,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: registrable
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              registrable
                  ? 'Press the combination you want. Modifiers toggle as you '
                      'press them.'
                  : 'Add at least one modifier other than the Windows key.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: registrable
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: registrable
              ? () => Navigator.of(context).pop(_pending.value)
              : null,
          child: const Text('Use this'),
        ),
      ],
        );
      },
    );
  }
}
