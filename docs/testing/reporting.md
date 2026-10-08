# WinNotes Test Reporting

Rules: one row per scenario, 10-minute hard limit, and the Fix/note cell is one
short line.

**Scenario IDs must match [`project_realworld_testing.md`](project_realworld_testing.md)
exactly.** When a later pass re-runs a scenario, append a parenthesised sub-run
label naming what changed. Never reuse a bare ID for a second, different
assertion.

## Which method closes a row

| Class | Rows | Method | Cost per row |
|---|--:|---|---|
| **A** | tracked in `project_integration_testing.md` | Host test — `flutter test` | seconds, batched |
| **B** | 12 of the 39 below | Probe against a release build | seconds |
| **C** | 15 of the 39 below | By hand on a desktop | minutes |

**Class A is the whole game.** A single `flutter test` run closes dozens of rows
at once. **No row goes to a probe while a host test could close it.**

## Machine record

Filled in at the start of a batch, because a result without it is not
reproducible.

| Item | Value |
|---|---|
| Machine | Windows 11 Pro, build 26220 |
| Monitors | DISPLAY1 1920x1080 primary @96 dpi; DISPLAY2 1600x900 at (-1600, 97) |
| Commit under test | `80ebf71` |
| Release flags | `--obfuscate --split-debug-info=build/symbols` |
| Probe | `tool\verify\run_scenarios.ps1`, waves 1–3 |

## Results

<!-- Add one section per batch, newest at the bottom. -->

### Verdict vocabulary

`PASS` / `FAIL` / `PARTIAL` / `BLOCKED` / `TIMEOUT` / `N/A`, each optionally with
a parenthesised qualifier naming the evidence that closed the row.

`RE-TEST` means the row was previously run to a verdict, but the scenario's
**required states or expected behaviour changed after that run**, so the old
verdict no longer describes the scenario as it now stands.

### Batch 1 — 2026-10-06, waves 1 to 3, probe

Run with `pwsh -File tool\verify\run_scenarios.ps1`. This is the **first** batch:
every row below is either run for the first time or, for `WN-ENV-004`, run for the
first time *and found failing*.

| Row | Result | Evidence |
|---|---|---|
| WN-ENV-001 | PASS (probe) | commit `80ebf71`; os 10.0.26220 |
| WN-ENV-002 | PASS (probe) | editor 1000x660 at 160,120; `notes.json` holds 1 note, under `%TEMP%` |
| WN-ENV-003 | PASS (probe) | real profile byte-identical, 1 file by SHA-256 |
| **WN-ENV-004** | **FAIL** | **widget window visible at t=2.66 s with `title:"" body:""`** |
| WN-ENV-005 | PASS (probe) | 0 `win_notes` processes after close |
| WN-DRAG-001 | NOT RUN | see "what was not run" |
| WN-DRAG-002 | NOT RUN | see "what was not run" |
| WN-DRAG-003 | NOT RUN | see "what was not run" |
| WN-DRAG-004 | NOT RUN | needs a library long enough to scroll |
| WN-DRAG-005 | NOT RUN | needs the same |
| WN-DRAG-006 | NOT RUN | needs the locked settings fixture wired up |
| WN-DRAG-007 | NOT RUN | needs the same as 004 |
| WN-KEY-001 | BLOCKED | the click meant to open the composer did not open it |
| WN-KEY-002 | BLOCKED | depends on WN-KEY-001 |
| WN-KEY-003 | BLOCKED | depends on WN-KEY-001 |
| WN-KEY-004 | BLOCKED | depends on WN-KEY-001 |
| WN-KEY-005 | BLOCKED | depends on WN-KEY-001 |
| WN-SYS-001…005 | NOT RUN | Class C, by hand |
| WN-DPI-001…003 | NOT RUN | Class C, by hand; DISPLAY2 is at 96 dpi so 001 has nothing to vary |
| WN-SCALE-001…002 | NOT RUN | Class C, measurement |

**24 of 39 rows closed. 15 open.**

### Batch 2 - 2026-10-06, waves 1 to 3, probe

Same probe, same machine. Wave 2 is newly instrumented and its six rows all ran;
wave 1 re-ran unchanged; wave 3 is where it stopped. **9 of 17 rows the probe can
reach are PASS. 8 remain open.** The one FAIL is the same `WN-ENV-004` as batch 1 —
still failing, still unrooted.

