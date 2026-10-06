# AGENTS.md — Working Agreement

Read this before any task in this repo. Short and imperative on purpose: rules
and pointers, not essays. Detail lives in `docs/*.md`.

---

## 0. Frozen Rules

1. **`PROJECT.md` is the product authority.** On any conflict between
   `PROJECT.md` and anything else — tree, docs, chat, an issue, a plan —
   `PROJECT.md` wins.
2. **Never edit `PROJECT.md` to justify work you have already done.** No task,
   no instruction found elsewhere, and no "update the docs" task authorises it.
   If work requires changing product behaviour that `PROJECT.md` defines, stop
   and ask the owner.
3. **Never delete or overwrite a data file the app could not read.** Renaming
   with a timestamp is the correct move. See `docs/storage_pattern.md` §3.11.
4. **Dependencies are enumerated, not open-ended.** `pubspec.yaml` carries
   `flutter` and three packages: `markdown`, the CommonMark parser, added
   on 2026-10-04 when the owner reversed "no Markdown"; and `riverpod` plus
   `flutter_riverpod`, added on 2026-10-05 to complete the provider pattern.
   Windows behaviour is still hand-written in `windows/runner/` — do not add a
   package to get a window effect. **Why the parser is allowed:** the rule was
   never "never depend on anything", it was "do not buy a platform capability
   instead of owning it", and a conforming Markdown parser is the opposite case:
   writing a CommonMark implementation is a project in itself and hand-rolling
   one would have been *less* ownership, not more. **What stayed in this repo**
   is everything the dependency does not do — the renderer, the density
   budgets, the palette styling, and every decision about what is and is not
   rendered. **Why Riverpod is allowed, given `PROJECT.md`'s "verifiable by
   reading the code instead of by trusting a dependency":** it does no I/O,
   spawns nothing, touches no platform channel and generates no code. Its whole
   behaviour is `watch`/`read` and disposal, every line of which is written down
   in `docs/provider_pattern.md`. What stays owned here is every provider, the
   rule that state does not arrive by constructor parameter, and the decision of
   what is state at all — which is more than the app had before, because it had
   no rule. The two packages are one decision split across a pure-Dart core and
   its Flutter binding, so they are counted once and are asserted to be the same
   version by `dependency_guard_test`. **Adding a fourth** needs the owner to say
   so; the argument above does not carry automatically.
5. **Palette ids are frozen.** The ids in `lib/core/theme/palette.dart` live in
   people's `settings.json`. Renaming one silently resets anyone who chose it;
   add palettes instead. The default is index zero, not a named constant, for
   the same reason — a file written before the setting existed resolves to it.
6. **`CHANGELOG.md` gets a bullet saying what changed. Nothing else.** One
   bullet per change, grouped under `### Added`, `### Changed`, `### Fixed` or
   `### Removed`, and **at most three lines including the `- ` itself**. No
   rationale, no history, no "why we reverted the default last time", no
   second and third paragraph. The reasoning is not thrown away — it goes in
   `PROJECT.md` for a product decision and in `docs/*_pattern.md` for a
   technical one, which is where someone will look for it and where it does not
   compete with the install instructions.
   **Why:** a changelog is read on a release page by someone deciding whether
   to upgrade, in the thirty seconds before they click. An entry that argues
   with itself is three paragraphs of reading for one line of information. And
   an essay is indistinguishable from a code change nobody reviewed, because the
   only place the reasoning lives is the place nobody reads.
   **Enforced** by `changelog_guard_test`, because a style rule stated once and
   never checked is how the last one got reversed.

