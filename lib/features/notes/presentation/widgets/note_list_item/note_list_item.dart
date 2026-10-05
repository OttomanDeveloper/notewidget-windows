import 'package:flutter/material.dart';

import '../../../domain/note.dart';
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
  });

  final Note note;
  final bool selected;
  final VoidCallback onTap;

  /// Separate from [onTap] so ticking a task off does not also open it. Working
  /// through a list means pressing the same small circle a dozen times in a row,
  /// and having the editor jump to each note in turn makes that unusable.
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = note.isCompleted;

    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                // The caret colour marks selection, tying the list to the mark.
                // A finished note gives it up: it is no longer the one to pick up.
                color: selected && !done ? scheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  children: [
                    // A Markdown note's title gets its inline formatting, the
                    // same as on a widget card: a title is one line by
                    // definition, so `#` in one is a mistake rather than a
                    // heading, but `**` and backticks are someone being
                    // emphatic.
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
                        // The same renderer as the widget card, at the row's own
                        // type size and clamped to its own two lines.
                        //
                        // Clamped by height rather than by `maxLines`, for the
                        // reason documented in markdown_text.dart: `maxLines`
                        // bounds the lines inside one Text and says nothing
                        // about how many blocks a note has, so a body of twenty
                        // one-line paragraphs sailed past it.
                        //
                        // Headings are flattened to body size, same as a compact
                        // card. A row is two lines in a 300px column, and a
                        // body opening with `# Title` is already repeating the
                        // row's own title above it.
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
        ),
      ),
    );
  }

  /// Vertical room a rendered Markdown preview gets in a row.
  ///
  /// Two lines of the row's own body size at the same 1.35 line height the
  /// plain-text preview uses, so a Markdown row is not taller than a plain one.
  /// The fade band comes out of the *third* line — see
  /// [MarkdownText.budgetForLines].
  static double _previewHeight(ThemeData theme) =>
      MarkdownText.budgetForLines(
        fontSize: theme.textTheme.bodySmall?.fontSize ?? 12,
        lineHeight: 1.35,
        lines: 2,
      );

  /// Falls back to the title when there is no body yet, so a note that has only
  /// been named still shows something useful in the preview slot.
  ///
  /// "No text yet" is reserved for a note with nothing in it at all. A note with
  /// a title and no body has its content right there on the line above, so
  /// claiming otherwise is just wrong - and a note added from the widget's
  /// composer is always in that shape.
  static String _preview(Note note) {
    final body = note.body.trim();
    if (body.isNotEmpty) return body.replaceAll('\n', ' ');
    if (note.title.trim().isNotEmpty) return '';
    return 'No text yet';
  }
}
