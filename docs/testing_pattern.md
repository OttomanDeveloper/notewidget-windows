# Testing Pattern — What Each Kind of Test Here Is Allowed to Claim

`test/`, `tool/screenshots/WN.Probe.cs`

This is the document that should have existed first. Two bugs shipped that this
file now explains: **the widget could not be dragged for its entire life**, and
**the first launch sometimes shows an empty widget instead of hiding it**. Both
are Win32 or lifecycle behaviour that the suite structurally cannot see.

---

## 1. Architecture Overview

```
test/
  notes_controller_test.dart     45   state, recovery, search, undo, completion
  widget_integration_test.dart   28   the widget surface against a mock shell
  settings_test.dart             25   bindings, settings, window state
  notes_repository_test.dart     24   load, ordering, AtomicJsonFile
  backup_service_test.dart       23   plain-text round trip, writing it
  note_test.dart                 17   the model, completion, id factory
  widget_surface_test.dart        9   card rendering at a given size
  palette_test.dart              65   contrast per palette, the picker, the setting
  editor_navigation_test.dart     4   dialog routing

  architecture/                         rules that are not about behaviour
    widget_guard_test.dart        9    HTCLIENT, gesture anchor, compose mode
    docs_test.dart                7    the docs must agree with this suite
    storage_guard_test.dart       7    watcher target, atomic export ordering
    layer_test.dart               6    dart:io confinement, channel parity
    guards.dart                   -    the scanners, shared by all four

tool/screenshots/
  WN.Probe.cs                    synthetic mouse + keyboard injection
  WN.Print.cs                    PrintWindow(flag 2) capture
  WN.cs                          window find and rect helpers
  capture.ps1 / compose_hero.ps1 screenshot runs
```

**449 tests: 326 about behaviour, 123 about the rules themselves, 65 about
colour.** All in `flutter test`. Nothing needs a device.

The 51 in `markdown_test` are the densest in the suite, because the renderer has
more ways to be quietly wrong than the rest of the app put together: an
unrecognised node that drops a paragraph, a leaf span that loses its inherited
style, a table whose rows are one level down, a clamp that does not clamp. Four
of those were real defects, and **three of them were found by a screenshot rather
than by a test** — emphasis that looked like asterisks, a heading that looked
twice its size, a cut that landed mid-glyph. A test can assert that a span exists
and still leave the note unreadable.

The 65 in `palette_test` are mostly generated: one group per palette, asserting
the contrast guarantee holds for it. That is deliberate — a curated palette is
only worth having if nothing in it is unreadable, and the test is what stops the
next one being added without checking.

The `architecture/` folder exists because a rule written in prose stops being
true the moment someone is in a hurry, and nothing fails. `docs/storage_pattern.md`
§4 already said a guard has to be proven non-inert; that practice is applied to
the guards themselves in §5.

---

## 2. What the suite can and cannot claim

This is the section that matters. Three tiers, and the boundary between them is
where both shipped bugs lived.

### Tier A — genuinely verified by `flutter test`

Pure Dart logic, widget rendering under a fixed size, and platform channels
against a mock handler.

- Every storage rule in `docs/storage_pattern.md` §8.
- Every card rendering rule at a given size.
- The composer contract: absent until asked for, keyboard borrowed and returned,
  write routed or not, no note from empty input, no drag while composing.
- Completion from both surfaces, both directions, including "does not reorder".
- A whitespace-only note body normalising to empty through the plain-text
  backup, while a body with text keeps its own whitespace.

These are real. A regression here is caught before it ships.

### Tier B — architecture guards, in CI

`test/architecture/` reads the source tree as text. These are not Tier B
anymore — they run in `flutter test` like everything else, and they cover the
rules whose failure is *silent*: the runner answering `HTCAPTION`, the gesture
anchor being seeded from the live cursor, `dart:io` reappearing in a widget, a
channel method the runner does not handle, a doc citing a test that was renamed.

They cannot replace Tier C, because they check that the code still *looks* like
the rule rather than that the rule still *holds*. A drag that computes the wrong
number looks exactly like a drag that computes the right one.

| Guard | Rule |
|---|---|
| `layer_test` | `dart:io` confined to `core/`+`data/`; only `platform/` builds a `MethodChannel`; every called method is handled by the runner |
| `storage_guard_test` | the watcher is on the directory and filtered; the export goes through the atomic writer; the backup is taken **before** the replace |
| `widget_guard_test` | no `HTCAPTION`; the loop cursor comes from the anchor and not `GetCursorPos`; `WS_EX_NOACTIVATE` dropped and restored; focus returned to the window it was taken from; `WM_MOUSEACTIVATE` defers to compose mode |
| `docs_test` | every rule in §3 has a table row; every cited test exists; every cited guard exists; `AGENTS.md` claims no fixed rule is still broken |

