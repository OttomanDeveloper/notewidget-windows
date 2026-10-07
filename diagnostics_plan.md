# Diagnostics — implementation plan

Target: when something goes wrong on a machine I cannot see, the evidence is on
disk and the answer arrives in one message instead of one session.

**Authority: `PROJECT.md` says no network, no accounts, no sync, no backend.** So
this collects nothing and sends nothing. Every file stays under
`%APPDATA%\WinNotes` and reaches me because you paste it. Nothing here may add a
dependency (§0.4) or a file outside the profile directory.

## What this would and would not have caught

The widget-position bug was **silent and correct-behaved**. No exception, no
crash, no failed assertion: the app started, created both windows, and put one
in the wrong place. A crash reporter logs a clean run and finds nothing.

What actually cost time there was a bad *measurement* — filtering windows by
title, getting nothing back, and reporting "no window appeared" when both
windows were up. That is a mistake I made, not a gap in the app, and no amount
of instrumentation inside the product would have caught it.

So the three items below are ordered by what they actually catch. Item 3 is the
one that would have caught that class of bug, and it is the cheapest.

---

## Wave 1 — Self-check tests (no new files in the profile)

Restores the invariant that `docs/testing_pattern.md` §3 argues for and that
this session proved matters: *a passing check is not a safety property*. The
`§5.1` "an empty library shows no widget" check counted one window per process
and therefore could not fail; the widget-position bug shipped with no test at
all that a saved position survives a restart.

- **`widget_integration_test`** — extend what this session added. Assert the
  full save→restore round trip through `widget_state.json` with a fake channel,
  so "saved geometry survives a restart" is a CI fact rather than a claim.
- **`first_launch_test`** — assert the widget is hidden on a genuinely empty
  library *and* shown when one note has text, driven the way `main()` drives it.
  `widget_integration_test:770-783` already asserts both directions of
  `hasAnyNoteWithText`/`widgetVisible`, so the *rule* is tested; what is not
  tested is the startup ladder that produced the `§5.1` symptom, including the
  `settings == null` early return in `_applyWindowConfiguration` and the
  `event.geometry` timing. That is the unrooted bug, and a test stating both
  directions is what a fix will have to satisfy.
- **`app_paths_test`** — untouched in this wave. Listed here so the Wave 2
  contract change is not a surprise.

Verify: `flutter test test\first_launch_test.dart test\widget_integration_test.dart`
then the full suite. `check_architecture.ps1` unchanged.

**Risk: the `§5.1` test will fail, because the bug is unrooted.** That is the
point — it converts an open question into a red test with a stated expected
value. It goes in a `skip:` with the reason, not left deleted and not made
vacuously green. `docs/testing/reporting.md` gets a row.

---

## Wave 2 — Crash capture, appended to one rotating file

The real hole: `main.cpp:42` creates a console only when a debugger is attached,
so a release build launched at login has nowhere to print. A Dart exception in a
widget build dies silently and the evidence goes nowhere.

- **`core/utils/crash_log.dart`** — `dart:io` is confined to `utils/` and
  `data/` (`layer_test`), so a plain utility in `utils/` is the correct owner.
  Append-only, UTF-8, no dependencies.
- **Two Dart hooks** — `FlutterError.onError` and
  `PlatformDispatcher.instance.onError`, installed at the top of `main()` before
  the `ProviderScope`. The stack, the isolate, and the notes/settings file sizes
  (never note *content* — see below).
- **One native hook** — `SetUnhandledExceptionFilter` in `win_notes_window.cpp`,
  appending the Win32 fault code and the exception addresses. `main.cpp` already
  has the console logic; this is the no-console case.
- **Rotation** — cap at 256 KB, keep one previous file. The rename-with-timestamp
  shape is already written in `notes_repository.dart:155-167`; reuse it rather
  than inventing a second convention.