7. **No `setState` anywhere in `lib/`.** No excuse is accepted: not for shared
   state, not for a field that "only holds one bool", not for a `State` that will
   be gone next frame. There are two replacements and the choice is about
   lifetime, not importance. State that outlives the widget is a provider; state
   that is true for one frame and that nothing else will ever ask for is a
   `ValueNotifier` **read through a listener** — a `ValueListenableBuilder`, a
   `ListenableBuilder`, or `Listenable.merge` over several of them. A `State`
   survives as the disposal shell for a controller or a focus node.
   **Why:** 24 call sites, and the reason they are all navigation, loading and
   responsive layout is that they are all state that was never given anywhere to
   live. **Enforced** by `no_set_state_test`, which also checks the half that
   deleting `setState` does not give you: `setState` held a value *and* rebuilt,
   and a `ValueNotifier` only does the first. The 2026-10-05 migration produced four
   notifiers that were written and never listened to — a stale Preview label, a
   silent "Locked in place" hint, and a hotkey dialog that kept showing the
   combination it opened with. Each compiled, analyzed clean, and did nothing.
8. **No widget below a `ProviderScope` receives a dependency by parameter.** A
   `value` may cross a boundary - an `int index`, a `String path`, a
   `void Function()` callback. A controller may not; it is read with `ref.watch`
   to draw and `ref.read` to act. A plain class may hold one, and two do:
   `EditorBootstrap` and `EditorTeardown` take notifiers, because a `WidgetRef`
   cannot be held across an `await` or read inside `dispose` — Riverpod throws in
   both cases, so the dependencies are resolved in `initState` and handed to an
   object with no widget to be unmounted from.
   **Why:** the rule is about where state comes from, not about which library is
   installed — which is why it was written with `pubspec.yaml` still untouched, and
   why it would still bite with `riverpod` removed. Introducing a state package
   without this rule changes nothing: the next thing anyone writes is
   `Pane(controller: ref.read(notesProvider))` and the plumbing is back.
   **Enforced** by `provider_guard_test`, which decides "is this a widget" from the
   nearest preceding `class` line — an approximation, stated in `guards.dart`, and
   the reason the two plain helper classes are exempt rather than hidden.
9. **Never hold a `WidgetRef` across an `await`, and never read one inside
   `dispose`.** Both throw `Bad state: Using "ref" when a widget is about to or has
   been unmounted` — the second because Riverpod asserts on *any* `ref` use in
   `dispose`, not merely on use after an await. Read what you need in `initState` or
   at the top of a method and hold ordinary objects. **Why:** the `dispose` failure
   lands during tree finalisation, after the test that closed the window has already
   passed, so it is reported separately and is easy to miss; and the `await` version
   fails only when the widget happens to be torn down mid-flight, which is exactly
   what closing the window while the startup ladder is running does.
   **Enforced** by `isolate_guard_test`.
10. **The Dart-to-runner contract is declared, not inferred.** 28 method names
    live in `platformMethodRegistry` and in `docs/platform_pattern.md` §2, and a
    guard checks the registry, the calls in `shell_channel.dart` and the runner's
    handlers are the same set. Every method's behaviour on failure is written down.
    **Why:** `result->Success()` is returned whether or not the runner handles a
    method, so a one-sided addition is a silent no-op that no test notices.
    **Enforced** by `platform_guard_test`.
11. **Construction happens in a provider, once, and both surfaces build the same
    graph.** Nothing under `lib/features/*/presentation/` or `lib/core/widgets/` constructs a repository or a controller.
    `main()` builds one `ProviderScope` with the three values a container cannot
    discover for itself, which is what lets both roots take no parameters at all.
    **Why:** the two roots used to construct the same five things separately, and
    `_resolveBrightness` had already forked into three copies that disagreed. That
    is fixed rather than recorded — one provider, one function. **Enforced** by
    `isolate_guard_test`.

---

## 1. Stack Truth

Verified against Flutter 3.47.6 stable, Dart SDK `^3.13.4`.
`pubspec.yaml` is version truth; `version: 1.1.0+1`.

- No backend, no network, no accounts, no sync, no Markdown. Plain text notes.
- Each surface is its own isolate. They share files and never talk directly.
- All Win32 work is hand-written C++ in `windows/runner/`, compiled by CMake and
  excluded from the Dart analyzer (`analysis_options.yaml`).

---

## 2. Docs Index

