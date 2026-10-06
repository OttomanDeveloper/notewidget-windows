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
| **B** | 12 of the 27 below | Probe against a release build | seconds |
| **C** | 15 of the 27 below | By hand on a desktop | minutes |

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

**5 of 27 rows closed. 22 open.** One of the five is a failure.

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