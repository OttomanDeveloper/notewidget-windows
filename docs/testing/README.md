# Testing WinNotes

Orientation for a person or an agent landing here. What exists, how to run it,
and which check answers which question.

## The four files in this folder

| File | What it is |
|---|---|
| **`project_realworld_testing.md`** | The Windows program: **27 scenarios** in 6 dependency-ordered waves, each tagged with the methods that can verify it. All `NOT RUN`. The authority for what must be proven against real Windows. |
| **`project_integration_testing.md`** | The evidence rules, and the A/B/C classification that says what a test is allowed to claim. The authority for honesty. |
| **`feature_test_matrix.md`** | Which test modules a *kind of feature* needs, and how many. The rule that survives the catalog being renumbered. |
| **`reporting.md`** | The results ledger. One row per scenario, machine recorded once per batch. |

**Read the two programs before writing a test.** They already classify every open
scenario, so you do not have to work out from scratch whether your idea needs a
real window.

**Adding a feature?** Skip both catalogs and read
[`feature_test_matrix.md`](feature_test_matrix.md). Short version: a feature needs
a second test type exactly when it crosses a boundary — Dart↔file, Dart↔runner,
Dart↔Win32, Dart↔code, or code↔user. Most features cross none, and need one
module.

## Run the gate

```powershell
pwsh -File tool\verify\verify.ps1
```

Seven stages in dependency order, about two minutes. This is the gate, and it is
also what CI runs.

| Stage | Does | Needs |
|---|---|---|
| `Caps` | `check_architecture.ps1` — size caps and widget privacy | nothing, under a second |
| `Analyze` | `flutter analyze` | nothing |
| `Test` | the suite, and the 147 architecture guards inside it | nothing |
| `Random` | the suite in randomised order — hunts order-dependent flakes | nothing |
| `Random` (what it has found) | a 6-second wait sitting inside a 5.75-second retry budget, in `notes_repository_test.dart` | — |
| `Build` | the release binary. **The only stage that compiles C++** | nothing |
| `Release` | drives that binary through a first launch against `%TEMP%` | `Build` |
| `Icons` | reads the icon out of the built exe and installer | `Build` |

The order is the dependency order, and it matters: `Caps` runs first because it
needs no Dart VM and fails fastest on the mistake you are about to make 400
times in an editor; `Release` and `Icons` run last because they consume
`Build`'s output.

Run one stage, or skip one:

```powershell
pwsh -File tool\verify\verify.ps1 -Action Test
pwsh -File tool\verify\verify.ps1 -Action All -Skip Release
```

`-Action Random` is worth running before a push, and it has earned its place.
This suite has real-clock behaviour in it — a 250 ms debounce, a directory
watcher, temp directories — and a test that only passes because something else ran
first is exactly what a shuffle finds.

It found one on the day it was written: `notes_repository_test.dart` waited six
seconds for a file, while a write that cannot land legitimately retries for about
5.75 seconds. The deadline sat *inside* the budget, so under contention the test
failed while the app was still behaving correctly. Twenty serial runs never showed
it; randomised ordering showed it within a dozen.

It is also the stage most likely to print `Connection closed before test suite
loaded` — a lost tester connection that fails every suite still loading, at
roughly one run in eight on a busy machine. That is the runner, not the app; see
the traps in `docs/testing_pattern.md` §3.

## The tools

| Tool | Lives in | Runs on | Speed | Use it for |
|---|---|---|---|---|
| **Unit / widget** | `test/` (26 files) | host | seconds | Business rules, ordering, budgets, contrast, copy, empty/error states |
| **Architecture scanners** | `test/architecture/` (13) | host | instant | Rules that must not drift: no `setState`, no injected controllers, one widget per file named after itself, the channel contract, the file caps |
| **Release drive** | `tool/verify/verify_release.ps1` | release build | ~12s | The startup path: first launch, no widget when empty, a note on disk, no orphan, real profile untouched |
| **Icon audit** | `tool/verify/verify_icons.ps1` | built artifacts | ~33s | The icon in all four places Windows reads it from |
| **Probe** | `tool/verify/run_scenarios.ps1` | release build | seconds | Hit-testing, drag geometry, focus, the keyboard borrow — everything a Dart test cannot assert |
| **Manual** | `project_realworld_testing.md` | desktop | minutes | Acrylic, tray, global hotkey, autostart, multi-monitor |