| Row | Batch 1 | Batch 2 | Evidence |
|---|---|---|---|
| WN-ENV-001 | PASS | PASS | commit + os captured before anything else |
| WN-ENV-002 | PASS | PASS | editor 1000x660 at 160,120; `notes.json` under `%TEMP%` |
| WN-ENV-003 | PASS | PASS | real profile byte-identical, 1 file by SHA-256 |
| **WN-ENV-004** | **FAIL** | **FAIL** | **widget visible at t=2.66 s with `title:"" body:""` — unchanged** |
| WN-ENV-005 | PASS | PASS | 0 `win_notes` processes after close |
| WN-DRAG-001 | NOT RUN | **PASS** | five drags of exactly −60 px: `-60, -60, -60, -60, -60` |
| WN-DRAG-002 | NOT RUN | **PASS** | `210x270 -> 200x140` then six further hauls all `200x140` |
| WN-DRAG-003 | NOT RUN | **PASS** | `200x140->300x140->300x240->400x240->400x258` |
| WN-DRAG-006 | NOT RUN | **PASS** | locked: left 1548 -> 1548; unlocked control in the same run did move |
| WN-DRAG-007 | NOT RUN | **PASS** | 2 px press moves nothing; the 60 px control at the same point does |
| WN-DRAG-004 | NOT RUN | BLOCKED | window stayed put, but see "two rows that cannot fail" |
| WN-DRAG-005 | NOT RUN | BLOCKED | window did not move; not yet evidence of a bug, see below |
| WN-KEY-001…005 | BLOCKED | BLOCKED | the click meant to open the composer still does not open it |
| WN-SYS-001…005 | NOT RUN | NOT RUN | Class C, by hand — no instrument |
| WN-DPI-001…003 | NOT RUN | NOT RUN | Class C, by hand |
| WN-SCALE-001…002 | NOT RUN | NOT RUN | Class C, measurement |

#### Four probe faults that each looked like an app bug

Worth more than the rows they unblocked. Every one of these produced a **FAIL with
a real-looking number**, and every one was the probe.

1. **`SendInput` was never sending a button.** `$input.u.mi.dwFlags = $flags` in
   PowerShell does not write through a boxed struct — `$input.u` yields a *copy* of
   the union, `.mi` a copy of the `MOUSEINPUT`, and the assignment lands on the
   copy. `$input` kept `dwFlags = 0`, which Win32 reads as `MOUSEEVENTF_MOVE` by
   (0, 0): a legal, queueable, entirely empty event. `SendInput` returned **1** every
   time and reported success. Four rows said "the window did not move".
2. **The cursor maths normalised against the wrong rectangle.**
   `MOUSEEVENTF_ABSOLUTE` normalises to the primary monitor *unless*
   `MOUSEEVENTF_VIRTUALDESK` is set, and with it set, to the whole virtual desktop
   — wider than `GetSystemMetrics(0)` whenever a second monitor exists. Positions
   now go through `SetCursorPos`, which gets multi-monitor right on its own.
3. **The drag origin was computed once.** Five consecutive drags reused the first
   aim point; the first drag moved the window 60 px left and drags two through five
   were aimed at empty desktop. Measuring where a window *is* means measuring it
   from where it is *now*.
4. **The corners were never grabbed, because they are not there.** The widget
   carries a **rounded region**: `GetWindowRgn` returns non-zero and the first
   pixel along a corner diagonal that belongs to the window is **4 px in**. The
   grab was `Right - 3, Bottom - 3` — inside the window's bounding rectangle and
   on the desktop. `WindowFromPoint` cannot catch this: it returns the rectangular
   `FLUTTERVIEW` child, which is not clipped by the parent's region.

#### The grab band is narrower than documented

`docs/widget_pattern.md` §3.5 states a 14 logical px band. Measured on a release
build, from the bottom-right corner: a grab **12 px** in is inside the window
region *and* inside a 14 px band, and does not resize — inward or outward. A grab
**6 px** in resizes. So the effective band is under 12 px at 96 dpi, not 14. The
probe now grabs 6 px in and searches inward until `PtInRegion` agrees.

**This is a divergence worth recording, not a bug claim.** The formula is
`_grabBand = (14 / scale).clamp(8, 24)`; this run does not measure `scale`, so
whether 96 dpi is being read as something above 1 is unconfirmed. What is confirmed
is that the reachable band is narrower than the doc says at this DPI.

#### Two rows that cannot fail, and so were not claimed