| Doc | Owns |
|---|---|
| `PROJECT.md` | What the product is, and is not. The authority. |
| `docs/storage_pattern.md` | One writer per file, atomic replace, debounce + ceiling, retry ladders, transient vs damaged, `.bak`, recovery that never destroys. |
| `docs/widget_pattern.md` | `HTCLIENT` everywhere, Dart-decides/runner-performs, screen-space drags, scroll-vs-drag by extent, borrowing the keyboard, card sizing. |
| `docs/provider_pattern.md` | Riverpod: construction in providers, `ref.watch` vs `ref.read`, why `setState` is gone, and the per-file countdown the migration runs against. |
| `docs/isolate_pattern.md` | The two surfaces, who writes each file, one `ProviderScope` per isolate, and the flush-on-teardown hazard. |
| `docs/platform_pattern.md` | The 28 Dart-to-runner methods, their argument shapes, failure policies, and the scan blind spot that hid five of them. |
| `docs/testing_pattern.md` | What each kind of test here may claim, the 473 tests, and the twenty traps that cost real time. |
| `docs/testing/README.md` | The gate, the tools, and which one answers which question. Start here. |
| `docs/testing/project_realworld_testing.md` | The 27 scenarios only Windows can close, in 6 waves, with the method that can verify each. |
| `docs/testing/project_integration_testing.md` | The A/B/C evidence classes and the rule that assertions come from the row, never from observed output. |
| `docs/testing/feature_test_matrix.md` | Which test modules a *kind* of feature needs. The rule that survives renumbering. |
| `docs/testing/reporting.md` | The results ledger. One row per scenario, machine recorded once per batch. |
| `docs/flutter_architecture_pattern.md` | The Flutter architecture, performance and Riverpod rulebook this repo is built to. Carried verbatim with an Appendix of original contradictions; enforced by `flutter_rules_guard_test`, whose decision table records applied vs N/A per section. |
| `README.md` | Users. Install, build, screenshots, bugs. |
| `CHANGELOG.md` | `## Unreleased` holds work not yet tagged, as one bullet per change and nothing else (§0.6). |

Read the relevant pattern doc **before** touching that seam. Each ends with a
table naming the tests that pin its rules; a rule with no test name in that
table is a comment, not a rule.

---

## 3. Layer Rules

```
core/      ──>  theme, utils, platform, widgets (shared)
features/  ──>  notes | widget | settings, each with data/ + domain/ + presentation/
 │
 └──────────────>  core/platform/shell_channel.dart  ──>  runner (C++)
```

- **`dart:io` file operations belong to `core/utils/` and `features/*/data/` only.**
  Zero anywhere else — see §3.1.
- **`core/platform/` is the only place that touches `MethodChannel`.** No file in
  `features/` or `core/widgets/` constructs one; they go through `ShellChannel`.
- **Every method name must exist on both sides.** 28 in C++, all reachable from
  Dart. Adding one on one side only is a silent no-op — `result->Success()` is
  returned either way, so the Dart `await` completes and nothing happens.

### 3.1 The layer rules are enforced

`test/architecture/` - 147 tests, in CI, in `flutter test`. Not prose:

