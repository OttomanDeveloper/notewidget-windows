# Which test module a feature needs

Scenario IDs churn. The product grows, the scenario catalog gets renumbered, rows
close. **Feature *types* do not change.** This file is the stable rule: given a
kind of feature, how many test modules it needs and which ones.

## The one principle

> **A feature needs a second test type exactly when it crosses a boundary.**

There are only five boundaries in this app:

| Boundary | Crossing it means | Test type that owns it |
|---|---|---|
| Dart ↔ file | `dart:io`, the atomic writer, the backup ladder | `notes_repository_test.dart` style — real temp dirs, real clock |
| Dart ↔ runner | `ShellChannel`, the 28 methods, window handles | `platform_guard_test` for the contract; a probe for the behaviour |
| Dart ↔ Win32 | hit-testing, geometry, focus, the message loop | `WN.Probe.cs` against a release build |
| Dart ↔ code | what a widget rebuilds, what a provider exposes | `flutter_rules_guard_test`, `provider_guard_test` |
| code ↔ user | what they see, type, and understand | widget test |

A feature that lives entirely inside one layer needs **one** test type. That is
most features. Do not split by layer out of habit.

## The matrix

| Feature type | Primary module | Also needs | Total |
|---|---|---|---|
| Pure calculation — Markdown budget, note ordering | unit | — | **1** |
| Colour and contrast — palette legibility, `readableOn` | unit | — | **1** |
| Business rule over stored data — search, undo window, completion | `notes_controller_test` | — | **1** |
| Screen copy, empty state, error state | widget | — | **1** |
| Anything touching a file - export, import, storage move, backup | real temp dir | a probe for the file dialog | **1 + probe** |
| Diagnostics - a crash log, a dump | unit against a temp dir | a **manual** run of the real exe | **1 + manual** |
| A new `ShellChannel` method | `platform_guard_test` for both sides | a probe if it changes what a person sees | **1–2** |
| A shape or size rule — caps, private widgets, comments | guard or `check_architecture.ps1` | — | **1** |
| Drag, resize, focus or keyboard handling | **probe** | a guard for the rule that must not drift | **1 + probe** |
| Settings that reach the runner — hotkey, autostart, acrylic | unit for the setting | probe or device for the OS effect | **1–2** |
| Screen at scale — a long library, many notes | widget | a measurement; **no device class exists here** | **1 + manual** |
| Windows compositing — acrylic, tray, per-monitor DPI | — | — | **manual only** |

Read the last two rows as boundaries, not as excuses. Scale and compositing are
not Dart problems — they are Windows problems, and no module on this list closes
them.

**The diagnostics row is not fully closed by its unit test, and cannot be.** A
`crash.log` and a `--diagnose` dump are both written from a release build with no
console, so the parts a Dart test cannot reach are the ones that matter: that the
`SetUnhandledExceptionFilter` actually fires, and that the flag reaches Dart at
all. The second one had already failed silently once — the runner owns
`dart_entrypoint_arguments`, so parsing `--diagnose` in `main.dart` compiled,
analysed clean, and never once ran. Both were verified by running the built exe,
and a test cannot replace that.

## Three worked examples from this repo
**Markdown rendering → 5 files, all unit.** `markdown_test.dart` plus the
per-concern files it drives. It crosses no boundary, so it never needs a probe or
a real directory. That is what "one type" looks like when a feature is worth
more than one file.

**Moving your notes folder → 4 files, three types.** `storage_location_test`
resolves the path, `storage_location_guard_test` fails if the resolved path is
then *not* the one used, `storage_transfer` is exercised against real temp dirs,
and the folder picker itself is a probe. It crosses Dart↔file twice over — once
for the copy, once for the delete — and the asymmetry between them is the whole
risk.

**The completion tick → 3 files, two types.** `palette_test` proves the accent
is legible against both surfaces, `completion_painter_test` proves the tick is
drawn at every box size, and `widget_integration_test` proves tapping it routes
correctly from either surface. The painter itself is guarded for per-frame
allocation. Nothing here needs a device, because nothing here is Windows.

## Where the file goes

- One module → `test/<concern>_test.dart`, beside its siblings.
- Several modules → one file per boundary crossed.
- A rule about *shape* rather than behaviour → a scanner in
  `test/architecture/`. Write scanners to take text, not a `SourceTree`, so a
  planted fixture can prove they bite.
- Shared setup → `test/helpers/`. Do not re-derive a temp-directory dance or a
  provider container; `file_io.dart` and `provider_harness.dart` already exist.

Name the file after the **concern**, not the layer: `markdown_test` beats
`widget_test`. `notes_repository_test` beats `data_test`.

## Anti-patterns

- **One test type per layer, by default.** If a feature is pure logic, a real
  temp directory is slower and proves nothing extra.
- **A unit test standing in for a probe claim.** `docs/testing_pattern.md` §2
  Tier C rows stay open until the probe runs. A test cannot assert that a drag
  moved the window 60 pixels.
- **A scanner for a rule that has never broken.** Every guard here has been
  broken on purpose to prove it goes red — see §6 of that doc. A guard that has
  never failed is a comment.
- **A fixed sleep standing in for a wait.** `test/helpers/file_io.dart`'s
  `waitForContent` exists because three tests each grew their own version, and
  two of them were wrong. See the traps in `docs/testing_pattern.md` §3.
- **Reporting `PASS` without saying how.** A row verified by a test is not a row
  verified against Windows. `docs/testing/scenarios.md` carries a Method column
  for that reason.

## Adding a feature: the checklist

1. Name its type from the matrix. That gives you the module list.
2. For each boundary it crosses, add the matching module.
3. If it is user-visible, one widget module for copy and states.
4. If it is a probe row, the test does not close it — the probe does.
5. If it is in the last row of the matrix, it is a manual row and nothing else.