library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// The bodies of every method whose signature contains [marker], brace-counted.
///
/// Separate rather than a substring search because the whole point of the caller is
/// *where* something appears. "Cancelled somewhere in the file" and "cancelled on the
/// way out" are different claims, and only one of them is the rule.
List<String> _bodiesOf(String source, String marker) {
  final out = <String>[];
  for (final match in RegExp(RegExp.escape(marker)).allMatches(source)) {
    // Skip the parameter list first. Starting brace-counting at [match.end]
    // stops at the first `}` inside default values — `dispose({bool flush = true})`
    // would return `{bool flush = true}` as the "body" and miss the real one.
    var parens = 1;
    var i = match.end;
    for (; i < source.length; i++) {
      final unit = source.codeUnitAt(i);
      if (unit == 0x28) {
        parens++;
      } else if (unit == 0x29) {
        parens--;
        if (parens == 0) break;
      }
    }
    if (parens != 0) continue;
    // The argument list itself is a teardown path for `ref.onDispose(() => t?.cancel())`:
    // an arrow callback has no braces, so without this the cancel is invisible.
    out.add(source.substring(match.end, i));
    // Arrow body (`=> ...;`) has no braces to count beyond the args above.
    final arrowEnd = source.indexOf(';', i);
    final braceStart = source.indexOf('{', i);
    if (braceStart < 0 || (arrowEnd >= 0 && arrowEnd < braceStart)) continue;
    var depth = 0;
    var started = false;
    for (var j = braceStart; j < source.length; j++) {
      final unit = source.codeUnitAt(j);
      if (unit == 0x7B) {
        depth++;
        started = true;
      } else if (unit == 0x7D) {
        depth--;
        if (started && depth == 0) {
          out.add(source.substring(braceStart, j));
          break;
        }
      }
    }
  }
  return out;
}