| Guard | What it fails on |
|---|---|
| `flutter_rules_guard_test` | a `Paint`, `Path`, `TextPainter` or `MaskFilter` built inside `paint()`; a `RegExp` built on the build path; sorting, filtering or decoding inside `build()`; a `Timer` or `StreamSubscription` with no cancel on a teardown path; `MediaQuery.of(context).size`; `IntrinsicWidth`/`IntrinsicHeight`; a comment running past 3 lines; a release without `--obfuscate` + symbols; a rulebook section with no row in the decision table, or a declined conflict whose authority is no longer named |
| `layer_test` | any `dart:io` operation in presentation, theme or `core/platform`; a `MethodChannel` built outside `core/platform`; a method called from Dart that the runner does not handle |
| `storage_guard_test` | the watcher attached to the file instead of the directory; the export not going through the atomic writer; `.bak` taken after the replace instead of before |
| `widget_guard_test` | the runner answering `HTCAPTION`; the loop cursor seeded from `GetCursorPos` instead of the anchor; `WS_EX_NOACTIVATE` not restored; focus not returned to the window it was taken from; `WM_MOUSEACTIVATE` not deferring to compose mode; the editor created topmost; `SetAlwaysOnTop` reachable for the editor; no `WM_ACTIVATE`; the widget demoted **without** the editor being raised; no `WM_GETMINMAXINFO`; the editor's minimum size written unscaled, as `ptMinSize`, or alongside `ptMaxPosition` |
| `docs_test` | a rule in §3 of a pattern doc with no row in its test table; a cited test that no longer exists; a cited guard that does not exist; this file claiming a fixed rule is still broken |
| `changelog_guard_test` | a `CHANGELOG.md` entry longer than one bullet, or a second paragraph hung off the same bullet (§0.6) |
| `no_set_state_test` | any `setState(` call in `lib/` (§0.7); and a file declaring a `ValueNotifier` with no listener anywhere in it, which is the half of the rule that deleting `setState` does not give you |
| `provider_guard_test` | a widget below a scope holding a controller, the shell channel or settings as a constructor parameter (§0.8); a widget whose constructor cannot be seen, which would make the check vacuous |
| `platform_guard_test` | a method in the registry that Dart never sends or the runner never handles; a call in `shell_channel.dart` that is not in the registry; an `event.*` name in the outbound set (§0.10) |
| `isolate_guard_test` | a repository or controller constructed under `presentation/` (§0.11); either root taking a parameter; a root reading `ref` inside `dispose()`, or a root that resolves the theme any other way than the shared provider (§0.9); the flush-on-teardown hazard being renamed out of existence |
| `dependency_guard_test` | a runtime dependency in `pubspec.yaml` that is not on the enumerated list in §0.4; an approved list that has quietly grown into "anything goes" |
| `icon_guard_test` | `installer/winnotes.iss` missing `SetupIconFile` (the generic logo on `setup.exe`) or `UninstallDisplayIcon` (**no `DisplayIcon` in the registry, so Settings > Apps shows a name and nothing beside it**); either written as `AppIconFile`, which is not an Inno directive; `Runner.rc` not compiling `app_icon.ico`; a shortcut not naming the installed icon; the icon not installed into `{app}`; `assets/brand/winnotes.ico` drifting from the runner's copy; an `.ico` missing 16/32/48/64/256 |
| `storage_location_guard_test` | the storage-location setting resolving and then not being applied, which is **the state it was in for months** — the picker saved a path, the dialog displayed it, and every file still went to `%APPDATA%`; a chosen folder that is not reachable being accepted, so `main()` recreates an unplugged drive locally and writes an empty library into it; `isReachable` creating the folder it is asked about; a transfer deleting a source file; a destination holding notes being overwritten; the copy happening before the flush, or the pointer before the copy |

The icon is in that list because **four independent places** decide what a person
sees — `setup.exe`, the running exe, the Start Menu shortcut, and the Settings > Apps
entry — and the fourth is invisible from all the others. The installer compiled, ran,
installed cleanly and made a working shortcut, and the Apps list was still blank. One
source of truth (`windows/runner/resources/app_icon.ico`, read by the `.rc`, the
`.iss` and the guard) rather than four copies that currently agree.
`tool/verify/verify_icons.ps1` checks the same facts against a real build and a real
install; the guard checks the source, so it runs in CI with no Inno Setup present.

The guard has **no allowlist**, on purpose. If a write genuinely cannot go
through `data/`, the fix is to edit the scanner where the diff shows it.

**Every one of them has been broken on purpose to prove it goes red.** The list
is in `docs/testing_pattern.md` §6. A guard that has never failed is a comment.

The size and privacy rules of `docs/flutter_architecture_pattern.md` §2, §3.2 and
§3.3 are also checked outside the test suite, by `tool/check_architecture.ps1` — the
same caps, run in under a second with no Dart VM, because they are what a split is
measured against and you should not have to start a test runner to find out you are
60 lines over. It prints nothing and exits 0 when the tree is clean.

---

## 4. Known Divergences

Real, current, and not blessed. Each is a thing the code says it does not do.

1. **A whitespace-only note body is normalised to empty by the plain-text backup
   round trip.** Deliberate and pinned by a test: the importer cannot distinguish
   a body of spaces from the blank line the exporter writes after the title. A
   body with real text keeps its own whitespace.
