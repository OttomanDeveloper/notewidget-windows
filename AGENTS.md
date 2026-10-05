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
   `flutter` and exactly one package: `markdown`, the CommonMark parser, added
   on 2026-10-04 when the owner reversed "no Markdown". Windows behaviour is
   still hand-written in `windows/runner/` — do not add a package to get a
   window effect. **Why one is allowed:** the rule was never "never depend on
   anything", it was "do not buy a platform capability instead of owning it",
   and a conforming Markdown parser is the opposite case: writing a CommonMark
   implementation is a project in itself and hand-rolling one would have been
   *less* ownership, not more. **What stayed in this repo** is everything the
   dependency does not do — the renderer, the density budgets, the palette
   styling, and every decision about what is and is not rendered. Adding a
   second package needs the owner to say so, because the argument that carried
   the first one does not carry automatically.
5. **Palette ids are frozen.** The ids in `lib/src/ui/palette.dart` live in
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
   `ValueNotifier` read by a `ValueListenableBuilder`. A `State` survives as the
   disposal shell for a controller or a focus node.
   **Why:** 24 call sites, and the reason they are all navigation, loading and
   responsive layout is that they are all state that was never given anywhere to
   live. **Enforced** by `no_set_state_test`.
8. **No widget below a `ProviderScope` receives a dependency by parameter.** A
   `value` may cross a boundary - an `int index`, a `String path`, a
   `void Function()` callback. A controller may not; it is read with `ref.watch`
   to draw and `ref.read` to act.
   **Why:** the rule is about where state comes from, not about which library is
   installed, which is why it has teeth before `riverpod` is in `pubspec.yaml`.
   Introducing a state package without this rule changes nothing: the next thing
   anyone writes is `Pane(controller: ref.read(notesProvider))` and the plumbing
   is back. **Enforced** by `provider_guard_test`.
9. **The Dart-to-runner contract is declared, not inferred.** 28 method names
   live in `platformMethodRegistry` and in `docs/platform_pattern.md` §2, and a
   guard checks the registry, the calls in `shell_channel.dart` and the runner's
   handlers are the same set. Every method's behaviour on failure is written down.
   **Why:** `result->Success()` is returned whether or not the runner handles a
   method, so a one-sided addition is a silent no-op that no test notices.
   **Enforced** by `platform_guard_test`.
10. **Construction happens in a provider, once, and both surfaces build the same
    graph.** Nothing under `lib/src/ui/` constructs a repository or a controller.
    Each root owns its own `ProviderScope`; nothing goes in `main()`.
    **Why:** the two roots construct the same five things separately, and
    `_resolveBrightness` has already forked into three copies that disagree - see
    §4.7. **Enforced** by `isolate_guard_test`.

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
| `docs/testing_pattern.md` | What each kind of test here may claim, the 389 tests, and the ten traps that cost real time. |
| `README.md` | Users. Install, build, screenshots, bugs. |
| `CHANGELOG.md` | `## Unreleased` holds work not yet tagged, as one bullet per change and nothing else (§0.6). |

Read the relevant pattern doc **before** touching that seam. Each ends with a
table naming the tests that pin its rules; a rule with no test name in that
table is a comment, not a rule.

---

## 3. Layer Rules

```
ui/  ──>  state/  ──>  data/  ──>  core/
 │         │           │
 └─────────┴───────────┴──>  platform/shell_channel.dart  ──>  runner (C++)
```

- **`dart:io` file operations belong to `core/` and `data/` only.** 19
  operations live there. Zero anywhere else, and that is now enforced — see §3.1.
- **`platform/` is the only place that touches `MethodChannel`.** No file in
  `ui/` or `state/` constructs one; they go through `ShellChannel`.
- **Every method name must exist on both sides.** 28 in C++, all reachable from
  Dart. Adding one on one side only is a silent no-op — `result->Success()` is
  returned either way, so the Dart `await` completes and nothing happens.

### 3.1 The layer rules are enforced

`test/architecture/` - 98 tests, in CI, in `flutter test`. Not prose:

