/// The first launch, end to end, asking the question `PROJECT.md` asks.
///
/// `notes_controller_test.dart` has a test named 'the first launch has a note ready
/// to type into', and it passes - but it calls `ensureAtLeastOneNote()` by hand, so it
/// pins that *method*. The app never calls it: `build()` inserts the note itself,
/// through `_insert`, which does not save. So the promise in `PROJECT.md` - "the first
/// launch opens the editor with an empty note already focused, so typing is the very
/// first thing that happens" - was untested, and untrue: nothing reached disk until
/// the user typed, so a first launch closed without typing left no trace and every
/// launch minted a new note id.
///
/// These read the provider the way `main()` does and then look at the filesystem. No
/// method is called to set anything up, because a test that sets up its own
/// preconditions cannot catch a path that forgets to.
///
/// The waits are real elapsed time rather than a fake clock, because the question is
/// whether a *file* exists and the debounce has to actually elapse for that to mean
/// anything.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/provider_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() {
    // A real directory and a real clock: the question is whether a file exists on
    // disk, and only real elapsed time lets a debounce actually elapse.
    harness = TestHarness.build(isWidgetSurface: false);
  });

  tearDown(() async {
    await harness.dispose();
  });

  test('a first launch puts the ready-to-type note on disk', () async {
    final file = File(harness.notesFile);

    // Exactly what the app does: read the provider. No `ensureAtLeastOneNote()`.
    await harness.notes();

    expect(
      harness.notesState().notes,
      hasLength(1),
      reason: 'precondition: there IS a note to type into, in memory',
    );
    expect(
      harness.notesState().selectedNote,
      isNotNull,
      reason: 'precondition: and it is the one selected',
    );

    // Let the debounce window close. Nothing should be pending, which is the point.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(
      file.existsSync(),
      isTrue,
      reason: 'The note exists in memory, so a reload - or the next launch - should '
          'see it. If the file is absent it was never written, and the only thing that '
          'puts it on disk is the user typing, which is not what PROJECT.md means by '
          '"the first launch opens the editor with an empty note already focused, so '
          'typing is the very first thing that happens".',
    );
  });

  test('a second launch finds the same note, so the first launch is stable', () async {
    // The consequence of the above, as its own check: a note that lives only in memory
    // is regenerated on every launch, so a second launch is indistinguishable from a
    // first, and anything that refers to the note - the widget's selection, a hotkey -
    // loses its target.
    //
    // Same directory both times. Building a fresh harness pointed at a *new* temp
    // directory would pass whether or not the note was written, because a second
    // launch would find nothing and create a note - which is exactly the wrong answer
    // presented as the right one.
    final dir = harness.path;
    await harness.notes();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final firstId = harness.notesState().notes.first.id;

    // `disposeKeepingProfile`, not `dispose`: dispose deletes the directory, and a
    // rebuild pointed at a directory that no longer exists is a first launch.
    await harness.disposeKeepingProfile();
    harness = TestHarness.build(isWidgetSurface: false, at: dir);
    await harness.notes();

    expect(
      harness.notesState().notes,
      hasLength(1),
      reason: 'precondition: the second launch also has exactly one note',
    );
    expect(
      harness.notesState().notes.first.id,
      firstId,
      reason: 'A second launch produced a different note. That is what "never written" '
          'looks like from here: the id is regenerated every time, so the note is new '
          'every time.',
    );
  });
}