- **`app_paths.dart`** — add `crashLogFile`. This makes it a **fifth** file in
  the profile and changes the contract pinned by `app_paths_test:166` ("the four
  files"). That test gets a row, and `docs/storage_pattern.md` §3 gets a rule
  stating that the log is not a data file and is never read back as one.

**Never write note text, note titles, or file paths containing a Windows user
name.** A crash log gets pasted into a public issue; `ISSUE_REPORTING.md:56`
already says a report is public the moment it is submitted, and a stack trace
carrying `C:\Users\<someone>\...` would leak a name into a permanent record.
File *sizes* and a content hash are enough to tell "notes failed to parse" from
"notes were empty".

Verify: a test that forces an exception and asserts the file exists, the stack
is in it, and the rotation renames rather than deletes. Full suite + a release
build launched with no parent console.

---

## Wave 3 — A diagnostic dump on demand (optional, largest, least certain)

Not a log. A snapshot of the state that actually answered the widget bug: launch
mode, resolved profile paths, parsed-and-summarised notes/settings/widget-state,
live window handles, the registry autostart entry, monitor count. One paste.

Deliberately **not** continuous. Continuous logging of this much state writes
sensitive metadata to disk on every launch to fix a problem that occurs rarely —
the same reasoning `ISSUE_REPORTING.md:3` already applies to crash reporting.
This runs when asked.

- `diagnostics.dump()` in `core/utils/`, behind a `widget.diagnostics` method in
  `platformMethodRegistry` **with the C++ handler in the same change**.
  `§0.10`: a one-sided addition is a silent no-op because `result->Success()` is
  returned either way. The registry goes 28 → 29 and
  `platform_guard_test`'s expectations follow.
- Trigger: a Settings item, or `win_notes.exe --diagnose <path>` from a shell.
  The second needs `ResolveLaunchMode()` to grow a mode; the first does not, and
  is cheaper.

Verify: run it against a profile with a deliberately corrupt `notes.json`, assert
the dump says so rather than throwing. Full suite, then a real dump by hand.

**This wave is the one to cut.** It is the largest, it changes the platform
contract, and it duplicates what a 20-line PowerShell probe does today —
`tool/screenshots/WN.Probe.cs` already drives the release build and
`run_scenarios.ps1` already fingerprints a profile. Only build it if Waves 1 and
2 prove insufficient in practice.

---

## Deliberately not doing

- **No telemetry, no upload, no error reporting service.** `PROJECT.md` forbids
  the server; `§0.4` forbids the dependency; and nothing here may make a network
  call from an app whose product authority says it does not touch the internet.
- **No note content in any log.** See Wave 2. `docs/storage_pattern.md` §3.11
  exists because losing a data file is unforgivable; leaking one in a pasted
  issue is the same failure in the other direction.
- **No behaviour change disguised as diagnostics.** Wave 1's `§5.1` test is
  written to state the *expected* behaviour, not to encode the current buggy
  one.
- **No new file outside `%APPDATA%\WinNotes`.** `§5.1`'s rule — a script may only
  delete a directory it created itself — applies to the tooling too.

## Docs to update with each wave

- `PROJECT.md` — only if a product statement conflicts. The `§5.1` widget
  decision and the "no telemetry" line are the two candidates. §0.2: the owner
  decides, so propose rather than edit.
- `docs/storage_pattern.md` §3 + §7 table — the log is not a data file; rotation
  renames.
- `docs/testing_pattern.md` — Wave 1's skip, and what each test may now claim.
- `docs/testing/reporting.md` — a row for the `§5.1` open bug.
- `ISSUE_REPORTING.md` — replace "this project has no crash reporting" with what
  now exists and what to paste.
- `CHANGELOG.md` — one bullet per change, ≤3 lines, no rationale (§0.6).

## Open question for the owner

A log file in the profile directory is a file nobody asked for, sitting next to
someone's notes. `docs/storage_pattern.md` §3.11 governs not losing data but is
silent on files that carry none. Is a fifth file in `%APPDATA%\WinNotes`
acceptable, or should the log live somewhere else — `%LOCALAPPDATA%`, which
Windows already reserves for machine-local state and which never syncs?