| Guard | What it fails on |
|---|---|
| `layer_test` | any `dart:io` operation in `ui/`, `state/` or `platform/`; a `MethodChannel` built outside `platform/`; a method called from Dart that the runner does not handle |
| `storage_guard_test` | the watcher attached to the file instead of the directory; the export not going through the atomic writer; `.bak` taken after the replace instead of before |
| `widget_guard_test` | the runner answering `HTCAPTION`; the loop cursor seeded from `GetCursorPos` instead of the anchor; `WS_EX_NOACTIVATE` not restored; focus not returned to the window it was taken from; `WM_MOUSEACTIVATE` not deferring to compose mode; the editor created topmost; `SetAlwaysOnTop` reachable for the editor; no `WM_ACTIVATE`; the widget demoted **without** the editor being raised; no `WM_GETMINMAXINFO`; the editor's minimum size written unscaled, as `ptMinSize`, or alongside `ptMaxPosition` |
| `docs_test` | a rule in §3 of a pattern doc with no row in its test table; a cited test that no longer exists; a cited guard that does not exist; this file claiming a fixed rule is still broken |
| `changelog_guard_test` | a `CHANGELOG.md` entry longer than one bullet, or a second paragraph hung off the same bullet (§0.6) |
| `no_set_state_test` | a `setState(` call in `lib/` beyond the recorded countdown; a stale budget line left behind after one is removed (§0.7) |
| `provider_guard_test` | a widget below a scope holding a controller, the shell channel or settings as a constructor parameter (§0.8) |
| `platform_guard_test` | a method in the registry that Dart never sends or the runner never handles; a call in `shell_channel.dart` that is not in the registry; an `event.*` name in the outbound set (§0.9) |
| `isolate_guard_test` | a repository or controller constructed under `lib/src/ui/` beyond the recorded countdown; a `ProviderScope` in `main()` rather than in a root (§0.10) |
| `dependency_guard_test` | a runtime dependency in `pubspec.yaml` that is not on the enumerated list in §0.4; an approved list that has quietly grown into "anything goes" |

The guard has **no allowlist**, on purpose. If a write genuinely cannot go
through `data/`, the fix is to edit the scanner where the diff shows it.

**Every one of them has been broken on purpose to prove it goes red.** The list
is in `docs/testing_pattern.md` §6. A guard that has never failed is a comment.

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

7. **`_resolveBrightness` exists in three copies and they disagree.**
   `editor_app.dart` has one; `widget_app.dart` has two. The editor's falls back to
   a live `_systemBrightness` field, the widget's hardcodes `Brightness.light`. If
   both surfaces are open and Windows changes theme while the app runs, the two can
   resolve "system" differently and the widget's palette will not match the
   editor's. Not fixed, because §0.10 is the fix and §0.10 is not landed.
   `docs/isolate_pattern.md` §3.1.
8. **Four `unawaited(...flush())` calls run inside `dispose()`.**
   `editor_app.dart` and `widget_app.dart` both flush pending writes without
   awaiting, in a teardown whose isolate is about to end. `docs/storage_pattern.md`
   §3.11 says never lose a data file, so this is a live hazard and it is
   **pre-existing** - not caused by any provider work, and not to be fixed as a
   drive-by. Riverpod's `ref.onDispose` cannot fix it either, being synchronous:
   the real fix is making the write durable where it happens, which is a
   `docs/storage_pattern.md` question. `docs/isolate_pattern.md` §4.3.

## 5. Known Bugs

1. **First launch sometimes shows the widget when it should hide it.**
   Reproduced 4/4 on a genuinely fresh profile with valid JSON: the widget paints
   "No notes" while visible. Every candidate show/hide site has been read and
   ruled out. **Unrooted.** Needs an instrumented build. Do not "fix" it by
   changing the visibility rule — that is §4.5 and it is a decision.

2. **Nothing else is known broken.** If you find something, add it here before
   fixing it, so the record is honest about the order things were found in.

---

## 6. Before You Push

```
flutter analyze          # must be clean
flutter test             # 389 passing
```

Then: a `## Unreleased` entry in `CHANGELOG.md`, **one bullet per change saying
what changed** (§0.6 — not why; the *why* goes in `PROJECT.md` or a pattern doc,
and `changelog_guard_test` fails the long version). Every rule added to a
pattern doc gets its row in that doc's §7 table.

Builds fail with **LNK1104** if `win_notes.exe` is running from
`build\...\Release\`. Stop it first.