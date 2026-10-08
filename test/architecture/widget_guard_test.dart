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

  group('a saved position is restored, and clamped on the way', () {
    // §3.22. Dart sends `widget.setGeometry` the left/top it saved on the last
    // boot, which is the only move path with no pointer-up to clamp it.
    late String source;

    setUpAll(() => source = tree.runnerSource);

    String setBoundsBody() => RegExp(r'void Window::SetBounds\(.*?\n\}', dotAll: true)
        .firstMatch(source)
        ?.group(0) ??
        '';

    test('SetBounds clamps to a reachable screen', () {
      expect(setBoundsBody(), isNotEmpty, reason: 'SetBounds should still exist');
      expect(
        setBoundsBody(),
        contains('ClampToReachableScreen'),
        reason: 'this is the restore path: the saved monitor may be gone, and an '
            'unclamped programmatic move is the one way to leave the widget '
            'where it can never be clicked again',
      );
    });

    test('the guard bites: a SetBounds without the clamp is rejected', () {
      final String faulty = source.replaceFirst(
        RegExp(r'(void Window::SetBounds\(.*?\n\})(.*?)\n\}', dotAll: true),
        r'$1$2\n}',
      );
      expect(faulty, isNot(equals(source)), reason: 'the mutation must apply');
      expect(
        RegExp(r'void Window::SetBounds\(.*?\n\}', dotAll: true)
            .firstMatch(faulty)
            ?.group(0) ??
            '',
        isNot(contains('ClampToReachableScreen')),
        reason: 'otherwise the guard is not looking at anything',
      );
    });

    test('Dart pushes the saved position rather than reading the default back', () {
      final String dart = SourceTree().read(
        'lib/features/widget/presentation/providers/widget_controller.dart',
      );

      expect(dart, contains('setWidgetGeometry'));
      // The old order was: ask where the window is, then believe it. Read the
      // bounds *and* push them and the push wins only by accident.
      final int push = dart.indexOf('setWidgetGeometry');
      final int read = dart.indexOf('widgetBounds()');
      expect(push, greaterThan(0), reason: 'the position has to be pushed');
      expect(read, greaterThan(push), reason: 'a read-back must not precede it');
    });

    test('autostart is "enabled" only when the entry names this executable', () {
      // `WN-SYS-004`. Existence was the test, and existence is not the question:
      // an entry pointing at an uninstalled build survived, so `syncPlatform`
      // agreed with the setting and repaired nothing while a login would launch
      // a path that no longer existed.
      final String platform = SourceTree().read('windows/runner/win_notes_platform.cpp');
      final RegExpMatch? enabled = RegExp(
        r'bool AutostartEnabled\(\) \{(.*?)\n\}',
        dotAll: true,
      ).firstMatch(platform);
      expect(enabled, isNotNull, reason: 'AutostartEnabled should still be there');

      final String body = enabled!.group(1) ?? '';
      expect(body, contains('AutostartCommand()'),
          reason: 'the comparison needs the command this build would write');
      expect(body, contains('== expected'),
          reason: 'presence alone is not agreement; the string has to match');
      // And it must not have been "fixed" by simply removing the registry read.
      expect(body, contains('RegQueryValueExW'),
          reason: 'precondition: it still reads the stored value');
    });

    test('the guard bites: an existence-only check is rejected', () {
      final String platform = SourceTree().read('windows/runner/win_notes_platform.cpp');
      final String faulty = platform.replaceFirst(
        RegExp(
          r'(bool AutostartEnabled\(\) \{.*?)return std::wstring\(buffer\) == expected;',
          dotAll: true,
        ),
        r'$1return r == ERROR_SUCCESS;',
      );
      expect(faulty, isNot(equals(platform)), reason: 'the mutation must apply');
      expect(
        RegExp(r'bool AutostartEnabled\(\) \{(.*?)\n\}', dotAll: true)
            .firstMatch(faulty)
            ?.group(1) ??
            '',
        isNot(contains('== expected')),
        reason: 'otherwise this guard is not looking at anything',
      );
    });

    test('the method is declared on both sides, not just the registry', () {
      // The registry is checked three ways by `platform_guard_test`; this is the
      // Dart call site, which is the fourth thing that can be missing.
      expect(
        SourceTree().read('lib/core/platform/shell_channel.dart'),
        contains("'widget.setGeometry'"),
      );
    });
  });

  group('the deferred first-frame Show does not undo a hide', () {
    // `AGENTS.md` §5.1, which was open for weeks. `Window::Create` defers the
    // boot-time `Show()` to `SetNextFrameCallback`, because showing a window
    // before the engine can paint leaves a white rectangle on the desktop. That
    // deferral is what let the bug exist: Dart can decide `visible: false` and
    // have the runner hide the window *before* that callback runs, and the
    // callback then showed it again.
    //
    // Silent by construction - the widget painted over an empty library, nothing
    // threw, and every existing check either asserted the Dart-side rule or
    // could not fail.

    late String source;
    late String header;

    setUpAll(() {
      source = SourceTree().read('windows/runner/win_notes_window.cpp');
      header = SourceTree().read('windows/runner/win_notes_window.h');
    });

    test('the boot-time Show is skipped when the window was already hidden', () {
      final RegExpMatch? boot = RegExp(
        r'SetNextFrameCallback\(\[this\]\(\) \{(.*?)\n  \}\);',
        dotAll: true,
      ).firstMatch(source);
      expect(boot, isNotNull, reason: 'the deferred Show should still be there');

      expect(
        boot!.group(1),
        contains('visible_at_start'),
        reason: 'precondition: this is the boot-time Show, not some other one',
      );
      expect(
        boot.group(1),
        contains('!hidden_before_first_frame_'),
        reason: 'a window hidden before its first frame must stay hidden. '
            'Without this the widget paints over an empty library, which is '
            'exactly what §5.1 reported',
      );
    });

    test('a real hide records that it happened', () {
      final RegExpMatch? hide =
          RegExp(r'void Window::Hide\(\) \{(.*?)\n\}', dotAll: true).firstMatch(source);
      expect(hide, isNotNull);
      expect(
        hide!.group(1),
        contains('hidden_before_first_frame_ = true'),
        reason: 'the flag has to be set by Hide() itself, or it is never set',
      );
      expect(
        hide.group(1),
        contains('SW_HIDE'),
        reason: 'precondition: it is still a hide',
      );
    });

    test('the flag is a distinct member, not reused from visible_', () {
      // `visible_` also starts false, so testing it here would say "nobody has
      // hidden this" on a window that was just hidden. That mistake was made and
      // reverted; the flag exists so it cannot be made twice.
      expect(header, contains('bool hidden_before_first_frame_ = false;'));
    });

    test('the guard bites: an unguarded boot-time Show is rejected', () {
      final String faulty = source.replaceFirst(
        RegExp(r'if \(params_\.visible_at_start && !hidden_before_first_frame_\) Show\(\);'),
        'if (params_.visible_at_start) Show();',
      );
      expect(faulty, isNot(equals(source)), reason: 'the mutation must apply');
      expect(
        RegExp(
          r'SetNextFrameCallback\(\[this\]\(\) \{(.*?)\n  \}\);',
          dotAll: true,
        )
            .firstMatch(faulty)
            ?.group(1) ??
            '',
        isNot(contains('!hidden_before_first_frame_')),
        reason: 'otherwise this guard is not looking at anything',
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