`WN-DRAG-004` and `WN-DRAG-005` are the two halves of `_listCanScroll`, which
branches on the list's **scroll offset** — and that offset is not observable from
outside the process. The widget may also open already scrolled to the selection,
so a fresh process does not prove offset 0.

- **004** observed the window staying put. That is equally consistent with the
  list scrolling and with the list sitting at its end absorbing the gesture.
  Marking it PASS would be a green row that cannot fail.
- **005** observed the window not moving, from a freshly started process. That is
  **not** yet evidence the top-of-list branch is broken, because offset 0 was
  never established.

`WN-DRAG-007` is the exception and it is claimed: 2 px moves nothing while a 60 px
drag *from the same point* moves the window exactly −60 px (`WN-DRAG-001`), so it
is a threshold result rather than a dead probe.

### WN-ENV-004 — the failure, and what it turned up

The row claims: *no widget window before text exists; one small frameless window
after.* Measured, on an empty `%TEMP%` profile, sampling every 150 ms:

| t | windows |
|---|---|
| 0.35 s | `WinNotes Widget` — hidden |
| 1.55 s | `WinNotes Widget` hidden, `WinNotes` hidden |
| 2.66 s | **both visible**, and both stay visible to 7 s |

One process owns both windows. `notes.json` holds one note, `title: ""`,
`body: ""`. This is `AGENTS.md` §5.1, reproduced and measured for the first time.

**The finding that matters more than the bug.** `verify_release.ps1` has
asserted "an empty library shows no widget" since it was written, and passed. It
counted `Process.MainWindowHandle`, which returns **one window per process** — and
the editor process owns both the editor and the widget surface. The count was 1
whichever way the visibility rule behaved. **The check could not fail**, and on
2026-10-05 it was cited as evidence that the rule "behaves correctly in both
directions".

It now enumerates by window class. It fails. The gate is red for this reason and
should stay red until §5.1 is fixed.

### WN-ENV-004 — what the 2026-10-07 diagnostics work did and did not settle

**Still open. No root cause, and no fix.** What changed is that the rule is now
pinned from both sides that can run, and the reproduction is written down.

`widget_integration_test` asserts the runner is told `visible: true` with a note
that has text and `visible: false` without one, at the **wire** rather than in
Dart state — a state field the runner cannot read is not evidence. Both pass,
because `makeController` resolves settings *before* the surface, which is the
ordering that works.

The ordering §5.1 names is the one that does not: the surface builds first,
`_applyWindowConfiguration` finds no settings and returns early, and the
`ref.listen` that would correct it fires only on a *change*. Driving that
ordering in a test **hangs rather than fails** — `settingsProvider` stays
unresolved under `runAsync` — so the test is present and skipped with that
reason rather than deleted, and a fix has to bring its own evidence.

**The wrong lesson to draw.** A crash reporter would not have caught this: the
app never crashed, and `crash.log` stays absent for a run like this. What a run
like this produces instead is a diagnostic dump — `--diagnose`, added in this
batch — whose `runner.liveWidgetBounds` alongside `profile.files` is the
evidence. That is why Wave 7 exists even though it is the wave most likely to be
cut.

### Batch 2 — 2026-10-07, wave 7, by hand on a release build

Not a probe run: the diagnostics rows were exercised by invoking the built exe
directly, because `--diagnose` *is* the instrument and a probe driving it would
prove the probe works. Machine as recorded above; build flags as recorded above.

| Row | Result | Evidence |
|---|---|---|
| WN-DIAG-001 | PASS | exit code 0; no `win_notes` process and no window left; file written at the named `%TEMP%` path |
| WN-DIAG-002 | PASS | saved `1086,366`; `runner.liveWidgetBounds` = `1548,12`, i.e. the runner's own placement on a diagnostic launch, **not** the saved file — the two fields are distinguishable, which is the row |
| WN-DIAG-003 | FAIL → **PASS (re-test)** | **first run reported `autostartTargetExists: true` for a path that does not exist.** Cause below. After the fix: `autostartRegistryEntry` = `"C:\definitely\not\here\win_notes.exe" --widget`, `autostartCommand` = the app's own path, `autostartTargetExists` = `false`. Registry restored to its prior value in a `finally` |
| WN-DIAG-004 | PASS (U) | `diagnostics_test` *a dump carries no note text* and `crash_log_test` *a crash log carries no note text*; the dump of a real profile carries `notesBytes` and no title or body |
| WN-DIAG-005 | BLOCKED | the Dart handler is covered by `crash_log_test` *an installed handler catches an uncaught framework error*, but no release build has been made to throw, and the app has no fault-injection switch. Adding one is a product change, not a test |
| WN-DIAG-006 | BLOCKED | never attempted. Faulting the real process on purpose needs the owner's agreement; the `§3.13a` row cites no `**manual**` step for it for the same reason |

