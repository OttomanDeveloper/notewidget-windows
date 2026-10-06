# WinNotes Test-Verification Program

> New here? Start with [`README.md`](README.md) — it lists every check in the
> repository, how to run it, and which one answers which kind of question.

## Document purpose

This file is the ordered source of truth for verifying WinNotes, and for keeping
test evidence honestly distinguishable from evidence gathered against real
Windows.

It contains:

1. Every scenario the repository has not fully proven, with the states it needs.
2. The behaviour `PROJECT.md` and the pattern docs require.
3. **Which methods can verify it, and in what order.**
4. The actual result once run, in [`reporting.md`](reporting.md).

`PROJECT.md` wins if this file conflicts with it. `AGENTS.md` controls repository
and agent rules. This file must never contain real note bodies, real profile
paths, or anything read out of a person's `%APPDATA%\WinNotes`.

## Relationship to the pattern docs

`docs/testing_pattern.md` §2 already classifies what the suite can and cannot
claim, in four tiers. This file does not replace it and does not re-scope it.
What it adds is the thing a tier cannot: **a row per scenario, with an ID, the
states it needs, and the evidence that would close it.**

The tiers answer "what kind of claim is this?". This file answers "which claim,
what would prove it, and has it run?".

## Why this exists

The tier prose was written honestly and is still honest — but it cannot be
checked. `docs/widget_pattern.md` §7 lists eight behaviours as **manual** and
records how each was verified, with no date, no verdict, and no statement of
what the evidence was. Six weeks later there is no way to tell whether a row
was run on the current runner or on one from before the gesture-anchor change,
and no way to tell a re-verified row from one that was never re-run.

That is the failure this file exists to prevent: **a claim that cannot be dated
is indistinguishable from a claim that has been falsified.**

It is also the difference between "verified by probe" and "the probe exists".

## What this program does not establish

Stated first, because the failure mode of a test-heavy program is believing its
own green suite.

- **It does not show the app behaves correctly on a real desktop.** Widget tests
  run against a fake clock and a mock shell. None of that is Windows.
- **It does not measure frames or responsiveness.** "No jank" is a claim about a
  real compositor.
- **It does not exercise compositing.** Acrylic, the tray icon, and per-monitor
  DPI are facts about `DWM` and the display topology, not about Dart.
- **It does not survive process death.** A test has no process to kill. The
  flush-on-teardown hazard in `docs/isolate_pattern.md` §4.3 is exactly this.
- **It cannot find the bugs nobody thought to write a row for.** The
  first-launch widget bug (`AGENTS.md` §5.1) was found by opening the app, not
  by an assertion. A suite is a floor, never a ceiling.

A green gate and a working app are different claims. This program is honest
about which one it is making.

## Verification classes

| Class | Closed by | Stays open until |
|---|---|---|
| **A** — test-verifiable | one passing test or guard | the test passes |
| **B** — test, then Windows | test **and** probe | both land |
| **C** — Windows-only | never, here | a probe or a person in `reporting.md` |

**Class A.** The expected behaviour is fully assertable without Windows:
validation, ordering, budgets, contrast, empty and error states, boundary
conditions, the atomic-write ladder, the debounce ceiling. A passing test
closes the row.

**Class B.** The logic is assertable, but real Windows must confirm the platform
integration: hit-testing, geometry arithmetic, focus, the keyboard borrow, a
real message loop. Test first, probe second. **The row does not close on the
test alone.**

**Class C.** Irreducibly Windows: acrylic compositing, the tray, the global
hotkey and its collisions, the `HKCU\…\Run` autostart entry, single-instance
activation, multi-monitor DPI and per-monitor position restore. **This program
does not close these.** They are listed so the ledger accounts for every known
open item honestly rather than quietly dropping the hard ones.

## Evidence rules

1. A row's `Result` records **how** it was verified, never just that it passed.
   The permitted values are `PASS (test)`, `PASS (probe)`, `PASS (test+probe)`,
   `FAIL`, `FAIL-FIXED`, `BLOCKED`, `NOT RUN`, `RE-TEST`. **A bare `PASS` is not
   a value.**
2. Class A rows close on `PASS (test)`. Class B rows need `PASS (test+probe)`.
   Class C rows never receive a result from this program.
3. **Assertions are derived from the row's Expected behaviour, never from
   observed output.** This is the rule that matters most, and the one most
   easily broken by good intentions.
4. Where a test and the expected behaviour disagree, that is a `FAIL` against
   the app, not a test to be adjusted. A genuine ambiguity in the row is recorded
   in `reporting.md` as an open question with both readings, never resolved by
   editing the assertion to match the code.
5. One root cause per fix. No batching unrelated changes behind a single result.
6. Every fix ships with a test that fails without it. **A fix with no regression
   test is not finished.**
7. `pwsh -File tool\verify\verify.ps1` green before any commit.

Rule 3 exists because a test written against current behaviour certifies current
behaviour. The renderer is where that bites: a heading measured at half its
intended size looks like a styling choice, and a test written to match it turns
that bug into a passing assertion with a CI badge attached. The whole value of
this program rests on not doing that.

## Test harness

- `test/` — host-side. Widget tests, controller tests, and repository tests
  against real temp directories and a real clock. Fast, deterministic, no
  Windows.
- `test/architecture/` — 147 scanners that read the source as text. They check
  that the code still *looks like* the rule, not that the rule still *holds*.
- `tool/verify/verify.ps1` — the gate. Analyze, the suite, a release build, and
  two scripts that drive it.
- `tool/screenshots/WN.Probe.cs` — synthetic mouse and keyboard into a real
  HWND. The instrument for everything Class B and C.

## Execution rules

1. Work one class-A block at a time. Do not interleave probe work with test work;
   the two have different failure vocabularies.
2. **10-minute limit per row.** On timeout, mark `BLOCKED`, record what was
   tried, move on.
3. On `FAIL`, reproduce once, fix one root cause, add the regression test, then
   continue.
4. Never mark a row `PASS` on a test that does not run in the full suite.
   **A test nobody runs is a comment.**
5. Class B rows get their probe run in one batched session, not one session per
   row.
6. Class C rows are not attempted by a test. They are Windows work and are
   reported as such.
7. Results go to `reporting.md`, under a heading that names the class.
8. **No real note bodies in this file or in any log.** A verification run reads
   `%TEMP%`, never `%APPDATA%`.

## Reporting

[`reporting.md`](reporting.md) is the single ledger. Each block states its class
in the heading, so test evidence and Windows evidence are never interleaved
without a label.

For a class-A block, a row is reported when its test is committed and the gate
is green. For a class-B block, when both the test and the probe run have landed.