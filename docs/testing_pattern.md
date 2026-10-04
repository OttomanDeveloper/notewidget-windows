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
  widget_integration_test.dart   26   the widget surface against a mock shell
  settings_test.dart             25   bindings, settings, window state
  notes_repository_test.dart     21   load, ordering, AtomicJsonFile
  note_test.dart                 17   the model, completion, id factory
  backup_service_test.dart       17   plain-text round trip
  widget_surface_test.dart        9   card rendering at a given size
  editor_navigation_test.dart     4   dialog routing

tool/screenshots/
  WN.Probe.cs                    synthetic mouse + keyboard injection
  WN.Print.cs                    PrintWindow(flag 2) capture
  WN.cs                          window find and rect helpers
  capture.ps1 / compose_hero.ps1 screenshot runs
```

**164 tests. All in `flutter test`. Nothing needs a device.**

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

### Tier B — verified manually, with a synthetic-input probe

Everything Win32 that Dart cannot observe. This is why the 40% drag bug and the
`HTCAPTION` failure were found — **by driving the real release build**, not by
the suite.

The probe is `tool/screenshots/WN.Probe.cs`: `SetCursorPos`, `SendInput` mouse
down/up/move, `SendInput` keyboard by virtual-key code, and `PrintWindow` with
flag 2 to capture the window.

**Verified this way, and recorded in `docs/widget_pattern.md` §3:**

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

**This tier is manual and is not re-run by CI.** That is a real gap, stated
plainly rather than implied away: a regression in any of these rows would not be
caught automatically.

### Tier C — not verified at all

- **The first-launch bug.** Reproduced 4/4 on a genuinely fresh profile with
  valid JSON: the widget paints "No notes" while visible when it should hide.
  Every candidate show/hide site has been read and ruled out. Needs an
  instrumented build. Unrooted.
- Acrylic compositing, tray icon and menu, global hotkey registration and
  collision, the `HKCU\...\Run` autostart entry, single-instance activation,
  multi-monitor DPI and the per-monitor position restore, the native move/size
  loop itself.

---

## 3. The traps

Every one of these cost real time. They are listed so the next person does not
pay again.

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
- **Never gate the ZIP on `WinNotes.exe`** — the executable is `win_notes.exe`.
- **The build fails with LNK1104 if the app is running** from
  `build\...\Release\win_notes.exe`. Stop it first.

---

## 4. Widget-test traps specific to this codebase

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
  `tester.runAsync` or the pending timer fails the test on the way out.
- **Do not double-dispose.** `addRelease(tester, controller)` already disposes.
- **Reading state back from a file races the 250 ms debounce.** A `Get-Content`
  a moment after a change can miss it. Parse per note with
  `[System.Text.Json.JsonDocument]` — and never with a regex, which will leak one
  note's `completedAt` into the next.

---

## 5. Adding work

- **A rule in a pattern doc** → add the row to that doc's §7 table, with the
  test name. A rule with no test name is a comment, not a rule.
- **Something Win32** → it goes in Tier B. Add the row to §2 with how it was
  verified, and accept that CI will not catch it.
- **Something needing a device or a real profile** → Tier C. Say so.
- **A bug fixed** → add the regression test *and* the reason it shipped, if the
  reason is not obvious. The reason is the part that stops it happening again in
  a different place.

---

## 6. Guarantees

1. Every storage and state rule in `docs/storage_pattern.md` is pinned by a named
   test.
2. Every widget rendering and composer rule is pinned by a named test.
3. Win32 behaviour is verified on a release build by driving it, and the exact
   probe is recorded.
4. What is *not* verified is written down rather than left to be assumed.
5. `flutter analyze` is clean and `flutter test` is green before anything is
   pushed.