### Tier C — verified manually, with a synthetic-input probe

Everything Win32 that Dart cannot observe. This is why the 40% drag bug and the
`HTCAPTION` failure were found — **by driving the real release build**, not by
the suite.

The probe is `tool/screenshots/WN.Probe.cs`: `SetCursorPos`, `SendInput` mouse
down/up/move, `SendInput` keyboard by virtual-key code, and `PrintWindow` with
flag 2 to capture the window.

**Verified this way, and recorded in `docs/widget_pattern.md` §7:**

| Behaviour | How |
|---|---|
| 5 consecutive drags at exactly −60, 0 | probe drag, window rect before/after |
| Resize on every edge at exactly +100 | probe drag from each edge |
| 200×140 floor holding against a 900 px haul | probe drag, rect after |
| `WS_EX_NOACTIVATE` dropped while composing, restored after | `GetWindowLongPtrW(GWL_EXSTYLE)` |
| Focus returns to the window it was taken from | `GetForegroundWindow` + `GetWindowTextW` before and after |
| Typing reaches the field | `SendInput` VK codes, `PrintWindow` capture |
| 1.5 s lock opens normally | `_ExclusiveLock` with a delay, then load |
| 8 s lock reports "Something is holding your notes file" | ditto, then the screen |

**The residue is one rule:** `docs/widget_pattern.md` §3.13, the size clamp. Its
arithmetic lives in the runner and its failure mode is a widget too small to
read rather than a crash. A Dart test could only assert the absence of a bug.
Everything else in that doc is a test or a guard.

**This tier is manual and is not re-run by CI.** That is a real gap, stated
plainly rather than implied away: a regression in any of these rows would not be
caught automatically.

#### The startup path has its own unattended probe

`tool/verify/verify_release.ps1` drives a **release build** through first launch and
checks that the editor opens, that no widget appears for an empty library, that
`notes.json` is created and holds a note, then relaunches with `--widget` and checks a
small frameless window appears at the screen edge. 13 checks.

**It runs against a directory in `%TEMP%`, set through `WIN_NOTES_DATA_DIR`** — which
`AppPaths.resolve` reads in `main()`. Nothing is moved, stashed or restored, because
there is nothing to restore.

That is the second version. The first moved `%APPDATA%\WinNotes` aside, restored it in
a `finally`, and then ran `Remove-Item $profile -Recurse -Force` **one line after the
restore** — on the success path. It ran six times and deleted the notes it had just
restored, and it printed `[PASS] the previous profile is back` while doing it: a check
that the restore happened, immediately followed by a deletion of what it had restored.

Three lessons, all of which generalise past this script:

- **A passing check is not a safety property.** The restore check passed. It said the
  restore worked, and nothing about whether what came after was safe.
- **Restoring and cleaning up in the same script is a trap.** Every instinct says a
  `finally` makes it safe, and here the `finally` was correct while the line after it
  was not. Better: have nothing to restore. An override in the app is strictly safer
  than moving somebody's files to a stash and hoping.
- **A safety guard can be vacuous on the machine you are standing on.** The probe's
  "the real profile was not created" check passed with the bug still present, because
  the profile already existed — creating it again is indistinguishable from not
  creating it. That check now states only what it can prove, and the real guarantee
  comes from `isolate_guard_test` (which catches `main()` creating the reported
  directory) plus a SHA-256 comparison of the profile before and after.

`WIN_NOTES_DATA_DIR` is absolute-path-only and rejects `..`. A relative override would
resolve against the runner's working directory, and `..` walks out of whatever was
intended — either of which turns "somewhere else" into "somewhere unexpected", which
is where notes are lost.

The probe cannot send keystrokes: `SetForegroundWindow` returns false from a process
Windows does not consider foreground, so `SendKeys` goes nowhere. It checks the startup
ladder instead — which window exists, and what is on disk — which is exactly the part
`flutter test` cannot see, because a Dart test has no second isolate and no desktop.
The keystroke path is the Dart suite's job. It found the first-launch regression in
`AGENTS.md` §5.2.

### Tier D — not verified at all

- **The first-launch bug.** Reproduced 4/4 on a genuinely fresh profile with
  valid JSON: the widget paints "No notes" while visible when it should hide.
  Every candidate show/hide site has been read and ruled out. Needs an
  instrumented build. Unrooted. Narrowed on 2026-10-05: the release probe shows the
  visibility rule behaving correctly in both directions on a fresh profile, so the
  rule is not inverted and the fault is timing.