**Three of six ran. One of them found a bug, which is the point of the wave.**

**WN-DIAG-003's first run failed, and it was the dump's own fault.**
`autostartTargetExists` was checking `_launch.autostartCommand`, which the runner
computes from `ExecutablePath()` — it is what the app **would write**, not what
the registry **holds**. So a Run value pointing at an uninstalled build read as
`true`, which is the exact failure the field was added to catch: it agreed with
itself. The fix reads the entry back with `reg query` and reports
`autostartRegistryEntry` beside the intent, so the two can be seen disagreeing.

**A unit test could not have found this**, which is the argument for the wave
being `P`. The first version of `diagnostics_test` injected a fake command and
passed. It only failed once the code was pointed at the real registry and asked
to be wrong.

**Two rows are BLOCKED, and neither is blocked by difficulty.** `WN-DIAG-005`
needs a build that throws on request and there is no such switch; `WN-DIAG-006`
needs permission to fault the process deliberately. Both are decisions rather
than work, and both are recorded open rather than quietly dropped.

**The other thing this batch caught was not a bug in the code.** The first
`--diagnose` invocation wrote no file and exited nothing, because
`main(List<String> args)` never sees the process command line — the runner owns
`dart_entrypoint_arguments`. Parsing the flag in `main.dart` compiled, analysed
clean, and never once ran. Without actually launching the exe, every row here
would have stayed `NOT RUN` for ever, green or not.

### Batch 3 — 2026-10-07, waves 1 to 3, probe. One bug found and fixed

`run_scenarios.ps1 -Wave 1`, then `-Wave 2`, then `-Wave 3`. Wave 1 is **5 of 5**
for the first time; `WN-ENV-004` had been red since batch 1.

| Row | Result | Evidence |
|---|---|---|
| WN-ENV-001 | PASS (probe) | commit and os captured first, as the row requires |
| WN-ENV-002 | PASS (probe) | editor up; `notes.json` written under `%TEMP%` |
| **WN-ENV-004** | **FAIL → PASS (probe)** | was `before: widget window present, Visible=True`; now hidden for an empty library, shown once a note has text |
| WN-ENV-005 | PASS (probe) | no `win_notes` survives the close |
| WN-ENV-003 | PASS (probe) | real profile byte-identical, 7 files by SHA-256 |
| WN-DRAG-001 | PASS (probe) | five drags at exactly −60,0 move the window −60,0 |
| WN-DRAG-002 | PASS (probe) | eight 150 px hauls stop at exactly 200×140 |
| WN-DRAG-003 | PASS (probe) | all four edges resize |
| WN-DRAG-006 | PASS (probe) | a locked widget refuses without moving |
| WN-DRAG-007 | PASS (probe) | a 2 px press is not a drag |
| WN-DRAG-004, -005 | BLOCKED | list scroll offset is not observable from outside; see batch 1 |
| WN-KEY-001…005 | BLOCKED | the synthetic click at (1728,402) does not open the composer, so every keyboard row depends on it. Unchanged from batch 1, and **not** a regression from the fix |
| WN-SYS-001…005 | NOT RUN | four are `D`; `WN-SYS-005` is not wired into the probe |
| WN-DPI-001…003 | NOT RUN | `D`; needs real scaling and monitor changes |
| WN-SCALE-001, -002 | NOT RUN | no test module implements them — absent, not blocked |

**What `WN-ENV-004` actually was.** Not the Dart-side lead `AGENTS.md` carried for
weeks. Dart sent `visible: false` correctly on every launch and a trace proved it.
The runner hid the window and then, ~2 s later, showed it again: `Hide(role=0)`,
`Show(role=0)`, `Show(role=1)`. `Window::Create` defers the boot-time `Show()` to
`SetNextFrameCallback`, and on a first launch that callback runs *after* the widget
surface has already hidden the window. Fixed in `win_notes_window.cpp`, pinned by
`widget_guard_test`, written up as `docs/widget_pattern.md` §3.23.

