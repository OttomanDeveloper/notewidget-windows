import 'package:flutter/material.dart';

import '../../../../../core/theme/theme.dart';

/// The key for the add-a-note button: drivable without guessing among same-labelled
/// semantics nodes. Public because widget tests are consumers of this widget.
const Key addNoteButtonKey = ValueKey<String>('winnotes.widget.addNote');

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
    final Color muted = widgetMutedColor(dark ? Brightness.dark : Brightness.light);
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
              // Outside the Material on purpose: it would otherwise expand to full
              // width and swallow neighbouring taps.
            child: SizedBox(
              width: 30,
              height: 30,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                    // Keyed, not label-found: Semantics and Tooltip share the label, so a
                    // label finder is ambiguous until the tap misses.
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
