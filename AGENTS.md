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
4. **Zero runtime dependencies.** `pubspec.yaml` has `flutter` and nothing else,
   and that is a decision rather than an accident. Windows behaviour is
   hand-written in `windows/runner/`. Do not add a package to get a window
   effect.

---

## 1. Stack Truth

Verified against Flutter 3.47.5 stable, Dart SDK `^3.13.4`.
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
| `docs/testing_pattern.md` | What each kind of test here may claim, the 164 tests, and the seven traps that cost real time. |
| `README.md` | Users. Install, build, screenshots, bugs. |
| `CHANGELOG.md` | `## Unreleased` holds work not yet tagged. |

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
  operations live there today. The 8 in `ui/` are a known divergence — §4.1.
- **`platform/` is the only place that touches `MethodChannel`.** No file in
  `ui/` or `state/` constructs one; they go through `ShellChannel`.
- **Every method name must exist on both sides.** 28 in C++, all reachable from
  Dart. Adding one on one side only is a silent no-op — `result->Success()` is
  returned either way, so the Dart `await` completes and nothing happens.

---

## 4. Known Divergences

Real, current, and not blessed. Each is a thing the code says it does not do.

1. **The plain-text export bypasses the atomic writer.** `editor_app.dart:162`
   calls `File(path).writeAsString(text)` from the UI layer. Not atomic: an
   interrupted export leaves a truncated file, and that file is what someone
   reaches for when everything else has failed. Five further `dart:io` calls in
   `ui/` are reads and are untidy rather than hazardous.
2. **A whitespace-only note body is normalised to empty by the plain-text backup
   round trip.** Deliberate and pinned by a test: the importer cannot distinguish
   a body of spaces from the blank line the exporter writes after the title. A
   body with real text keeps its own whitespace.
3. **Win32 behaviour is not covered by CI.** Drag correctness, focus borrowing,
   acrylic, tray, hotkey, autostart, single-instance and multi-monitor are
   verified by driving a release build with `tool/screenshots/WN.Probe.cs`. A
   regression in any of them would not be caught automatically. See
   `docs/testing_pattern.md` §2.
4. **Completion state is not in the plain-text backup.** Deliberate — the file
   must stay readable in Notepad, and there is no plain-text spelling of
   "struck through" that is not a formatting convention. Not a bug.
5. **The widget hides when no note has text**, so with an empty library there is
   no widget and therefore no way to add the first note from the widget.
   Deliberate, and interacts with §5.1.

---

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
flutter test             # 164 passing
```

Then: a `## Unreleased` entry in `CHANGELOG.md` that says **why**, not just
what. Every rule added to a pattern doc gets its row in that doc's §7 table.

Builds fail with **LNK1104** if `win_notes.exe` is running from
`build\...\Release\`. Stop it first.