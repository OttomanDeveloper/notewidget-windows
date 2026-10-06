import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../composer_button/composer_button.dart';
import '../composer_field/composer_field.dart';

/// The add-a-note affordance, and the field it turns into. One slot, two states:
/// the clicked thing appears where clicked, never disturbing the cards. Faint when
/// collapsed (hover-only controls are never found); keyboard handed straight back.
class WidgetComposer extends StatelessWidget {
  const WidgetComposer({
    super.key,
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (Widget child, Animation<double> animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          // Grows downwards from the bottom edge, so the field appears to come
          // out of where the button was rather than sliding in from nowhere.
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
        // Escape: a text field that cannot be dismissed traps the keyboard it holds;
        // the dismissing click must be inside the widget too.
      child: CallbackShortcuts(
        bindings: open
            ? <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
              }
            : const <ShortcutActivator, VoidCallback>{},
        child: open
            ? ComposerField(
                field: field,
                focusNode: focusNode,
                dark: dark,
                accent: accent,
                onClose: onClose,
                onSubmit: onSubmit,
              )
            : ComposerButton(
                revealed: revealed,
                dark: dark,
                onOpen: onOpen,
              ),
      ),
    );
  }
}