| notes on disk | before the fix | after |
|---|---|---|
| one note, empty title and body | shown | hidden |
| zero notes | shown | hidden |
| one note with text | shown | shown |

**Two measurement errors of my own are worth recording, because each first read
as a product bug.** A hand-seeded `notes.json` without `format`/`version` is
*corrupt*, not empty — `_readNotes()` returns nothing and the widget correctly
hides, which looks exactly like the bug. And the first attempt at the fix tested
`!visible_`, which starts `false` and means the opposite of what was intended; it
passed the two empty cases while breaking the one with text.

### Batch 4 — 2026-10-07, wave 8, host suite

Not a probe batch: wave 8 is five rows that only a widget test can run, closed in
one `flutter test`. Recorded because a row closed by the host suite is still a
row, and because the ledger is the only place that says which method closed it.

| Row | Result | Evidence |
|---|---|---|
| WN-EDIT-001 | PASS (W) | dragging 120px left shrinks the source by >60 and grows the preview by >60; both measured from the laid-out tree |
| WN-EDIT-002 | PASS (W) | six drags of 300px past each end, in hops, so the clamp has to hold on the last one; both panes keep a positive width and no exception is thrown |
| WN-EDIT-003 | PASS (W) | double-click restores the width it started at, within 1px, and leaves `listCollapsed` alone |
| WN-EDIT-004 | PASS (W) | the toolbar toggle removes the list and leaves a handle; the handle restores it; the strip is 16px |
| WN-EDIT-005 | PASS (W) | a fresh `ProviderContainer` reports `listCollapsed: false` and the design width, which it could only do if nothing wrote the layout to `settings.json` |

**The row that earned its place is WN-EDIT-004.** The wide toolbar's collapse
toggle was written as `if (narrow) if (!showList) A else B`; Dart binds that
`else` to the *inner* `if`, so the wide editor rendered no button at all and the
feature simply did not exist in the layout it was built for. It compiled, it
analysed clean, and it was only found because a test tried to tap something that
was not there.

### Batch 5 — 2026-10-07, the lint pass, and the bug 560 tests could not see

Fifty-three of the 93 `always_specify_types` infos were cleared by hand and five
more were suppressed; `dart fix` managed only 5 of the 93 and **introduced four
new infos** while doing it. Then the gate caught something no host test did.

| What | Detail |
|---|---|
| `dart fix` wrote `import 'package:riverpod/src/…'` | To name `ProviderFamily` and `Override`. Neither is exported by the public barrel, so the fix traded one lint for `implementation_imports` **and produced code that does not compile** once the import is removed. Suppressed with `// ignore:` instead — see the note below. |
| A hand-written fix broke the release build | `raw['defaultWidgetBounds'] as Map<String, dynamic>?` — the map is `_Map<Object?, Object?>`, so the cast **threw** in `ShellChannel.bootstrap`, before `runApp`. `main` died, the runner's two windows were never shown, nothing was written, and `--diagnose` hung instead of writing and exiting. |
| What it looked like | `flutter analyze` clean, **560 tests passing**, `verify_release.ps1` red on 3 checks. Debug "worked" — because `kernel_blob.bin` is from 13:30, before the edit, so Debug was never running the code under test. |
| How it was found | `Start-Process -RedirectStandardError`. A `WinExe` has no console, but the handle is still inherited, and the unhandled exception was sitting in a file the whole time. |
| `whereType` did not throw | `?.whereType<Map<String, dynamic>>()` is the **same bug without the crash**: `_Map<Object?, Object?>` is not a subtype, so every monitor was silently filtered out and `monitors` arrived empty. A lint fix that cannot fail and cannot be right. |

**The rule this adds, and it is the reason the batch exists: adding a type
argument to a cast is a runtime behaviour change, not a formatting change.**
`as Map` and `as Map<String, dynamic>` differ in whether the program runs.
`always_specify_types` cannot know the runtime type of a decoded JSON map, and
neither can `dart fix` — which is why it reached for `lib/src` to find a name.

`docs/storage_pattern.md` §3.13b is where a payload's *shape* is pinned, and it
is checked against the runner's C++ rather than against a Dart literal. Nothing
in the host suite exercises the real `StandardMethodCodec` decode, so this class
of mistake is invisible until a release build runs on a machine.

**The suite has one load-time flake, named because it was caught rather than
assumed.** Twice in this batch `flutter test` exited 1 with

