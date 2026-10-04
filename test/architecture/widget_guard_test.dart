/// `docs/widget_pattern.md` §3.1 and §3.7, as tests.
///
/// The rules here cannot be reached by a Dart test at all: they are about what
/// the runner answers to `WM_NCHITTEST` and what it does with
/// `WS_EX_NOACTIVATE`. `docs/testing_pattern.md` §2 records that tier as verified
/// by driving a release build, which means it is not in CI. This file is the
/// part that can be, and it covers the failure mode that was silent and total.
library;

import 'package:flutter_test/flutter_test.dart';

import 'guards.dart';

/// Body of `Window::SeedLoopAnchor`, or an empty string if it has gone.
///
/// Empty rather than nullable on purpose: every caller asserts on its contents,
/// and a `String?` here would push a null check into four assertions instead of
/// one place.
String _seedLoopBody(String source) =>
    RegExp(r'void Window::SeedLoopAnchor\(\)\s*\{(.*?)\n\}', dotAll: true)
        .firstMatch(source)
        ?.group(1) ??
    '';

void main() {
  final tree = SourceTree();

  group('the widget is HTCLIENT everywhere', () {
    test('the runner never answers HTCAPTION', () {
      final hits = findCaptionHits(tree);

      expect(
        hits,
        isEmpty,
        reason: 'Reporting HTCAPTION over the widget body is the bug that '
            'stopped the widget being draggable for its entire life, twice '
            'over: the Flutter view covers the client area so the system never '
            'consults the frame, and DefWindowProc will not start the move loop '
            'without WS_CAPTION or WS_THICKFRAME. It also breaks card taps, '
            'because Windows hit-tests exactly one target per pixel.\n\n'
            '${hits.join('\n')}',
      );
    });

    test('the scan is not passing because it finds nothing to look for', () {
      // Prove the scanner works by running it over source that does contain the
      // thing. Without this, deleting the regex would turn this file green.
      const dirty = '''
        LRESULT HitTest(POINT p) const {
          if (inCorner(p)) return HTTOPLEFT;
          return HTCAPTION;
        }
      ''';

      final found = RegExp(r'HTCAPTION').allMatches(dirty).length;
      expect(found, 1, reason: 'the scanner must see HTCAPTION in real code');
      expect(
        RegExp(r'return\s+HTTOPLEFT\b').hasMatch(dirty),
        isTrue,
        reason: 'and the edge variants, which would fight the Dart gesture',
      );
    });

    test('the explanatory comments that mention HTCAPTION do not trip it', () {
      // HitTest's own comment block names HTCAPTION four times, on purpose, to
      // explain why it must never be used. A guard that flagged those would be
      // deleted within a day, which is worse than no guard.
      final source = tree.runnerSource;
      final inComments = source
          .split('\n')
          .where((l) => l.trimLeft().startsWith('//'))
          .where((l) => l.contains('HTCAPTION'))
          .length;

      expect(
        inComments,
        greaterThan(0),
        reason: 'If this ever hits zero the prose was deleted and the reason '
            'the rule exists is gone with it.',
      );
      expect(findCaptionHits(tree), isEmpty,
          reason: 'and yet the code itself must still be clean');
    });
  });

  group('the gesture anchor travels with the hand-off', () {
    // §3.3. The runner is told a drag started only *after* the pointer has
    // already travelled past the threshold, so seeding the native loop's start
    // cursor from GetCursorPos at that moment throws away everything moved in
    // the first hop - the window jumps backwards by the threshold distance
    // before it starts following. The anchor Dart captured at pointer-down has
    // to be what the loop starts from.
    late String source;

    setUpAll(() => source = tree.runnerSource);

    test('both move and resize seed the loop from the pending anchor', () {
      final move = RegExp(r'case kWmBeginMove:\s*\{(.*?)\n    \}', dotAll: true)
          .firstMatch(source)?.group(1);
      final resize = RegExp(r'case kWmBeginResize:\s*\{(.*?)\n    \}', dotAll: true)
          .firstMatch(source)?.group(1);

      expect(move, isNotNull, reason: 'the move loop should still exist');
      expect(resize, isNotNull, reason: 'and so should the resize loop');
      expect(move, contains('SeedLoopAnchor()'));
      expect(resize, contains('SeedLoopAnchor()'),
          reason: 'a resize that skipped the anchor would jump the same way');
    });

    test('the loop cursor comes from the anchor, not from the live cursor', () {
      final body = _seedLoopBody(source);
      expect(body, contains('pending_anchor_x_'));
      expect(body, contains('pending_anchor_y_'));
      expect(
        body.contains('GetCursorPos'),
        isFalse,
        reason: 'reading the cursor here is exactly the bug: by now it has '
            'already moved, so the first hop is discarded',
      );
      // And the anchor is scaled, because Flutter reports view-relative logical
      // pixels and the loop works in physical ones.
      expect(body, contains('scale'));
    });

    test('the anchor is consumed, so a stale one cannot be reused', () {
      expect(
        _seedLoopBody(source),
        contains('pending_anchor_valid_ = false'),
        reason: 'otherwise a second gesture would start from the first one\'s '
            'anchor',
      );
    });
  });

  group('compose mode returns the keyboard', () {
    test('the runner restores WS_EX_NOACTIVATE when compose mode ends', () {
      final source = tree.runnerSource;

      // Both halves must be present. A runner that dropped the flag and never
      // put it back would leave the widget holding the caret for the rest of
      // the session, with no field visible to type into.
      expect(
        source.contains(r'~static_cast<LONG_PTR>(WS_EX_NOACTIVATE)'),
        isTrue,
        reason: 'compose mode must drop WS_EX_NOACTIVATE, or typing cannot work',
      );
      expect(
        source.contains(r'ex |= static_cast<LONG_PTR>(WS_EX_NOACTIVATE)'),
        isTrue,
        reason: 'and put it back, or the widget keeps the keyboard for good',
      );
    });

    test('focus goes back to the window it was taken from', () {
      final source = tree.runnerSource;

      expect(
        source.contains('compose_previous_focus_'),
        isTrue,
        reason: 'the previous foreground window has to be remembered',
      );
      expect(
        RegExp(r'SetForegroundWindow\(previous\)').hasMatch(source),
        isTrue,
        reason: 'and handed back - restoring to "whatever is foreground now" '
            'would undo an alt-tab the user made while typing',
      );
      expect(
        RegExp(r'GetForegroundWindow\(\)\s*==\s*window_').hasMatch(source),
        isTrue,
        reason: 'but only if the widget still has focus. Yanking someone back '
            'from a window they chose is worse than leaving them there.',
      );
    });

    test('WM_MOUSEACTIVATE defers to compose mode', () {
      final source = tree.runnerSource;
      final block = RegExp(
        r'case WM_MOUSEACTIVATE:\s*\{(.*?)\n    \}',
        dotAll: true,
      ).firstMatch(source)?.group(1);

      expect(block, isNotNull, reason: 'the handler should still exist');
      expect(
        block!.contains('compose_mode_'),
        isTrue,
        reason: 'MA_NOACTIVATE is belt-and-braces with the ex-style and blocks '
            'activation at exactly the moment the widget should be a text '
            'field. Same bug, one layer down, and much harder to see.',
      );
    });
  });
}