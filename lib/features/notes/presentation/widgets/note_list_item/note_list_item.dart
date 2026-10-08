import 'package:flutter/material.dart';

import '../../../domain/note.dart';
import '../../../../../core/theme/skin.dart';
import '../../../../../core/widgets/completion_toggle/completion_toggle.dart';
import '../../../../../core/widgets/markdown_density/markdown_density.dart';
import '../../../../../core/widgets/markdown_text/markdown_text.dart';

class NoteListItem extends StatelessWidget {
  const NoteListItem({
    super.key,
    required this.note,
    required this.selected,
    required this.onTap,
    required this.onToggleCompleted,
    this.skin,
  });

  final Note note;
  final bool selected;
  final VoidCallback onTap;

  /// Separate from [onTap] so ticking a task off does not also open it. Working
  /// through a list means pressing the same small circle a dozen times in a row,
  /// and having the editor jump to each note in turn makes that unusable.
  final VoidCallback onToggleCompleted;

  /// The row's shape, crossing as a value like `note` does. Null means the
  /// built-in look, which is what every install without a skin gets.
  final WinNotesSkin? skin;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool done = note.isCompleted;
    final SkinLook look = lookOf(skin);
    // The caret colour marks selection, tying the list to the mark. A finished
    // note gives it up: it is no longer the one to pick up.
    final bool marked = selected && !done;

    return Material(
      color: switch (look.focus) {
        SkinFocus.fill when marked => scheme.primary.withValues(alpha: 0.16),
        SkinFocus.bar when marked => scheme.primary.withValues(alpha: 0.10),
        _ => Colors.transparent,
      },
      child: InkWell(
        onTap: onTap,
        borderRadius: look.shape,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            look.pad(14),
            look.pad(10),
            look.pad(14),
            look.pad(10),
          ),
          decoration: BoxDecoration(
            // A `Border` with one coloured side cannot carry a `borderRadius`.
            // So the edge of a `bar` skin is a child of the Stack below, and
            // the border here stays uniform.
            borderRadius: look.shape,
            border: marked && look.focus == SkinFocus.outline
                ? Border.all(color: scheme.primary, width: 1.5)
                : Border.all(color: Colors.transparent),
          ),
          child: Stack(
            children: <Widget>[
              Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: CompletionToggle(
                  completed: done,
                  onToggle: onToggleCompleted,
                  diameter: 18,
                  hitTarget: 30,
                  color: done ? scheme.primary : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // A Markdown title gets inline formatting like a widget card
                    // (`**`, backticks — but `#` stays literal: one line, no headings).
                    if (note.markdown)
                      MarkdownText.inline(
                        note.title,
                        color: done
                            ? scheme.onSurfaceVariant.withValues(alpha: 0.75)
                            : scheme.onSurface,
                        accent: scheme.primary,
                        style: markCompleted(
                          theme.textTheme.titleSmall?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: done
                                ? scheme.onSurfaceVariant
                                    .withValues(alpha: 0.75)
                                : scheme.onSurface,
                          ),
                          completed: done,
                        )!,
                        maxLines: 1,
                      )
                    else
                      Text(
                        note.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: markCompleted(
                          theme.textTheme.titleSmall?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: done
                                ? scheme.onSurfaceVariant
                                    .withValues(alpha: 0.75)
                                : scheme.onSurface,
                          ),
                          completed: done,
                        ),
                      ),
                    const SizedBox(height: 3),
                    // Skipped entirely when there is no body, rather than
                    // rendered as an empty line. See _preview.
                    if (note.body.trim().isNotEmpty)
                      if (note.markdown)
                        // Same renderer as the widget card, clamped by height (not
                        // `maxLines`: that bounds one Text, not twenty one-line
                        // paragraphs). Headings flatten to body size like a compact card.
                        DefaultTextStyle(
                          style: markCompleted(const TextStyle(),
                                  completed: done) ??
                              const TextStyle(),
                          child: MarkdownText(
                            source: note.body,
                            color: done
                                ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                                : scheme.onSurfaceVariant,
                            accent: scheme.primary,
                            mutedColor: scheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                            density: MarkdownDensity.widget,
                            fontSize:
                                theme.textTheme.bodySmall?.fontSize ?? 12,
                            headingScale: 1.0,
                            maxHeight: _previewHeight(theme),
                          ),
                        )
                      else
                        Text(
                          _preview(note),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: markCompleted(
                            theme.textTheme.bodySmall?.copyWith(
                              color: done
                                  ? scheme.onSurfaceVariant
                                      .withValues(alpha: 0.6)
                                  : scheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                            completed: done,
                          ),
                        ),
                  ],
                ),
              ),
            ],
              ),
              if (marked && look.focus == SkinFocus.bar)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(width: 3, color: scheme.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

    /// Two body-size lines at 1.35 height, matching plain rows; the fade comes
    /// out of the third (see [MarkdownText.budgetForLines]).
  static double _previewHeight(ThemeData theme) =>
      MarkdownText.budgetForLines(
        fontSize: theme.textTheme.bodySmall?.fontSize ?? 12,
        lineHeight: 1.35,
        lines: 2,
      );

  /// Falls back to the title when there is no body yet. "No text yet" is
  /// reserved for a note with nothing in it at all.
  static String _preview(Note note) {
    final String body = note.body.trim();
    if (body.isNotEmpty) return body.replaceAll('\n', ' ');
    if (note.title.trim().isNotEmpty) return '';
    return 'No text yet';
  }
}