- Acrylic compositing, tray icon and menu, global hotkey registration and
  collision, the `HKCU\...\Run` autostart entry, single-instance activation,
  multi-monitor DPI and the per-monitor position restore, the native move/size
  loop's own arithmetic.

---

## 3. The traps

Every one of these cost real time. They are listed so the next person does not
pay again.

- **A test that calls the method under test is testing the method.** The clearest
  example in this repo: `notes_controller_test.dart` has a test named *"the first
  launch has a note ready to type into"*, it passed throughout, and the app's first
  launch wrote nothing to disk. It calls `ensureAtLeastOneNote()` by hand, which pins
  that method — and nothing on a real first launch calls it, because `build()` inserts
  the note itself through a different path. The rule that follows: **a test claiming to
  describe a user-visible moment must reach that moment the way the app reaches it**,
  with no setup call that the app itself does not make. `test/first_launch_test.dart`
  is the same claim written that way — read the provider, look at the filesystem.
- **A cleanup line can undo the line above it.** `verify_release.ps1` restored the
  real profile in a `finally` and then, on the success path, deleted it. Both lines
  were individually reasonable and together they destroyed a profile of real notes.
  The general form: **a `finally` makes the restore safe and says nothing about what
  runs after it**, so a script that both restores and cleans up needs the two to be
  visibly different operations rather than a `Remove-Item` either side of a check.
- **A guard can pass because the thing it checks is already true.** The probe's "the
  real profile was not created by this run" check passed with `main()` still creating
  it, because the profile already existed on the machine doing the verifying. On a
  genuinely fresh machine it would have caught the bug; there is no way to tell those
  two situations apart from inside the check. When a guard depends on a precondition,
  assert the precondition too — which is why the `provider_guard_test` scanner checks
  ask for the sample they are about to search.
- **`TestHarness.dispose()` deletes the profile directory.** So the obvious way to
  write "a second launch" — `await dispose(); build(at: dir)` — is a *first* launch:
  the folder is gone and will be recreated empty, so the new harness finds nothing,
  creates a note, and the test passes against a provider that never wrote anything.
  Use `disposeKeepingProfile()`. Two traps nested inside that one: building a second
  harness in a **new** directory (which is what this originally did) is the same
  mistake wearing a different hat, and `MainWindowHandle` skips hidden windows, so a
  window count cannot see a widget that is correctly hidden.
- **`dart:io` cannot hold an exclusive lock.** `File.openSync` uses
  `FILE_SHARE_READ | FILE_SHARE_WRITE`, so no Dart-only test can reproduce a
  scanner holding the file — which is exactly why the missing read-retry ladder
  shipped. The fix is `_ExclusiveLock` in `notes_controller_test.dart`: call
  `CreateFileW` through `dart:ffi` with a share mode of zero, allocating the
  UTF-16 path by hand with `malloc` from `DynamicLibrary.process()`.
  `package:ffi` is deliberately **not** a dependency, so `Utf16` and `calloc`
  are unavailable.
- **`SendInput` needs `type = 1` for keyboard.** The mouse paths use `0`
  (`INPUT_MOUSE`) and the two share a union, so a keyboard event tagged `0` is
  delivered as *mouse input*. It fails silently — `SendInput` still reports
  success. This one cost the most: it made the composer look broken when it was
  fine. Typing `"milk"` as real virtual-key codes worked first time, which
  located it immediately.
- **`INPUT` must be 40 bytes on x64.** That requires `MOUSEINPUT` in the union
  even if you are only sending keys. A 32-byte struct returns
  `ERROR_INVALID_PARAMETER` (87).
- **`GetAsyncKeyState(VK_LBUTTON)` does not report injected mouse buttons.** A
  guard written with it ends every synthetic drag on the first move.
- **A popup menu's barrier absorbs synthetic clicks.** A "dead button" during
  testing is often an un-dismissed menu, not a bug. Diagnose with a
  hover-tooltip probe and a hit-box grid scan before concluding.
- **`KEYEVENTF_UNICODE` arrives garbled in Flutter.** Flutter derives the
  character from the keyboard layout, so `Type("Book the MOT")` lands as
  `"b/+ 85 mot"`. Use virtual-key codes, which is what a physical keyboard does.
