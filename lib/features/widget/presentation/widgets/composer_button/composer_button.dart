import 'package:flutter/material.dart';

import '../../../../../core/theme/theme.dart';

/// The key for the add-a-note button, so it can be driven without guessing at
/// which of two same-labelled semantics nodes is meant.
///
/// Public because a widget test is a consumer of this widget, and a finder that
/// has to reverse-engineer the layout to aim at a 30-pixel circle in the corner
/// is a finder that will silently start hitting the wrong thing.
const Key addNoteButtonKey = ValueKey('winnotes.widget.addNote');

/// The collapsed add-a-note circle.
class ComposerButton extends StatelessWidget {
  const ComposerButton({
    super.key,
    required this.revealed,
    required this.dark,
    required this.onOpen,
  });

  final bool revealed;
  final bool dark;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final muted = widgetMutedColor(dark ? Brightness.dark : Brightness.light);
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
}
