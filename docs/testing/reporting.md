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