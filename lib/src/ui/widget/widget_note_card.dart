import 'package:flutter/material.dart';

import '../../data/note.dart';
import '../common/completion_toggle.dart';
import '../common/markdown_text.dart';
import '../theme.dart';

/// One note in the widget.
///
/// The design answers the question the spec calls "a design problem rather than
/// a technical one": what happens when notes are different sizes. The focused
/// note gets the large treatment, every other note gets a compact one line at a
/// time, and they share a single scrolling column. Mixed sizes stop being a
/// problem because there is only one size in each state.
class WidgetNoteCard extends StatelessWidget {
  const WidgetNoteCard({
    super.key,
    required this.note,
    required this.focused,
    required this.onTap,
    required this.accent,
    required this.roomy,
    required this.onToggleCompleted,
    this.dark = false,
  });

  final Note note;
  final bool focused;
  final VoidCallback onTap;

  /// Marks this note finished or unfinished, without also focusing it.
  ///
  /// A separate target from [onTap] on purpose. Tapping a card means "I am
  /// working on this"; tapping its tick means "this is done" and should not drag
  /// the editor's selection along with it, because working through a list would
  /// otherwise move the cursor every time you tick something off.
  final VoidCallback onToggleCompleted;

  final Color accent;

  /// How much vertical room a rendered Markdown body gets on the card.
  ///
  /// Sized from the widget density line box rather than written as a magic
  /// number, so changing the density in `markdown_text.dart` moves this with it
  /// instead of leaving the card clipping at a height that no longer means
  /// anything. Two lines on a compact card and seven on a large one - the same
  /// budget the plain-text preview has always had.
  static const double _bodyLine = 13 * 1.35;
  static const double _compactBodyHeight = _bodyLine * 2;
  static const double _largeBodyHeight = _bodyLine * 7;
  final bool dark;

  /// Whether the widget is big enough for the focused card to get the large
  /// treatment.
  ///
  /// Passed in by the caller from the window's own size rather than measured
  /// here from scroll metrics: those are not readable while a sliver is being
  /// laid out, which is exactly when this card is built.
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    final bodyColor = widgetBodyColor(
      dark ? Brightness.dark : Brightness.light,
    );
    final mutedColor = widgetMutedColor(
      dark ? Brightness.dark : Brightness.light,
    );

    final renderLarge = focused && roomy;
    final done = note.isCompleted;

    // The line through the text is the signal; this is the quiet second one, so
    // a long finished list recedes instead of competing with the open tasks for
    // attention. Kept subtle on purpose - the widget is already drawn at reduced
    // opacity by the runner, and dimming much harder starts to look broken
    // rather than finished.
    final titleColor = done
        ? mutedColor.withValues(alpha: 0.7)
        : (renderLarge ? bodyColor : mutedColor);
    final previewColor = done
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
              children: [
                _toggle(),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: note.markdown
                                // The title is one line by definition, so a `#`
                                // in one is a mistake rather than a heading. The
                                // inline formatting is not: `**` and backticks
                                // in a title are someone being emphatic, and a
                                // card is the wrong place to argue with them.
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
                      if (_hasBody(note)) ...[
                        SizedBox(height: renderLarge ? 8 : 3),
                        if (note.markdown)
                          // A rendered body rather than a preview string.
                          //
                          // Clamped by height on the large card rather than by
                          // line count, because block structure means six
                          // rendered lines are not six source lines - a heading
                          // eats three of them. Widget density is what keeps
                          // this readable; see MarkdownDensity.
                          DefaultTextStyle(
                            // Carries the strikethrough. A rendered note is many
                            // spans and none of them is "the text", so the line
                            // cannot be drawn on any one of them. RichText merges
                            // this in instead, which is the only reason it lives
                            // here rather than on a TextStyle nobody reads.
                            style: markCompleted(const TextStyle(),
                                    completed: done) ??
                                const TextStyle(),
                            child: MarkdownText(
                              source: note.body,
                              color: previewColor,
                              accent: accent,
                              mutedColor: mutedColor,
                              density: MarkdownDensity.widget,
                              // Clamped by height, not by line count. `maxLines`
                              // bounds the lines inside one Text, so twenty
                              // one-line paragraphs sailed straight past it and
                              // overflowed the card. A height bound is the only
                              // thing that bounds a note made of blocks.
                              //
                              // It lands on a line boundary rather than through
                              // the middle of one, so the cut reads as "there is
                              // more" instead of as a rendering fault.
                              maxHeight:
                                  renderLarge ? _largeBodyHeight : _compactBodyHeight,
                              // Only the compact card flattens headings. The
                              // large card has seven lines and is the surface
                              // you actually read a note on, so it keeps a real
                              // heading scale; the compact one has two lines and
                              // already shows the note's title directly above,
                              // where a 1.3x `# Title` in the body is a repeat
                              // that costs a third of the card.
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
                      ] else if (renderLarge && note.title.trim().isEmpty) ...[
                        // Only for a note with nothing in it at all. A note with
                        // a title and no body already has its content on screen
                        // in the line above, and telling someone "No text yet"
                        // about a note they have just written is just wrong -
                        // which is how a note added from the widget always looks,
                        // since one line of typing becomes the title.
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
  Widget _toggle() {
    // Sits at least a card's padding in from the left edge. The outer band of the
    // widget is the resize grab, and a tick inside that band would be swallowed
    // by it, so the control has to start clear of it.
    final size = focused && roomy ? 20.0 : 16.0;
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: CompletionToggle(
        completed: note.isCompleted,
        onToggle: onToggleCompleted,
        diameter: size,
        hitTarget: size + 6,
        color: note.isCompleted ? accent : null,
      ),
    );
  }

  static bool _hasBody(Note note) => note.body.trim().isNotEmpty;

  /// The focused card shows more of the body, and keeps its line breaks,
  /// because a note being read at a glance should look like the note.
  static String _preview(Note note, bool renderLarge) {
    final body = note.body.trim();
    if (renderLarge) return body;
    return body.replaceAll(RegExp(r'\s*\n\s*'), ' ');
  }
}