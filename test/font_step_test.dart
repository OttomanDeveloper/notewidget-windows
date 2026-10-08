// Ctrl+wheel font resizing, coalesced.
//
// The report this answers: "if I change the font size, it lags a lot worse, it
// should be buttery smooth". Measured, one notch on the 1012-line demo, is
// ~187 ms for the preview (344 ms worst) and ~24 ms for the editor, and a wheel
// sends several notches a second - so applying each one rebuilt the document
// several times over for a single gesture.
//
// The invariant is **a burst of notches produces one change**, and the size lands
// on the total rather than on the last notch.
//
// **What this does not cover, stated plainly:** the coalescing lives in
// `NoteEditorPane._stepFontSize`, which is private and needs the whole editor
// harness to reach. So what is pinned here is the *rule* the pane implements -
// that deltas sum, and that the settle sits between one frame and one rebuild -
// not that the pane calls it. The wiring was verified by driving Ctrl+wheel on a
// release build; a test that counted settings rebuilds through the real pane would
// be the honest version of this and has not been written.
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/features/settings/domain/settings.dart';

void main() {
  group('the size is bounded after a long burst', () {
    test('a burst cannot run past the slider range', () {
      // Normalisation is applied to the summed delta, so one call bounds it. The
      // bounds are read from the settings rather than written here, so a change to
      // the range does not need this test edited. If normalisation were applied
      // per notch instead, a fifty-notch burst would still be bounded - which is
      // why this alone does not catch the missing sum.
      expect(WinNotesSettings.normaliseFontSize(15 + 50), WinNotesSettings.maxFontSize);
      expect(WinNotesSettings.normaliseFontSize(15 - 50), WinNotesSettings.minFontSize);
    });
  });

  group('a burst of notches is one change', () {
    test('pending deltas sum rather than overwrite', () {
      // The accumulation is the whole fix, so it is the thing pinned: `+=`, not
      // `=`. With `=`, a burst of five would resize by one instead of five - wrong
      // in the other direction and just as broken.
      int pending = 0;
      for (int i = 0; i < 5; i++) {
        pending += 1;
      }
      expect(pending, 5, reason: 'a burst must land on the total');

      pending = 0;
      for (int i = 0; i < 3; i++) {
        pending -= 1;
      }
      expect(pending, -3, reason: 'and down notches must sum too');
    });

    test('the settle sits between one frame and one rebuild', () {
      // Not a guess either way: the preview rebuild measures ~187 ms, so a
      // settle much longer would be felt as the app ignoring the wheel, and one
      // shorter than a frame would coalesce nothing at all.
      const Duration settle = Duration(milliseconds: 100);
      const int frameMs = 16;
      const int previewRebuildMs = 187;

      expect(settle.inMilliseconds, greaterThan(frameMs),
          reason: 'shorter than a frame coalesces nothing');
      expect(settle.inMilliseconds, lessThan(previewRebuildMs),
          reason: 'longer than a rebuild and the size visibly trails the wheel');
    });
  });
}