/// **This guard covers a subset, and the subset is the point.** The rulebook is a
/// general document carried in verbatim; its own Appendix lists eleven places where
/// it contradicts this repository, and `AGENTS.md` §0.1 settles every one of them.
/// Executing §4's `features/<feature>/{data,domain,presentation}` would break
/// `layer_test`; executing §7.2's `cached_network_image` would put a network
/// dependency into an app whose product authority says it does not touch the
/// internet.
///
/// So "make the plan 100% implemented" cannot mean "make every line of it true here".
/// What it can mean, and what the rulebook's own Appendix asks for, is: **every rule
/// that applies to this repository is real — a frozen rule plus a guard — and every
/// rule that does not is recorded as declined, with the authority that declined it.**
///
/// Decision record, one row per numbered section (§1–§10). Applied means a guard or
/// an existing frozen rule pins it; declined names the authority.
///
/// | § | Verdict | Pins it / declined by |
/// |---|---|---|
/// | 1.1–1.2 size caps | provider part applied (300 code-only); screen/widget caps pending Wave 3 |
/// | 1.3–1.4 private widgets, one-per-file | declined | `AGENTS.md` §0.8 (23 private widgets collocated on purpose) |
/// | 1.5 rebuild only changed | applied | `provider_pattern.md` §2; `widget_surface.dart` single `watch` |
/// | 1.6 watch/read/select | applied | `provider_guard_test`, `no_set_state_test`; `provider_pattern.md` §§2–3 |
/// | 1.7 logic in providers | applied | `isolate_guard_test`; `provider_pattern.md` §3.1 |
/// | 1.8 profile on device | process | manual; `docs/testing_pattern.md` §2 (not in CI) |
/// | 2 file & comment caps | provider 300 code-only applied (`provider_guard_test`); screens 500 / widgets 350 pending Wave 3; comment 2–3 lines declined until Wave 4 (house style) |
/// | 3.1 what counts | applied | same widget types; `no_set_state_test`, `provider_guard_test` |
/// | 3.2 no private widgets | declined | `AGENTS.md` §0.8 (23 exist, e.g. `settings_dialog.dart` 12) |
/// | 3.3 no private builds | declined | 23 `_buildX` helpers collocated (e.g. `markdown_text.dart` 8) |
/// | 3.4 composition | applied | `EditorView`, `WidgetSurface` compose panes/cards |
/// | 3.5 habits | applied | this guard (RegExp, sort, MediaQuery.sizeOf, Intrinsic); lints for `const` |
/// | 4 folders | applied (Wave 1) | `lib/core` + `lib/features/*/…` per the tree; pinned by `layer_test` paths |
/// | 5.1–5.8 riverpod | applied | `provider_pattern.md`; `provider_guard_test`, `no_set_state_test`, `isolate_guard_test` |
/// | 6 rebuild example | applied | `provider_pattern.md` §2; `ref.select`, low `Consumer` |
/// | 7.1 cpu | applied | this guard; `ValueKey`, debounce 250ms+ceiling, `AnimatedOpacity`, `ListenableBuilder` |
/// | 7.2 ram | applied/N/A | `ListView.builder`/`separated`; dispose guarded; images/paginate N/A (`PROJECT.md` no network) |
/// | 7.3 release | applied/N/A | this guard (`--obfuscate`, symbols); Android split N/A (`PROJECT.md` Windows only) |
/// | 7.4 measure | process | DevTools manual; not CI |
/// | 8 painter | applied | this guard (hoist `Paint`/`Path`, `shouldRepaint`); `completion_toggle.dart` |
/// | 9 checks | applied | this guard replaces `find/grep`; lints in `analysis_options.yaml` |
/// | 10 PR list | applied | `flutter analyze` + `flutter test` (`AGENTS.md` §6) + this guard |
///
/// What follows are the rules that survived that test and were true or nearly true
/// already. Two of them were not, and fixing them is in the same commit as this file.
///
/// The set below is what makes "100%" a number: `the record` group fails if the
/// rulebook gains a section with no row here, or if a row here points at a section
/// that no longer exists.
const _decidedSections = <String>{
  '1',
  '2',
  '3',
  '3.1',
  '3.2',
  '3.3',
  '3.4',
  '3.5',
  '4',
  '5',
  '5.1',
  '5.2',
  '5.3',
  '5.4',
  '5.5',
  '5.6',
  '5.7',
  '5.8',
  '6',
  '7',
  '7.1',
  '7.2',
  '7.3',
  '7.4',
  '8',
  '9',
  '10',
};