- **The widget window is translucent, so a screen grab lies.** `CopyFromScreen`
  on the widget's rectangle captures whatever is *behind* it — including the
  editor window, whose preview pane renders the same note at a *different
  density*. The result reads as a widget bug: a heading measured at nearly twice
  its real size, which was the editor's `headingScale: 1.9` showing through.
  Use `PrintWindow` on the widget's own HWND, which captures its Flutter
  content. Corollary: **do not conclude anything about emphasis or strikethrough
  from a small screenshot.** Weight, slant and a 1px rule all read as extra
  punctuation at card size. Zoom the crop 4× with nearest-neighbour, or assert
  on the span in a test.
- **Two probes of this one measured nothing at all, and both looked plausible.**
  `SetForegroundWindow` is silently ignored from a process that is not already
  the foreground one, so a Z-order probe that calls it and reads the result
  reports "nothing changed" no matter what the code does. And `EnumWindows`
  order is not a usable Z-order once shell and ghost windows are in the list.
  Drive activation with real synthetic clicks on a real title bar and read
  `GetForegroundWindow()`; never conclude anything from a Z-order index.
- **Never identify a WinNotes window by its size.** A previous probe left the
  widget wider than the editor and the editor minimised at `-32000`, and the
  probe cheerfully measured the widget while believing it had the editor. Match
  on title: `WinNotes` is the editor, `WinNotes Widget` is the widget. Also
  check `WindowFromPoint` before clicking — a maximised window will swallow the
  click and the probe reports a focus change that never happened.
- **`Add-Type -ReferencedAssemblies` replaces PowerShell's defaults.** It does
  not add to them, so a helper that needs `System.Drawing` or `System.Collections`
  fails to compile with errors about types that obviously exist. Keep P/Invoke
  helpers free of both (return arrays, not `List<T>`) and do the drawing in
  PowerShell, where `System.Drawing` is already loaded.
- **Never gate the ZIP on `WinNotes.exe`** — the executable is `win_notes.exe`.
- **The build fails with LNK1104 if the app is running** from
  `build\...\Release\win_notes.exe`. Stop it first.

---

## 4. Widget-test traps specific to this codebase

- **Real `dart:io` inside `testWidgets` hangs forever.** A widget test's fake
  clock never drives the real event loop. Two faces of the same thing: awaiting
  a disk read never completes, and a debounced write fires its timer but never
  finishes the write — so `flushPending()` finds nothing pending and no file
  appears, which looks exactly like the setting not being saved. Wrap setup in
  `tester.runAsync`; test debounces in a plain `test()` with real elapsed time.
- **A pending fake timer fails the test even though `tearDown` would have
  cleaned up.** The pending-timer check runs *before* `tearDown`, so a debounce
  armed by the last action has to be cancelled inside the test body
  (`AtomicJsonFile.cancelPendingWrites`).
- **A guard that can only be tested by breaking the thing it guards does not
  get tested.** `dependency_guard_test` proves its scanner bites by feeding it a
  pubspec that is not the real one. Write scanners to take text, not a
  `SourceTree`, for exactly this reason.
- **Span styles inherit, so leaf runs usually carry none.** A test that reads
  `span.style?.fontWeight` directly sees `null` for text the user can plainly
  see is bold, and then "passes" by finding nothing. Resolve inheritance while
  walking — which is also how this caught a real bug where `**bold**` inside a
  heading rendered at body size.
- **`maxLines` does not bound block count.** One `Text` with `maxLines: 2` is
  fine; twenty `Text`s each obeying it overflow by 365 pixels. Clamp rendered
  Markdown by height with an `OverflowBox`, because a `ConstrainedBox` still
  lets the `Column` report the overflow it is merely clipping.
- **The Markdown parser consumes the syntax you are looking for.** `- [ ]`
  becomes an `<input type="checkbox">` element and the brackets are gone from
  the text; the emphasis tags are `strong`/`em`/`del`, never `b`/`i`/`s`; table
  rows live inside `thead`/`tbody`, not directly under `table`. Dump the AST
  before writing an assertion about what a construct parses to.
- **`Material` with a clip shape expands to fill its constraints.** A `SizedBox`
  *inside* it does not constrain it. This made the add-note circle the full
  width of the widget. Found by a geometry probe, not by reading the code.
- **Two semantics nodes can share a label.** The composer's `Semantics` and its
  `Tooltip` both answer to "Add a note", so `find.bySemanticsLabel` is ambiguous
  about which box it means — and the ambiguity is invisible until the tap misses.
  Hence `addNoteButtonKey` / `addNoteFieldKey`.
- **A pending `Timer` fails a `testWidgets` outright.** The locked-drag hint uses
  a cancellable `Timer` rather than `Future.delayed` for exactly this reason.