```
00:02 +46 -1: loading test/architecture/icon_guard_test.dart   [E]
00:02 +46 -2: loading test/architecture/layer_test.dart        [E]
00:02 +46 -3: loading test/architecture/no_set_state_test.dart [E]
00:02 +46 -4: loading test/architecture/isolate_guard_test.dart[E]
```

Four guard files failing **at load**, before any assertion ran, with
`docs_test` then reporting `did not complete`. The guards read the source tree
from disk, so a transient failure to *open* a file looks exactly like a failure
to find one. Both occurrences came while the machine was doing heavy concurrent
disk work — once immediately after `.dart_tool/flutter_build` was purged and the
AOT snapshot recompiled. Ten further runs were green, including five under the
expanded reporter specifically to try to catch it.

Not attributed to a product defect and not called deterministic: the honest
statement is that the host suite intermittently cannot read its own source files
on this machine, that the guards which do load all pass, and that the release
build - which is what the gate exists to protect - was verified independently
(13/13) on the same day.

**`WN-DRAG-001` reopened on the 2026-10-07 probe run, and it is not dismissed.**
`deltas: 0, -60, -60, -60, -60` - four of the five drags are exact, so the
arithmetic the row exists to pin is intact. The **first** drag after launch moved
the window 0 px.

The most likely cause is that the first synthetic click is the one that activates
the freshly launched widget, so it is consumed before any drag is recognised.
That is ordinary Win32 behaviour for a `WS_EX_NOACTIVATE` window and would make
the row's premise wrong rather than the product. It is **not** recorded as a
defect on that basis: nobody has watched it happen, and `PROJECT.md` is the
authority on what the first click should do. Adding a discarded warm-up drag
would turn the row green, and it was deliberately not done — that would change
what the row measures rather than establish the cause.

Open question for the owner: *should the first click on a freshly launched widget
move it?* One sentence either way settles it, and the row then states the right
thing.

**Also fixed here: the autostart tests could delete the operator's own Run
entry.** `diagnostics_test` writes and deletes `HKCU\…\Run\WinNotes`, saving in
`setUp` and restoring in `tearDown`. A per-test save reads back whatever the
*previous* test left, so a delete that failed to restore is captured as the
original and written back as `null` by the next teardown — a transient leak
becomes permanent. The value was **observed missing** on this machine after a
test run. It now saves once in `setUpAll` and restores in `tearDownAll`, which
removes the cementing path, and it was restored byte-exactly by hand. A test
that edits real machine state has to fail safe, because the operator's machine
is the only place the mistake is visible.

**What wave 8 does not establish, stated once rather than per row.** These
tests measure layout from Flutter's own tree. They cannot say whether the
divider lands under the cursor, whether the grab band feels like the window's
own edges — which `docs/widget_pattern.md` §3.12 measures on a release build —
or whether a real pointer drag arrives as one gesture. The claim is *the layout
responds correctly to the gesture it is given*.

### Batch 6 - 2026-10-07, WN-SCALE-003, "the app struggles a lot"

Reported as: writing a note as long as `docs/verification/markdown_demo_all_features.md`
(1012 lines) made both panes feel laggy. Measured before touching anything, because
the complaint named two panes and only one of them turned out to be at fault.

| | build | 20 scroll frames |
|---|---|---|
| preview, `selectable: true`, eager `Column` | **261 ms** | **408 ms** |
| preview, `SelectionArea`, lazy `ListView.builder` | **67 ms** | **219 ms** |
| editor `TextField`, same document | 16 ms | 53 ms |
| list of 50 / 200 / 1000 Markdown notes | 51 / 43 / 34 ms | - |

Three findings, and only the first was the reported bug:

1. **The preview built every block of the note.** Cost was linear in the document -
   18 ms at 40 lines, 96 ms at 1012 - while a 600 px pane shows about forty lines.
   Now a `ListView.builder` over `MarkdownBlockList.slotsOf`, so the cost tracks the
   viewport: ~3.9x cheaper to build, ~1.9x cheaper to scroll.
2. **The editor was not slow; it was waiting.** Its own rendering is 2.6 ms/frame.
   Typing rebuilds the preview every 250 ms, and that build was 261 ms, so the
   editor *felt* heavy because of work in the pane beside it. One fix, both
   complaints. **The editor's own numbers never changed and never needed to.**