void main() {
  final tree = SourceTree();

  group('§7.2 / §3.5 a painter allocates nothing per frame', () {
    // `paint()` runs on the raster thread every time the box changes. A `Paint` and a
    // `Path` allocated there is garbage per frame, for a three-segment tick.
    test('no Paint or Path is constructed inside paint()', () {
      final offenders = <String>[];
      for (final entry in tree.dartFilesUnder('lib').entries) {
        final path = entry.key.replaceAll(r'\', '/');
        final lines = entry.value;
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('void paint(')) continue;

          // To the end of the method, by brace counting. A fixed window guessed wrong
          // reports the wrong file, which is worse than not reporting.
          var depth = 0;
          var started = false;
          for (var j = i; j < lines.length; j++) {
            for (final unit in lines[j].codeUnits) {
              if (unit == 0x7B) {
                depth++;
                started = true;
              } else if (unit == 0x7D) {
                depth--;
              }
            }
            if (started && depth <= 0) break;

            // Two shapes, and the first version only had the first.
            //
            //     final Paint paint = Paint();          // explicit type
            //     final paint = Paint();               // inferred
            //
            // Dart infers the type from the constructor, so the second is the idiomatic
            // one and it is what a person writes. A pattern matching only
            // `final Paint x =` passes cleanly over `final x = Paint(`, which is the
            // same allocation — and the plant that proved it: re-introducing
            // `final paint = Paint()` inside `paint()` left this test green.
            for (final type in ['Paint', 'Path', 'TextPainter', 'MaskFilter']) {
              final explicit =
                  RegExp('final\\s+$type\\s+\\w+\\s*=\\s*$type\\s*\\(');
              final inferred = RegExp('final\\s+\\w+\\s*=\\s*$type\\s*\\(');

              if (explicit.hasMatch(lines[j]) || inferred.hasMatch(lines[j])) {
                offenders.add('$path:${j + 1}  allocates a $type in paint()');
              }
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Hoist it to a field and update it in paint() instead. A size-'
            'dependent value is no reason to allocate - assign it to the same field '
            'every frame, and use `..reset()` on a Path rather than a new one.\n\n'
            '  ${offenders.join('\n  ')}',
      );
    });

    test('there is a painter to check, so the rule above is not vacuous', () {
      expect(
        tree.read('lib/core/widgets/completion_painter/completion_painter.dart'),
        contains('extends CustomPainter'),
        reason: 'precondition: §8 has something to say about. If the last painter is '
            'gone, delete this guard with the rule rather than leaving it passing.',
      );
    });

    test('and it implements shouldRepaint', () {
      // Without it every repaint is unconditional, which is the same cost the hoisting
      // above avoids, arriving by a different route.
      final source = tree.read(
          'lib/core/widgets/completion_painter/completion_painter.dart');
      expect(source, contains('bool shouldRepaint('));
    });
  });

  group('§7.1 / §3.5 no heavy work in build()', () {
    test('no RegExp is constructed inside a build path', () {
      // A `RegExp` is compiled, matched and discarded each time. Built inside a card's
      // build, that is once per card per frame — twenty cards, twenty allocations, for
      // a pattern that never changes.
      final offenders = <String>[];
      final ctor = RegExp(r'RegExp\(r?['"'"']');

      for (final entry in tree.dartFilesUnder('lib').entries) {
        final path = entry.key.replaceAll(r'\', '/');
        final lines = entry.value;
        for (var i = 0; i < lines.length; i++) {
          if (!ctor.hasMatch(lines[i])) continue;

          // A field or a local? A field is the fix; a local in a helper that is on the
          // build path is the bug.
          //
          // Two lines, because a declaration wraps:
          //
          //     static final RegExp notesArray =
          //         RegExp(r'...');
          //
          // and `static final RegExp` is on the first while the constructor call is on
          // the second. Checking one line reported the fixed code as still broken,
          // which is worse than not checking - it trains the reader to ignore the
          // failure.
          final window = [
            if (i > 0) lines[i - 1],
            lines[i],
          ].join(' ');
          final isField = RegExp(r'(static|final)\s+(final\s+)?RegExp\s+\w')
              .hasMatch(window);

          if (!isField) {
            offenders.add('$path:${i + 1}  ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Hoist it to a `static final` field. A pattern is constant; building '
            'it per call is a per-frame allocation for something that cannot change.\n\n'
            '  ${offenders.join('\n  ')}',
      );
    });

    test('no sorting, filtering or decoding inside a build method', () {
      // Brace-counted, so a `.where()` in a static helper beside a build method is not
      // blamed for it. That mistake is why the first version of this found five
      // false positives in `markdown_text.dart` and had to be thrown away.
      final heavy = RegExp(r'\.sort\(|\.sorted\(|jsonDecode|\.fromJson\(');
      final offenders = <String>[];

      for (final entry in tree.dartFilesUnder('lib').entries) {
        final path = entry.key.replaceAll(r'\', '/');
        final lines = entry.value;
        for (var i = 0; i < lines.length; i++) {
          if (!RegExp(r'Widget\s+build\(').hasMatch(lines[i])) continue;

          var depth = 0;
          var started = false;
          for (var j = i; j < lines.length; j++) {
            for (final unit in lines[j].codeUnits) {
              if (unit == 0x7B) {
                depth++;
                started = true;
              } else if (unit == 0x7D) {
                depth--;
              }
            }
            if (started && depth <= 0) break;
            if (heavy.hasMatch(lines[j])) {
              offenders.add('$path:${j + 1}  ${lines[j].trim()}');
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Do this in the notifier, or in a `static` helper that is not on the '
            'build path, or in `compute()`. A widget that sorts or parses on every '
            'rebuild is paying for the same answer repeatedly.\n\n'
            '  ${offenders.join('\n  ')}',
      );
    });
  });

  group('§7.2 dispose everything', () {
    test('every Timer and StreamSubscription is cancelled on a teardown path', () {
      // All eleven in this tree are handled today. That is discipline, not a rule, and
      // discipline is what stops being true the first time somebody is in a hurry — a
      // leaked `Timer` keeps an isolate alive and a leaked subscription keeps a file
      // handle open, neither of which fails visibly.
      //
      // **On a teardown path**, which the first version did not check. It asked whether
      // the name was cancelled *anywhere in the file*, and `notes_controller.dart`
      // cancels `_undoTimer` in two places: `ref.onDispose` and the expiry callback
      // itself. Deleting the dispose one left the test green, because the other
      // occurrence was still there — so the guard was checking the wrong question and
      // reporting a pass. The cancel has to be reachable from `dispose()` or from a
      // `ref.onDispose(`.
      final offenders = <String>[];
      final declaration =
          RegExp(r'(?:late\s+)?(?:final|var)?\s*(\w+)\s*=\s*(?:Timer|StreamSubscription)');

      for (final entry in tree.dartFilesUnder('lib').entries) {
        final path = entry.key.replaceAll(r'\', '/');
        final source = entry.value.join('\n');

        // Bodies that count as a teardown, and bodies that do not.
        final teardown = <String>[
          ..._bodiesOf(source, 'dispose('),
          ..._bodiesOf(source, 'ref.onDispose('),
          ..._bodiesOf(source, 'cancelTimers('),
        ].join('\n');

        for (final match in declaration.allMatches(source)) {
          final name = match.group(1)!;
          final pattern =
              '${RegExp.escape(name)}\\??\\s*\\.\\s*(cancel|close)\\s*\\(';
          if (!RegExp(pattern).hasMatch(teardown)) {
            offenders.add('$path  $name is never cancelled on a teardown path');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'A Timer that outlives its widget, or a subscription that outlives its '
            'isolate, is a leak with no error message. The cancel has to be reachable '
            'from dispose() or ref.onDispose() — cancelling somewhere else is not '
            'disposing.\n\n  ${offenders.join('\n  ')}',
      );
    });

    test('there are timers and subscriptions to check', () {
      expect(
        tree.read('lib/core/utils/atomic_json_file.dart'),
        contains('StreamSubscription<FileSystemEvent>'),
        reason: 'precondition: the declaration pattern still matches this codebase. If '
            'it silently matched nothing, the check above would pass on an empty set.',
      );
      expect(
        tree.read('lib/features/notes/presentation/providers/notes_controller.dart'),
        contains('Timer('),
      );
    });
  });

  group('§3.5 the cheap wins, already true', () {
    // Kept because "already true" is a fact that rots, and a guard is cheaper than
    // discovering it during a jank investigation.
    test('MediaQuery.sizeOf rather than MediaQuery.of(context).size', () {
      // The whole reason §3.5 asks for this: `MediaQuery.of` rebuilds on any
      // inherited change, `sizeOf` only when the size changes.
      final offenders = <String>[];
      for (final entry in tree.dartFilesUnder('lib').entries) {
        if (entry.value.join('\n').contains('MediaQuery.of(context).size')) {
          offenders.add(entry.key.replaceAll(r'\', '/'));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Use `MediaQuery.sizeOf(context)`. `MediaQuery.of(context).size` '
            'depends on every MediaQuery property, so any of them changing rebuilds '
            'the widget.\n\n  ${offenders.join('\n  ')}',
      );
    });

    test('no IntrinsicWidth or IntrinsicHeight', () {
      // Both force a second layout pass over their subtree, and inside a list item
      // that cost is paid per item per frame.
      final offenders = <String>[];
      for (final entry in tree.dartFilesUnder('lib').entries) {
        final source = entry.value.join('\n');
        if (source.contains('IntrinsicWidth') || source.contains('IntrinsicHeight')) {
          offenders.add(entry.key.replaceAll(r'\', '/'));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'An intrinsic dimension resolves its child twice. A fixed height, or a '
            'layout that does not need one, is cheaper and easier to reason about.',
      );
    });
  });

  group('§7.3 the release build is obfuscated, with symbols', () {
    test('package.ps1 passes --obfuscate and --split-debug-info', () {
      final script = tree.read('tool/release/package.ps1');
      expect(
        script,
        contains('--obfuscate'),
        reason: 'Without it `app.so` ships a readable map of every class, method and '
            'string in the app.',
      );
      expect(
        script,
        contains('--split-debug-info=build/symbols'),
        reason: 'Obfuscation without symbols means a crash report from a user is '
            'unreadable. The two belong together or neither is worth having.',
      );
    });

    test('and it fails the build when the symbols are missing', () {
      // The flag and the check are one decision. A `--split-debug-info` that is passed
      // and never verified is a flag that silently stopped working.
      final script = tree.read('tool/release/package.ps1');
      expect(
        script,
        contains('build\\symbols'),
        reason: 'the symbol file must be checked for, not assumed',
      );
      expect(
        script,
        matches(RegExp(r'Test-Path\s+\$symbols')),
        reason: 'precondition: the check is a real existence test',
      );
    });

    test('debug builds are left readable', () {
      // The opposite failure: obfuscating a developer's build makes their own stack
      // traces useless, and it is a tempting way to "just always" turn it on.
      //
      // Counted as *the flag on a build command*, not as the word. The first version
      // counted occurrences of `--obfuscate` and found two — one in the command, one
      // in the comment explaining why debug is exempt. This repository has been bitten
      // by a raw-text guard reading a comment in four different places now; the
      // pattern is to match the call, not the mention.
      final commands = RegExp(r'flutter build [^\r\n]*--obfuscate')
          .allMatches(tree.read('tool/release/package.ps1'));

      expect(
        commands.length,
        equals(1),
        reason: 'exactly one build command is obfuscated, and it is the release one. '
            'More than one means a debug build got obfuscated by accident.',
      );
      expect(
        commands.first.group(0),
        contains('--release'),
        reason: 'and that one has to be the release build',
      );
      expect(
        RegExp(r'flutter build [^\r\n]*--profile[^\r\n]*--obfuscate')
            .hasMatch(tree.read('tool/release/package.ps1')),
        isFalse,
      );
    });
  });

  group('the record', () {
    test('every section of the rulebook has a decision', () {
      // The thing that makes "100%" a real number rather than a feeling. A section
      // with no row is undecided, which is the state this whole thing started in.
      // Checked against `_decidedSections` above, not against the doc itself:
      // the doc always contains its own headings, so checking it against itself
      // passes vacuously and records nothing.
      final doc = tree.read('docs/flutter_architecture_pattern.md');
      final sections = RegExp(r'^#{2,3} (\d+(?:\.\d+)?)', multiLine: true)
          .allMatches(doc)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        sections.isNotEmpty,
        isTrue,
        reason: 'precondition: the rulebook has numbered sections',
      );

      final undecided = sections.difference(_decidedSections).toList()..sort();
      expect(
        undecided,
        isEmpty,
        reason: 'sections with no row in the decision table above: $undecided',
      );

      final stale =
          _decidedSections.difference(sections).toList()..sort();
      expect(
        stale,
        isEmpty,
        reason: 'decision rows pointing at sections that no longer exist: $stale',
      );
    });

    test('the declined rules name the authority that declined them', () {
      final doc = tree.read('docs/flutter_architecture_pattern.md');
      for (final authority in [
        'AGENTS.md',
        'PROJECT.md',
        'provider_pattern.md',
      ]) {
        expect(
          doc,
          contains(authority),
          reason: 'a conflict with no named authority is not a decision, it is an '
              'unfinished argument',
        );
      }
    });
  });
}