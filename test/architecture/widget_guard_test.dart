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
  final SourceTree tree = SourceTree();

  group('the editor has a minimum size', () {
    late String windowSource;

    setUpAll(() {
      windowSource = SourceTree().read('windows/runner/win_notes_window.cpp');
    });

    List<String> faultsFor([String? source]) =>
        findEditorMinSizeFaults(source ?? windowSource);

    test('the floor is enforced', () {
      expect(
        faultsFor(),
        isEmpty,
        reason: 'docs/widget_pattern.md §3.18.\n${faultsFor().join('\n')}',
      );
    });

    test('the floor is a named constant, scaled for DPI', () {
      // Asserted directly rather than only through the scanner, so the numbers
      // themselves are pinned: a floor of 520x360 is a design decision, and a
      // scanner cannot tell whether someone changed it to 200.
      expect(windowSource, contains('constexpr int kMinEditorWidth = 520;'));
      expect(windowSource, contains('constexpr int kMinEditorHeight = 360;'));
      expect(
        windowSource,
        contains('ScaleForWindow(window, kMinEditorWidth)'),
        reason: 'unscaled, the floor is wrong on every display that is not at '
            '100%',
      );
      expect(windowSource, contains('ScaleForWindow(window, kMinEditorHeight)'));
    });

    test('the guard bites: no WM_GETMINMAXINFO at all is rejected', () {
      expect(
        faultsFor(windowSource.replaceAll('case WM_GETMINMAXINFO: {', 'case WM_NCPAINT: {'))
            .any((String f) => f.contains('no WM_GETMINMAXINFO')),
        isTrue,
      );
    });

    test('the guard bites: ptMinSize instead of ptMinTrackSize is rejected',
        () {
      final String faulty = windowSource.replaceAll('ptMinTrackSize', 'ptMinSize');
      expect(
        faultsFor(faulty).any((String f) => f.contains('ptMinTrackSize')),
        isTrue,
        reason: 'ptMinSize also caps programmatic sizing, so Dart asking for '
            'a size would be silently ignored.',
      );
    });

    test('the guard bites: an unscaled floor is rejected', () {
      final String faulty = windowSource.replaceAll(
        'ScaleForWindow(window, kMinEditorWidth)',
        'kMinEditorWidth',
      ).replaceAll('ScaleForWindow(window, kMinEditorHeight)', 'kMinEditorHeight');
      expect(faulty, isNot(equals(windowSource)));
      expect(
        faultsFor(faulty).any((String f) => f.contains('unscaled')),
        isTrue,
        reason: 'a literal here is 520 physical pixels, which is 347 logical '
            'pixels at 150% scaling.',
      );
    });

    test('the guard bites: claiming ptMaxPosition is rejected', () {
      final String faulty = windowSource.replaceAll(
        '      info->ptMinTrackSize.x = ScaleForWindow(window, kMinEditorWidth);',
        '      info->ptMaxPosition.x = 0;\n'
            '      info->ptMinTrackSize.x = ScaleForWindow(window, kMinEditorWidth);',
      );
      expect(faulty, isNot(equals(windowSource)));
      expect(
        faultsFor(faulty).any((String f) => f.contains('ptMaxPosition')),
        isTrue,
        reason: 'that field governs dragging off-screen, which '
            'ClampToReachableScreen already owns.',
      );
    });
  });

  group('the widget gets out of the editor way', () {
    // The real runner, read once, and then mutated one fault at a time.
    late String windowSource;
    late String hostSource;

    setUpAll(() {
      final SourceTree tree = SourceTree();
      windowSource = tree.read('windows/runner/win_notes_window.cpp');
      hostSource = tree.read('windows/runner/win_notes_host.cpp');
    });

    List<String> faultsFor({String? window, String? host}) =>
        findWidgetAboveEditorFaults(window ?? windowSource, host ?? hostSource);

    test('nothing puts the widget above the editor', () {
      final List<String> faults = faultsFor();

      expect(
        faults,
        isEmpty,
        reason: 'docs/widget_pattern.md §3.17.\n'
            'A topmost window is above *every* window, so once the widget is '
            'topmost there is no Z-order position that means "above other apps '
            'but below the editor" - it simply covers the editor. That is the '
            'complaint this rule exists for, and the reason it is a rule rather '
            'than a preference.\n\n'
            '${faults.join('\n')}',
      );
    });

    test('the scanner finds the code it is looking for in the first place', () {
      // A guard that passes because its regexes match nothing is the failure
      // mode that reads most like enforcement. Every construct it depends on
      // is asserted present, so "no faults" means "checked" rather than
      // "silent".
      expect(windowSource, contains('case WM_ACTIVATE'));
      expect(windowSource, contains('void Window::StyleForRole'));
      expect(windowSource, contains('void Window::SetAlwaysOnTop'));
      expect(hostSource, contains('void Host::ApplyWidgetTopmost'));
      expect(hostSource, contains('editor_->Raise()'));
      expect(hostSource, contains('OnWindowActivationChanged'));
    });

    test('the guard bites: an editor with WS_EX_TOPMOST is rejected', () {
      final String faulty = windowSource.replaceAll(
        '    *ex_style = 0;',
        '    *ex_style = WS_EX_TOPMOST;',
      );
      expect(faulty, isNot(equals(windowSource)),
          reason: 'the fixture did not apply; the guard proved nothing');

      final List<String> faults = faultsFor(window: faulty);
      expect(
        faults.any((String f) => f.contains('gives the editor WS_EX_TOPMOST')),
        isTrue,
        reason: faults.join('\n'),
      );
    });

    test('the guard bites: demoting without raising the editor is rejected',
        () {
      // The half that is easy to leave out. Everything else about the yield can
      // be right and the widget still ends up above the editor.
      final String faulty = hostSource.replaceAll('    editor_->Raise();', '');

      final List<String> faults = faultsFor(host: faulty);
      expect(
        faults.any((String f) => f.contains('does not raise the editor')),
        isTrue,
        reason: 'the missing Raise must be named specifically, not lumped in '
            'with the other checks: it is the one that was measured rather '
            'than assumed.\n\n${faults.join('\n')}',
      );
    });

    test('the guard bites: an un-guarded SetAlwaysOnTop is rejected', () {
      final String faulty = windowSource.replaceAll(
        'if (window_ == nullptr || !IsWidgetRole(params_.role)) return;',
        'if (window_ == nullptr) return;',
      );
      expect(faulty, isNot(equals(windowSource)));

      final List<String> faults = faultsFor(window: faulty);
      expect(
        faults.any((String f) => f.contains('IsWidgetRole')),
        isTrue,
        reason: 'without the role check the always-on-top setting reaches the '
            'editor through the back door.\n\n${faults.join('\n')}',
      );
    });

    test('the guard bites: no WM_ACTIVATE is rejected', () {
      final String faulty = windowSource.replaceAll('case WM_ACTIVATE: {', 'case WM_NCPAINT: {');
      expect(faulty, isNot(equals(windowSource)));
      expect(
        faultsFor(window: faulty).any((String f) => f.contains('WM_ACTIVATE')),
        isTrue,
      );
    });

    test('the guard bites: a host with no activation handler is rejected', () {
      final String faulty = hostSource.replaceAll(
        'void Host::OnWindowActivationChanged(SurfaceRole role, bool active) {',
        'void Host::SomeOtherHandler(SurfaceRole role, bool active) {',
      );
      expect(faulty, isNot(equals(hostSource)),
          reason: 'the fixture did not apply; the guard proved nothing');

      expect(
        faultsFor(host: faulty)
            .any((String f) => f.contains('does not define Host::OnWindowActivationChanged')),
        isTrue,
        reason: 'matching the bare name would have been satisfied by the '
            'mention in a comment, so a renamed handler would have gone '
            'unnoticed.',
      );
    });
  });

  group('the widget is HTCLIENT everywhere', () {
    test('the runner never answers HTCAPTION', () {
      final List<String> hits = findCaptionHits(tree);

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
      const String dirty = '''
        LRESULT HitTest(POINT p) const {
          if (inCorner(p)) return HTTOPLEFT;
          return HTCAPTION;
        }
      ''';

      final int found = RegExp(r'HTCAPTION').allMatches(dirty).length;
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
      final String source = tree.runnerSource;
      final int inComments = source
          .split('\n')
          .where((String l) => l.trimLeft().startsWith('//'))
          .where((String l) => l.contains('HTCAPTION'))
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
      final String? move = RegExp(r'case kWmBeginMove:\s*\{(.*?)\n    \}', dotAll: true)
          .firstMatch(source)?.group(1);
      final String? resize = RegExp(r'case kWmBeginResize:\s*\{(.*?)\n    \}', dotAll: true)
          .firstMatch(source)?.group(1);

      expect(move, isNotNull, reason: 'the move loop should still exist');
      expect(resize, isNotNull, reason: 'and so should the resize loop');
      expect(move, contains('SeedLoopAnchor()'));
      expect(resize, contains('SeedLoopAnchor()'),
          reason: 'a resize that skipped the anchor would jump the same way');
    });

    test('the loop cursor comes from the anchor, not from the live cursor', () {
      final String body = _seedLoopBody(source);
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
      final String source = tree.runnerSource;

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
      final String source = tree.runnerSource;

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
      final String source = tree.runnerSource;
      final String? block = RegExp(
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