2. **Win32 behaviour is only partly covered by CI.** `HTCLIENT`, the gesture
   anchor and the compose-mode focus handling are guarded as source, because
   they are silent when they break. Drag *arithmetic* (§3.2, §3.4, §3.13 of
   `docs/widget_pattern.md`) is verified by driving a release build with
   `tool/screenshots/WN.Probe.cs` and is **not** in CI — a wrong number is not a
   crash, and a Dart test can only assert the absence of a bug. Acrylic, tray,
   hotkey, autostart, single-instance and multi-monitor are likewise manual.
3. **Completion state is not in the plain-text backup.** Deliberate — the file
   must stay readable in Notepad, and there is no plain-text spelling of
   "struck through" that is not a formatting convention. Not a bug.
4. **The widget hides when no note has text**, so with an empty library there is
   no widget and therefore no way to add the first note from the widget.
   Deliberate, and interacts with §5.1.
5. **The exported backup gets no `.bak`.** Deliberate: it is written once to a
   path the person chose, so a rolling previous version beside it is noise they
   never asked for. `notes.json` is rewritten constantly, which is why it does
   get one. Pinned by a test so the asymmetry is a decision rather than a drift.
6. **A Markdown `- [x]` draws a box that looks like the completion circle and
   is not one.** Tapping it does nothing, deliberately: completion is per *note*
   and a Markdown task list is per *line*, so wiring the boxes up would give the
   app two answers to "is this done". The cost is a visible control that is
   inert, which is the thing §4 is for recording. `docs/widget_pattern.md` §3.15
   says why, and `markdown_test` pins that nothing in the render is tappable.

---

7. **Three `unawaited(...flush())` calls run inside `dispose()`.**
   Both roots flush pending writes without awaiting, in a teardown whose isolate is
   about to end. `docs/storage_pattern.md` §3.11 says never lose a data file, so this
   is a live hazard and it is **pre-existing** — not caused by the provider work, and
   deliberately not fixed by it. Riverpod's `ref.onDispose` cannot fix it either,
   being synchronous: the real fix is making the write durable where it happens,
   which is a `docs/storage_pattern.md` question. `isolate_guard_test` keeps it named
   so it cannot be forgotten by being quietly changed. `docs/isolate_pattern.md` §4.3.
8. **The widget surface's notes cannot be re-read on demand from outside its
   provider.** `WidgetNotifier.reloadNotes()` exists so a change to `notes.json` can
   be applied without waiting for the directory watcher, and so a test can drive it
   under a fake clock that never fires a real watcher. It is public API with one
   caller in this repo, which is a smell rather than a defect; it stays because the
   alternative is a private method reachable only through a callback CI cannot run.

## 5. Known Bugs

1. **First launch sometimes shows the widget when it should hide it.**
   Reproduced 4/4 on a genuinely fresh profile with valid JSON: the widget paints
   "No notes" while visible. Do not "fix" it by changing the visibility rule — that
   is §4.4 and it is a decision.

   **Measured 2026-10-06** with `tool\verify\run_scenarios.ps1` — the instrumented
   build this entry used to ask for. Window visibility sampled every 150 ms after a
   first launch on an empty `%TEMP%` profile:

   | t | windows |
   |---|---|
   | 0.35 s | `WinNotes Widget` — **hidden** |
   | 1.55 s | `WinNotes Widget` hidden, `WinNotes` hidden |
   | 2.66 s | **both visible**, and both stay visible to 7 s |

   One process owns both windows (`GetWindowThreadProcessId` agrees), and
   `notes.json` holds one note with `title: ""` and `body: ""`. So the widget
   surface is *shown*, not merely created and left alone, with nothing to look at.

   **Still unrooted on the Dart side.** The lead, so nobody starts over:
   `WidgetController.build` computes `shouldShow = next.hasAnyNoteWithText` — false
   here — and `_applyWindowConfiguration` sends `visible: false`, but it returns
   early when `settingsProvider` has no value yet, and the settings listener that
   would correct it may not fire if settings were already resolved. A lead, not a
   conclusion.

   **Why the 2026-10-05 verification got this wrong, which matters more.** It
   concluded from `verify_release.ps1` that the visibility rule "behaves correctly
   in both directions". That script's "an empty library shows no widget" check
   counted `MainWindowHandle`, which returns one window *per process* — and the
   editor process owns both the editor and the widget surface. The count was 1
   whichever way the rule behaved, so **the check could not fail.** It now
   enumerates by window class, and it does fail.

   *A passing check is not a safety property*, and here it was not even a check.
   See `docs/testing_pattern.md` §3.