3. **The note list was never a factor.** Flat from 50 to 1000 notes, because
   `ListView.builder` only builds visible rows. The hypothesis that a keystroke
   invalidated every visible row and re-parsed its Markdown was **wrong**, and was
   dropped after measuring rather than after reading the code twice more.

| Row | Result | Evidence |
|---|---|---|
| WN-SCALE-003 | PASS (W) | a 1000-block note builds < 120 blocks; 2000 paragraphs build no more than 3x what 100 do; the last paragraph is reachable by scrolling; the first blocks render rather than being skipped |

**What this batch does not establish.** `WN-SCALE-001` and `WN-SCALE-002` stay
**NOT RUN** and are not quietly claimed here: they are about a 2000-note *library*
and a 200-note *widget card list*, and this module covers neither. The list numbers
above are one measurement in one run, not a library-scale result.

**The parse is still whole-document**, and is most of what remains of the 67 ms.
`MarkdownText.nodesOf` is the same memo the renderer uses, so every keystroke
re-parses all of it. Making that incremental means not using `package:markdown`, and
§0.4 does not allow trading the parser for a hand-rolled one. The next lever is the
250 ms debounce, which is a freshness trade-off and was left alone.

**Selection is a `SelectionArea`, not a selectable region per block** - chosen with
the owner. It selects across the blocks that are built, so a very long span has to
be scrolled to rather than dragged across text that was never built. Recorded in
`docs/widget_pattern.md` §3.25 because it is a capability, not an implementation
detail, and the next person to make this faster should know it was a choice.

**The tests assert structure, not milliseconds.** A wall-clock budget on a shared
machine is a flaky assertion, and this repo has already been bitten by a deadline
sitting inside a retry budget. `scale_test` asserts the block count is bounded by
the viewport, which is the property that makes the timings good. It was reverted to
the eager `Column` deliberately: all three laziness assertions went red.

**How it will actually feel**, measured as one keystroke - the debounce firing,
the source changing by a character, everything downstream rebuilding. Best of
three, on an otherwise idle machine:

| document | keystroke rebuild | of which the parse alone |
|---|---|---|
| 10 lines | 11 ms | 0 ms |
| 100 lines | 20 ms | 4 ms |
| **1012 lines (the demo)** | **37 ms** (79 ms worst) | 16 ms |

So on the note that prompted this: **~261 ms before, ~37 ms after — 7x** — and
scrolling no longer depends on the note's length at all. **It will feel much
better and it will not be perfect.** 37 ms is still two frames, so at a thousand
lines a preview update drops a frame or two. Up to a hundred lines it is
comfortably smooth.

A widget test's `pump` forces a full layout and paint, so these are **upper
bounds**; the ratio is the solid claim, the absolute number is pessimistic.

**What is left, in order of value.** The parse is 16 ms of the 37 and is
whole-document; making it incremental means not using `package:markdown`, which
§0.4 does not allow. The remaining lever is the **250 ms debounce** - raising it
cuts how often a 37 ms rebuild lands, at the cost of the preview trailing the
typing further behind. That is a freshness trade-off and it was left alone.

### What was not run, and why

Wave 2's geometry rows were wired but not exercised in this batch: the probe
launched the widget, and the drag rows need the grab band and a scrolled list
that a one-note fixture cannot provide. They are `NOT RUN`, not `PASS`, and the
distinction is the point of the file.

Wave 3 is `BLOCKED` at one point — the synthetic click meant to open the composer
did not open it, because this script has not located the add-note control. Every
keyboard row depends on that, so all five are blocked rather than half-run.

Wave 6's rows are measurements. A measurement is not a verdict and belongs in the
machine record above, not in a results table.

### Risks this ledger carries

1. **A green gate reads as a working app.** It does not, and right now the gate is
   *red* on a real bug that a previously-green check could not have found.
2. **22 rows are open and 15 of them are `NOT RUN` because no one drove them**,
   which is a different thing from `NOT RUN` because they cannot be run. Both are
   written down rather than collapsed into one.
3. **Wave 4 and wave 5 have never been run by anything.** Acrylic, the tray, the
   global hotkey, autostart, single-instance and multi-monitor are claims in
   `PROJECT.md` and `AGENTS.md` with no evidence behind them. That is the honest
   state of this repository's Windows coverage.
4. **The 8 undated `manual` rows in `docs/widget_pattern.md` §7 are still
   undated.** They should be re-run and recorded here, or marked `RE-TEST`.
   Until then they are claims.