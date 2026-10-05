import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../composer_button/composer_button.dart';
import '../composer_field/composer_field.dart';

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