- **Debounced writes need a real-clock flush.** A widget test's fake clock never
  advances the real event loop, so `controller.flush()` has to run under
  `tester.runAsync` or the pending timer fails the test on the way out. The same
  trap has a second form: **loading a file** inside `testWidgets` hangs forever
  if it is not wrapped in `runAsync`, and a debounced write under a fake clock
  fires its timer but never completes the real write — so `flush()` then finds
  nothing pending and no file appears. Both look like "the setting is not being
  saved". Test a debounce in a plain `test()` with real elapsed time instead.
- **Do not double-dispose.** `addRelease(tester, controller)` already disposes.
- **Reading state back from a file races the 250 ms debounce.** A `Get-Content`
  a moment after a change can miss it. Parse per note with
  `[System.Text.Json.JsonDocument]` — and never with a regex, which will leak one
  note's `completedAt` into the next.

---

## 5. Adding work

- **A rule in a pattern doc** → add the row to that doc's §7/§8 table, with the
  test name. `docs_test` fails if a rule has no row or if a cited test stops
  existing, so this is not optional bookkeeping.
- **A rule about how the code is *shaped*** rather than what it does → a scanner
  in `test/architecture/`. Those rules fail silently: `HTCAPTION` looks
  reasonable, `File(path).writeAsString` looks correct, a channel method with no
  handler looks fine. All three shipped.
- **Something Win32** → Tier C. Add the row to §2 with how it was verified, and
  accept that CI will not catch it.
- **A new guard** → **break the rule on purpose and watch the test go red.**
  Every guard in `architecture/` has been through that, and the list of what was
  broken to prove it is in §6. A guard that has never failed is a comment.
- **A bug fixed** → add the regression test *and* the reason it shipped, if the
  reason is not obvious. The reason is the part that stops it happening again in
  a different place.

## 6. Proof the guards are not inert

Run against a release-worthy tree, breaking one rule at a time and restoring
afterwards. All five went red; all five returned to green.

| Broken on purpose | Guard that caught it |
|---|---|
| `dart:io` reintroduced into `editor_app.dart` | `layer_test` → *no file operation appears in ui/, state/ or platform/* |
| `HitTest` made to return `HTCAPTION` | `widget_guard_test` → *the runner never answers HTCAPTION* |
| `.bak` taken **after** the rename | `storage_guard_test` → *the backup is taken before the replace, not after* |
| A `_fire` call with no runner handler | `layer_test` → *every method called from Dart is handled by the runner* |
| A cited test renamed | `docs_test` → *every test name it cites actually exists* |

The third one is the interesting entry: it was broken by accident while
extracting the atomic write into a shared helper, and the guard now exists
because of it.

The palette tests were put through the same thing, and one break is worth
recording because **the first attempt at it was wrong**:

| Broken on purpose | Test that caught it |
|---|---|
| An accent painted the same tone as the light surface | `palette_test` → *the accent reads against the light widget surface* |
| An accent painted the same tone as the dark surface | `palette_test` → *the accent reads against the dark widget surface* |
| `readableOn` put back on a 0.45 luminance threshold | `palette_test` → *the tick drawn inside the accent* |
| Two palettes given the same id | `palette_test` → *ids are unique* |
| The default palette's accent quietly changed | `palette_test` → *the default palette is still the brand* |
| The default palette renamed | `palette_test` → *the default is first* |

The first attempt darkened the default accent and the test stayed green — which
looked like an inert test and was not. Darkening an accent *raises* contrast
against a light surface; the failure mode is an accent too close to the surface,
not too dark. Painting it the same tone as the surface took it red immediately.

That is the argument for doing this at all: without breaking the rule on purpose
you cannot tell a guard that works from one that never fires — and when a break
fails to break anything, you cannot tell which of those two you are looking at.

---

## 7. Guarantees

1. Every storage and state rule in `docs/storage_pattern.md` is pinned by a named
   test, and every rule heading in §3 has a row saying which.
2. Every widget rendering and composer rule is pinned by a named test.
3. The rules that fail *silently* — `HTCLIENT`, the gesture anchor, `dart:io` in
   a widget, an unhandled channel method, `WS_EX_NOACTIVATE` never restored — are
   guards that run in CI, and each has been broken on purpose to prove it fires.
4. Win32 *arithmetic* is verified on a release build by driving it, the exact
   probe is recorded, and the one rule that remains manual is named rather than
   glossed.
5. What is *not* verified is written down rather than left to be assumed.
6. `flutter analyze` is clean and `flutter test` is green before anything is
   pushed.