Run a subset:

```powershell
flutter test test/notes_controller_test.dart
flutter test test/architecture/
pwsh -File tool\verify\verify.ps1 -Action Random
pwsh -File tool\verify\run_scenarios.ps1 -Wave 2
```

`run_scenarios.ps1` drives the Windows catalog and writes its verdicts to
`%TEMP%\wn_scenarios.json`. It exits non-zero while any row is open, because
"some rows are open" is the normal state and a zero exit would say otherwise.

## Which tool for which question

| You want to check | Class | Tool |
|---|---|---|
| A validation rule, a budget, or a boundary | A | unit test |
| Sort order, search filtering, the undo window | A | controller test |
| "the accent is readable on the dark surface" | A | `palette_test` |
| The atomic write, the backup ladder, the debounce ceiling | A | repository test against real temp dirs |
| A rule about code *shape* | A | a guard, proved red against a planted file |
| Drag arithmetic, resize geometry | B | **probe, then a hand-run** |
| The keyboard borrow, `WS_EX_NOACTIVATE`, focus return | B | **probe, then a hand-run** |
| Acrylic, tray, the global hotkey, autostart | C | **by hand** |
| Per-monitor DPI, position restore | C | **by hand** |
| Frame time under a 2,000-note library | C | measurement, not a verdict |

**The boundary is not "how important is it" — it is "can Dart see it".** A drag
that computes the wrong number looks exactly like a drag that computes the right
one, and a guard can only assert the absence of a bug. That asymmetry is why
wave 2 of the Windows program exists and why its rows stay open.

## Reading the Windows program

`project_realworld_testing.md` is ordered by **dependency**, not alphabetically.
You cannot test the widget while composing if the widget does not appear at all,
and multi-monitor runs last because it is only meaningful once everything else has
finished.

| Wave | Name | Rows | Gate before it |
|---:|---|--:|---|
| 0 | Host gate | — | nothing; runs on every commit |
| 1 | Windows and first run | 5 | a release build |
| 2 | Hit-testing and geometry | 7 | wave 1 |
| 3 | Keyboard and focus | 5 | wave 2 |
| 4 | Compositing, tray, and the shell | 5 | wave 1 |
| 5 | Multi-monitor and DPI | 3 | waves 2–4 |
| 6 | Scale and responsiveness | 2 | a seeded library |

Every row carries a **Method** column listing the methods that can verify it,
cheapest first: `U` unit, `W` widget, `G` guard, `P` probe, `D` by hand, `M`
measurement. Most rows need more than one, and a pass at one level is not a pass
at the others. The column says what *can* verify a row — never what *has*.
Results live only in `reporting.md`.

To find one scenario: `rg 'WN-DRAG-002' docs/`.

## Shared harness

`test/helpers/` holds the pieces that were duplicated across the suite:
`provider_harness.dart` (boots a real `ProviderContainer`) and `file_io.dart`
(the Windows file dance). Use them rather than re-deriving the setup.

`file_io.dart` in particular is not optional. `waitForContent` exists because
three tests each grew their own version of "wait for the debounced write", and
two of them were wrong in ways that cost a full-suite flake rate of one in five.
See the traps in `docs/testing_pattern.md` §3.

## Writing a new test

1. Find the scenario's ID and class in `project_integration_testing.md`.
2. Class A → add to the matching `test/` file, ideally next to a related test.
   Class B → add the test, then keep the probe row open. Class C → it belongs in
   `project_realworld_testing.md`; **do not pretend a test covers it.**
3. Use `test/helpers/`.
4. Run `verify.ps1 Test` before pushing, and `Random` if you touched anything
   with a clock or a temp directory in it.
5. Record the result in `reporting.md` using the catalog's exact ID, and say
   **how** it was verified. A bare `PASS` is not a value.

## What no check here can tell you

That the app behaves correctly on real Windows hardware — real compositing, real
focus, real DPI, real monitors. That is 27 rows in
`project_realworld_testing.md`, it is the reason this folder exists, and it is
**not** closed by a green gate.

The gate is a floor. Two of the three real bugs in this project were found by
looking at the running app, not by an assertion.