import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../notes/domain/note.dart';
import '../../../../../core/widgets/completion_toggle/completion_toggle.dart';
import '../../../../../core/widgets/markdown_text/markdown_text.dart';
import '../../../../../core/widgets/markdown_density/markdown_density.dart';
import '../../../../../core/theme/theme.dart';
import '../../providers/widget_providers.dart';

/// One note in the widget: focused gets the large treatment, others compact, sharing one column.
/// A `ConsumerWidget` watching only its own note, so typing rebuilds one card.
class WidgetNoteCard extends ConsumerWidget {
  const WidgetNoteCard({
    super.key,
    required this.noteId,
    required this.focused,
    required this.onTap,
    required this.accent,
    required this.roomy,
    required this.onToggleCompleted,
    this.dark = false,
  });

  /// The note id to draw; an id may cross as a parameter, the note is read with `ref` [`AGENTS.md` §0.8].
  /// So a card never rebuilds for another card's edit.
  final String noteId;
  final bool focused;
  final VoidCallback onTap;

  /// Marks finished without focusing, separate from [onTap] so ticking does not move the editor selection.
  final VoidCallback onToggleCompleted;

  final Color accent;

  /// Body height budget (2 compact, 7 large) from [MarkdownText.budgetForLines] so the fade is added once.
  static final double _compactBodyHeight = MarkdownText.budgetForLines(
    fontSize: 13,
    lineHeight: 1.35,
    lines: 2,
  );
  static final double _largeBodyHeight = MarkdownText.budgetForLines(
    fontSize: 13,
    lineHeight: 1.35,
    lines: 7,
  );
  final bool dark;

  /// Whether the focused card gets the large treatment, from window size not scroll metrics.
  /// Scroll metrics are unreadable while a sliver lays out, when this builds.
  final bool roomy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gone (deleted or never loaded) reads as empty rather than crashing: the
    // parent list rebuilds on every notes change, so this is only the frame
    // between the deletion and the list catching up.
    final Note? note = ref.watch(widgetNoteByIdProvider(noteId));
    if (note == null) return const SizedBox.shrink();

    final Color bodyColor = widgetBodyColor(
      dark ? Brightness.dark : Brightness.light,
    );
    final Color mutedColor = widgetMutedColor(
      dark ? Brightness.dark : Brightness.light,
    );

    final bool renderLarge = focused && roomy;
    final bool done = note.isCompleted;
    final double toggleSize = renderLarge ? 20.0 : 16.0;

    // Finished notes recede subtly; the runner already draws the widget at reduced opacity.
    final Color titleColor = done
        ? mutedColor.withValues(alpha: 0.7)
        : (renderLarge ? bodyColor : mutedColor);
    final Color previewColor = done
        ? mutedColor.withValues(alpha: 0.6)
        : (renderLarge ? bodyColor.withValues(alpha: 0.88) : mutedColor);

    return Semantics(
      button: true,
      label: note.displayTitle,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: renderLarge ? 16 : 12,
              vertical: renderLarge ? 14 : 8,
            ),
            decoration: BoxDecoration(
              // The focused card is the only one with a surface of its own,
              // which is what makes it obvious which note the editor has open.
              // A finished card gives it up, so the eye goes to what is left.
              color: renderLarge && !done
                  ? accent.withValues(alpha: dark ? 0.16 : 0.09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: renderLarge && !done ? accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Offset clear of the outer resize grab so the tick is not swallowed by it.
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: CompletionToggle(
                    completed: note.isCompleted,
                    onToggle: onToggleCompleted,
                    diameter: toggleSize,
                    hitTarget: toggleSize + 6,
                    color: note.isCompleted ? accent : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: note.markdown
                                // Title is one line: `#` is not a heading here, but `**` and backticks are kept as emphasis.
                                ? MarkdownText.inline(
                                    note.title,
                                    color: titleColor,
                                    accent: accent,
                                    style: markCompleted(
                                      TextStyle(
                                        fontSize: renderLarge ? 18 : 13,
                                        height: 1.25,
                                        fontWeight: renderLarge
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        letterSpacing: renderLarge ? -0.2 : 0,
                                        color: titleColor,
                                      ),
                                      completed: done,
                                    )!,
                                    maxLines: renderLarge ? 2 : 1,
                                  )
                                : Text(
                                    note.displayTitle,
                                    maxLines: renderLarge ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: markCompleted(
                                      TextStyle(
                                        fontSize: renderLarge ? 18 : 13,
                                        height: 1.25,
                                        fontWeight:
                                            renderLarge ? FontWeight.w600 : FontWeight.w500,
                                        letterSpacing: renderLarge ? -0.2 : 0,
                                        color: titleColor,
                                      ),
                                      completed: done,
                                    ),
                                  ),
                          ),
                          if (renderLarge && _hasBody(note))
                            Padding(
                              padding: const EdgeInsets.only(left: 8, top: 2),
                              child: Icon(Icons.push_pin_outlined,
                                  size: 14, color: mutedColor.withValues(alpha: 0.7)),
                            ),
                        ],
                      ),
                      if (_hasBody(note)) ...<Widget>[
                        SizedBox(height: renderLarge ? 8 : 3),
                        if (note.markdown)
                          // Rendered body clamped by height, not line count; see `MarkdownDensity`.
                          DefaultTextStyle(
                            // Carries the strikethrough via `RichText`, since no single span is "the text".
                            style: markCompleted(const TextStyle(),
                                    completed: done) ??
                                const TextStyle(),
                            child: MarkdownText(
                              source: note.body,
                              color: previewColor,
                              accent: accent,
                              mutedColor: mutedColor,
                              density: MarkdownDensity.widget,
                              // Clamped by height, not `maxLines`, which cannot bound multi-block notes; cut lands on a line boundary.
                              maxHeight:
                                  renderLarge ? _largeBodyHeight : _compactBodyHeight,
                              // Only the compact card flattens headings; it already shows the title above.
                              headingScale: renderLarge ? null : 1.0,
                            ),
                          )
                        else
                          Text(
                            _preview(note, renderLarge),
                            maxLines: renderLarge ? 6 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: markCompleted(
                              TextStyle(
                                fontSize: renderLarge ? 14 : 12,
                                height: renderLarge ? 1.5 : 1.35,
                                color: previewColor,
                              ),
                              completed: done,
                            ),
                          ),
                      ] else if (renderLarge && note.title.trim().isEmpty) ...<Widget>[
                        // Only for a fully empty note; a title-only note already shows its content above.
                        const SizedBox(height: 8),
                        Text(
                          'No text yet',
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The tick, aligned to the first line of text rather than centred in the card.

  static bool _hasBody(Note note) => note.body.trim().isNotEmpty;

  /// The focused card keeps line breaks so it reads like the note.
  /// [lineBreaks] is `static final`: no `RegExp` in `build()` [`flutter_architecture_pattern.md` §7.1].
  static final RegExp lineBreaks = RegExp(r'\s*\n\s*');

  static String _preview(Note note, bool renderLarge) {
    final String body = note.body.trim();
    if (renderLarge) return body;
    return body.replaceAll(lineBreaks, ' ');
  }
}