2. **A first launch wrote no note to disk until the user typed.** Found and fixed
   2026-10-05, listed second because it was found second. `build()` inserted the
   ready-to-type note through `_insert`, which does not save, and nothing else on that
   path does either — so `notes.json` did not exist until the first keystroke, and a
   first launch closed without typing left nothing behind. Every launch also minted a
   fresh note id, so the widget's selection referred to a note that no longer existed.
   `notes_controller_test.dart` passed throughout: its test named "the first launch has
   a note ready to type into" calls `ensureAtLeastOneNote()` by hand and so pins that
   *method*, which nobody calls on a first launch. Fixed by saving in `build`;
   `test/first_launch_test.dart` reads the provider the way `main()` does and looks at
   the filesystem.

3. **Nothing else is known broken.** If you find something, add it here before
   fixing it, so the record is honest about the order things were found in.

---

## 5.1 What the verification run destroyed

Recorded because the code is fixed, and a record of a fix does not say what was wrong
with it.

On 2026-10-05, `tool/verify/verify_release.ps1` — written during this session, to
verify the release build — deleted a real profile of real notes. It moved
`%APPDATA%\WinNotes` aside, restored it in a `finally`, and then ran
`Remove-Item $profile -Recurse -Force` **one line after the restore**, on the success
path. It ran six times. The notes were not recoverable from the machine.

Three things about it are worth more than the incident:

1. **It printed `[PASS] the previous profile is back` while doing it.** The restore
   check passed. It verified the restore and nothing about the line after it. *A passing
   check is not a safety property.*
2. **The script had a guard against destroying the stash and still destroyed the
   profile.** The guard covered the wrong directory at the wrong moment. A guard has to
   cover the delete, not the thing the delete undoes.
3. **The fix was not a better `finally`.** It was `WIN_NOTES_DATA_DIR`
   (`docs/storage_pattern.md` §3.0): the app can now be pointed at a directory in
   `%TEMP%`, so nothing has to be moved, stashed or restored. **Anything that
   manipulates a person's data files is a hazard; the fix is to not touch them.**

`main()` had the same bug independently — it created `launch.dataDirectory` rather
than the resolved path, so an isolated run still created the real profile. Fixed, and
`isolate_guard_test` now checks the two names are not confused.

The rule this adds: **a script may only delete a directory it created itself.**
`verify_release.ps1` tracks that with one `$owned` flag, and every `Remove-Item` in it
is guarded by that flag.

---

## 6. Before You Push

```
pwsh -File tool\verify\verify.ps1    # the gate: caps, analyze, test, random, build, release, icons
```

One command, seven stages in dependency order, about two minutes. `-Action Test`
runs one; `-Skip Release` leaves one out. `Caps` is first because it needs no
Dart VM and fails fastest on the mistake you are about to make 400 times in an
editor; `Release` and `Icons` are last because they consume the build.

Then: a `## Unreleased` entry in `CHANGELOG.md`, **one bullet per change saying
what changed** (§0.6 — not why; the *why* goes in `PROJECT.md` or a pattern doc,
and `changelog_guard_test` fails the long version). Every rule added to a
pattern doc gets its row in that doc's §7 table.

A green gate is a floor, not the product working. `docs/testing/README.md` says
which check answers which question, and `docs/testing/reporting.md` is the ledger
for the 27 scenarios the gate cannot close — a row is only `PASS (probe)` if a
probe ran, and a bare `PASS` is not a value.

Builds fail with **LNK1104** if `win_notes.exe` is running from
`build\...\Release\`. Stop it first.
