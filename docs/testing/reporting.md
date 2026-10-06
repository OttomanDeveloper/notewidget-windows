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
| **B** | most of `project_realworld_testing.md` | Probe against a release build | seconds |
| **C** | 8 rows | By hand on a desktop | minutes |

**Class A is the whole game.** A single `flutter test` run closes dozens of rows
at once. **No row goes to a probe while a host test could close it** — a probe
run is the last resort, not the default.

## Results

<!-- Add one section per batch, newest at the bottom. -->

### Verdict vocabulary

`PASS` / `FAIL` / `PARTIAL` / `BLOCKED` / `TIMEOUT` / `N/A`, each optionally with
a parenthesised qualifier naming the evidence that closed the row.

`RE-TEST` means the row was previously run to a verdict, but the scenario's
**required states or expected behaviour changed after that run**, so the old
verdict no longer describes the scenario as it now stands. It is a re-run
request, not a failure. The `Fix / note` cell of every `RE-TEST` row is
**retained from the original run** and still holds the evidence that closed it —
the verdict alone was overwritten.

### No rows yet

The catalog has 27 rows. None has been run *through this ledger*, because the
ledger did not exist until now.

What has been run, and what it proves:

| What | Verdict | When | What it does not prove |
|---|---|---|---|
| `verify.ps1` gate, all 7 stages | PASS (test) | 2026-10-06 | Anything in waves 1–6 |
| `verify_release.ps1`, 13 checks | PASS (test) | 2026-10-06 | Drag, focus, compositing — it cannot send a keystroke |
| `verify_icons.ps1`, 13 checks | PASS (test) | 2026-10-06 | Nothing about behaviour |
| Widget `§7` table: 8 rows marked **manual** | **unverifiable** | undated | Whether they ran on the current runner |

The last line is the reason this file exists. `docs/widget_pattern.md` §7 records
that five drags at exactly `−60,0` were verified, that a 900 px haul was hauled,
that `WS_EX_NOACTIVATE` was read before and after. It does not record **when**,
and nothing in the repository can tell. A claim that cannot be dated is
indistinguishable from a claim that has been falsified.

### First batch to run

`WN-ENV-001` through `WN-ENV-005`, then wave 2. Reasons, in order:

1. They are the cheapest, and `WN-ENV-003` — the real profile is untouched — is
   the one whose failure would be worst.
2. Wave 2 is the only place a **number** is being claimed. A drag that computes
   the wrong amount looks exactly like a drag that computes the right one, and
   every guard in the repository can only assert the absence of that bug.
3. `WN-DRAG-001` has a known reference: five consecutive drags at `−60,0`.
   A result that is not `−60,0` is a bug the suite provably cannot find.

## Machine record

Filled in at the start of a probe batch, because a result without it is not
reproducible.

| Item | Value |
|---|---|
| Machine | _(fill in)_ |
| Windows build | _(fill in)_ |
| GPU / driver | _(fill in)_ |
| Monitors and scale | _(fill in)_ |
| Commit under test | _(fill in)_ |
| Release flags | `--obfuscate --split-debug-info=build/symbols` |

Only the machine name goes in a scenario row. Driver versions and display
topology go here, once per batch, so a row is not 200 characters wide.

## Risks this ledger carries

1. **A green gate reads as a working app.** It is not one. 27 rows are open and
   a green gate is consistent with every one of them.
2. **The probe rows are only as good as the person driving them.** `WN-DRAG-002`
   passes if the window stops *somewhere*. The expected number has to be
   written down in the `Fix / note` cell, or the row is a comment.
3. **Window identification is the silent failure.** Rules 6 and 7 of the
   execution rules exist because a probe once measured the widget while
   believing it had the editor, and printed a number that was internally
   consistent and entirely wrong.
4. **The 8 undated manual rows in `docs/widget_pattern.md` are not evidence.**
   They should be re-run and recorded here, or marked `RE-TEST`. Until then they
   are claims.