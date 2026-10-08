import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/widgets/completion_toggle/completion_toggle.dart';
import '../../../../../core/widgets/markdown_density/markdown_density.dart';
import '../../../../../core/widgets/markdown_text/markdown_text.dart';
import '../../../../notes/domain/note.dart';
import '../../../domain/widget_design.dart';
import '../design_edge_painter/design_edge_painter.dart';

/// One note drawn as the chosen design: paper, stamp, ticket, soft or receipt.
/// It replaces the card rather than decorating it, and the surface picks one or
/// the other - `build()` keeps its body, and one widget is one file.
class DesignedNote extends StatelessWidget {
  const DesignedNote({
    super.key,
    required this.note,
    required this.design,
    required this.accent,
    required this.titleColor,
    required this.bodyColor,
    required this.mutedColor,
    required this.large,
    required this.done,
    required this.focused,
    required this.onTap,
    required this.onToggleCompleted,
  });

  final Note note;
  final WidgetDesign? design;
  final Color accent;
  final Color titleColor;
  final Color bodyColor;
  final Color mutedColor;
  final bool large;
  final bool done;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onToggleCompleted;

  /// The built-in card's own budget arithmetic, so a design scales the line count
  /// rather than inventing a second rule for what "two lines" means.
  static double budgetFor({required bool large, required double scale}) =>
      MarkdownText.budgetForLines(
        fontSize: 13,
        lineHeight: 1.35,
        lines: math.max(1, ((large ? 7 : 2) * scale).round()),
      );

  @override
  Widget build(BuildContext context) {
    final DesignLook look = lookOfDesign(design);
    final bool isStamp = design?.casing == DesignCasing.upper;
    final bool hasBody = note.body.trim().isNotEmpty;
    final bool roomy = look.cornerRadius > 12;

    final TextStyle title = TextStyle(
      fontSize: large ? 18 : 13,
      height: 1.3,
      fontWeight: isStamp
          ? FontWeight.w800
          : (large ? FontWeight.w700 : FontWeight.w600),
      letterSpacing: isStamp ? 1.6 : 0,
      color: titleColor,
      fontFamily: look.titleFont.isEmpty ? null : look.titleFont,
    );
    final TextStyle body = TextStyle(
      fontSize: large ? 13 : 11,
      height: 1.35,
      color: bodyColor,
      fontFamily: look.bodyFont.isEmpty ? null : look.bodyFont,
      fontFamilyFallback:
          look.bodyFontFallback.isEmpty ? null : look.bodyFontFallback,
    );

    // A stamp is pressed, and pressed type is capital, so the body is set
    // like the title - on the source, since `MarkdownText` takes a string.
    // It costs a code span its case; invisible here, we never follow a link.
    final String bodySource = isStamp ? note.body.toUpperCase() : note.body;

    // A perforation or a torn edge is drawn at the bottom of the card, so the card
    // has to leave room for it - otherwise it lands on the last line of text.
    // Measured on a release build: both cut straight through the body.
    final double edgeRoom = switch (look.edge) {
      DesignEdge.perforated => 13,
      DesignEdge.torn => 12,
      _ => 0.0,
    };

    final Widget sheet = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: focused && !done ? accent.withValues(alpha: 0.08) : null,
        borderRadius: look.shape,
        boxShadow: look.shadow
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: <Widget>[
          // Behind the text, and filling the **whole** card rather than just
          // the content: an edge painted at the bottom of the content lands
          // on the last line of text.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: DesignEdgePainter(look.edge, bodyColor)),
            ),
          ),
          // The padding is inside the stack for that reason - it is the room the
          // bottom edge is drawn in.
          Padding(
            padding: EdgeInsets.only(
              left: roomy ? 18 : 13,
              right: roomy ? 18 : 13,
              top: roomy ? 15 : 9,
              bottom: (roomy ? 15 : 9) + edgeRoom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
              // Offset clear of the outer resize grab, as the card does it, so
              // the tick is never swallowed by it.
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: CompletionToggle(
                  completed: note.isCompleted,
                  onToggle: onToggleCompleted,
                  diameter: large ? 20 : 16,
                  hitTarget: (large ? 20 : 16) + 6,
                  color: note.isCompleted ? accent : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DefaultTextStyle.merge(
                  style: body,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DefaultTextStyle.merge(
                        style: markCompleted(const TextStyle(), completed: done) ??
                            const TextStyle(),
                        child: note.markdown
                            ? MarkdownText.inline(
                                isStamp ? note.title.toUpperCase() : note.title,
                                color: titleColor,
                                accent: accent,
                                style: markCompleted(title, completed: done)!,
                                maxLines: large ? 2 : 1,
                              )
                            : Text(
                                isStamp
                                    ? note.displayTitle.toUpperCase()
                                    : note.displayTitle,
                                maxLines: large ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: markCompleted(title, completed: done),
                              ),
                      ),
                      if (hasBody) ...<Widget>[
                        SizedBox(height: large ? 7 : 3),
                        DefaultTextStyle.merge(
                          style:
                              markCompleted(const TextStyle(), completed: done) ??
                                  const TextStyle(),
                          child: note.markdown
                              ? MarkdownText(
                                  source: bodySource,
                                  color: bodyColor,
                                  accent: accent,
                                  mutedColor: mutedColor,
                                  density: MarkdownDensity.widget,
                                  maxHeight: budgetFor(
                                    large: large,
                                    scale: look.budgetScale,
                                  ),
                                  headingScale: large ? null : 1.0,
                                )
                              : Text(
                                  bodySource.replaceAll(_breaks, ' '),
                                  maxLines: large ? 4 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: body,
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (isStamp)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    'NO.${note.id.hashCode.abs() % 1000}',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.2,
                      color: bodyColor.withValues(alpha: 0.55),
                      fontFamily:
                          look.bodyFont.isEmpty ? null : look.bodyFont,
                    ),
                  ),
                ),
            ],
          ),
              ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: note.displayTitle,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: look.shape,
          child: look.tilt == 0
              ? sheet
              : Transform.rotate(
                  angle: look.tilt,
                  alignment: Alignment.topLeft,
                  child: sheet,
                ),
        ),
      ),
    );
  }

  /// Line breaks flattened for the compact card, so a multi-line note reads as
  /// one line rather than truncating at the first newline.
  static final RegExp _breaks = RegExp(r'\s*\n\s*');
}
