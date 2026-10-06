# WinNotes Real-World Test Program

> The class-A rows worth automating are tracked in
> [`project_integration_testing.md`](project_integration_testing.md). This file is
> the **Windows** half: what a Dart test cannot reach, ordered so that each row
> assumes the ones above it.

## Document purpose

The ordered source of truth for verifying WinNotes against real Windows. For
each scenario it records:

1. What must be true before it runs.
2. The behaviour `PROJECT.md` and `docs/widget_pattern.md` require.
3. **Which test methods can verify it, and in what order.**
4. The actual result once run, in [`reporting.md`](reporting.md).

`PROJECT.md` wins if this file conflicts with it. `AGENTS.md` controls repository
and agent rules. This file must never contain real note bodies or anything read
out of a person's `%APPDATA%\WinNotes`.

## Test harness folders

- `tool/verify/` — host-side. The gate, the release-build drive, the icon audit.
- `tool/screenshots/` — `WN.Probe.cs` for synthetic input, `WN.cs` for window
  handles, `WN.Print.cs` for `PrintWindow` capture.
- `test/` — host-side, but it cannot reach anything in this file. Listed for
  completeness.

## Current status

| Item | Status |
|---|---|
| Gate | **green** — `verify.ps1`, all 7 stages, 473 tests |
| Release drive | **13/13** — first launch, no widget when empty, a note on disk, the widget window, no orphan, real profile byte-identical |
| Icon audit | **13/13** — all four places Windows reads an icon from |
| Row coverage | **0 of 27 closed** — the catalog exists, the ledger does not yet |
| Open blocker | **Probe, not app** — `WN.Probe.cs` exists but is not driven by a scenario script, so every Tier C row needs a person at the keyboard |

The release drive is the strongest evidence this repository has, and it is worth
being precise about what it covers: **the startup path**. It proves the app
starts, writes where it was told to write, shows no widget for an empty library,
shows one when a note has text, and leaves the real profile untouched. It cannot
send a keystroke — `SetForegroundWindow` is ignored from a process Windows does
not consider foreground — so the composer's keyboard path is Dart-suite-only.

## How to read this document

### The method legend

| Code | Method | Runs on | Speed |
|---|---|---|---|
| **U** | Unit test — pure logic, no file | host | milliseconds |
| **W** | Widget test — real widget tree | host | seconds |
| **G** | Guard — a scanner in `test/architecture/` | host | instant |
| **P** | Probe — `WN.Probe.cs` into a real HWND | release build | seconds |
| **D** | Windows, by hand — the original method | desktop | minutes |
| **M** | Measurement — frame time, memory, handle count. Not pass/fail | release build | varies |

`U`, `W` and `G` are what `flutter test` runs. `P` is a person with a probe
script. `D` is a person and the app. `M` produces a number for `reporting.md`,
not a verdict.

**A scenario can be verified several ways, and usually should be.** Take
`WN-DRAG-002` (the size clamp): `G` proves `WM_GETMINMAXINFO` is still wired
with a scaled floor, and `P` proves a 900 px haul stops at 200×140. A pass at
one level is not a pass at the other, and the row stays open until the levels
that matter have run.

### The waves

Waves are ordered by **dependency**, not alphabetically. Each assumes the ones
above it are green, because you cannot test the widget while composing if the
widget does not appear at all, and multi-monitor runs last because it is only
meaningful once every other row has finished.

| Wave | Name | Rows | Needs |
|---|---|--:|---|
| **0** | Host gate | — | nothing; runs on every commit |
| 1 | Windows and first run | 5 | a release build |
| 2 | The widget surface: hit-testing and geometry | 7 | wave 1 |
| 3 | Keyboard and focus | 5 | wave 2 |
| 4 | Compositing, tray, and the shell | 5 | wave 1 |
| 5 | Multi-monitor and DPI | 3 | waves 2–4 |
| 6 | Scale and responsiveness | 2 | a seeded library |

Wave 0 has no scenarios of its own. It is the set of rows a host test can close
outright, and [`project_integration_testing.md`](project_integration_testing.md)
tracks which those are. Run it before touching a probe at all.

The `Method` column says *what can verify a row*, not *what has*. Nothing in it
is a result. Only `reporting.md` records results, and a row moves to `PASS`
there and not here.

## Execution rules

1. One scenario is `IN PROGRESS` at a time.
2. **Hard limit: 10 minutes per task.** Stop, mark `TIMEOUT`, and report.
3. Every run starts from a release build, never from `flutter run`.
4. Never batch scenarios. A drag measured 60 px wrong looks identical to a drag
   measured 60 px right, so each row is measured alone.
5. On `FAIL`, reproduce once, fix one root cause, run the targeted regression,
   then continue.
6. **Never identify a WinNotes window by its size.** Match on title: `WinNotes`
   is the editor, `WinNotes Widget` is the widget. A previous probe left the
   widget wider than the editor and the editor minimised at `-32000`, and
   cheerfully measured the widget while believing it had the editor.
7. **Never conclude anything from a Z-order index.** `EnumWindows` order is not
   a Z-order once shell and ghost windows are in the list. Drive activation with
   real synthetic clicks and read `GetForegroundWindow()`.
8. A probe that prints a number has not verified a row. The row needs the
   *expected* number asserted, in `reporting.md`, against what the doc requires.

Rules 6 and 7 are the two that cost the most time. They are repeated here
because they are not obvious and the failure is silent.

---

## Wave 1 — Windows and first run

| ID | Method | Overview | Required states | Expected behavior | End result | Fix |
|---|---|---|---|---|---|---|
| WN-ENV-001 | P M | Record machine and build identity | release build present | Commit, version and Windows build are captured before anything else | NOT RUN | - |
| WN-ENV-002 | P | First launch, empty profile | a fresh `%TEMP%` dir via `WIN_NOTES_DATA_DIR` | The editor opens and `notes.json` appears in the overridden directory | NOT RUN | - |
| WN-ENV-003 | P | The real profile is not touched | a profile with real notes | Byte-for-byte identical before and after, by SHA-256 | NOT RUN | - |
| WN-ENV-004 | P D | The widget hides for an empty library | launched, then a note with text | No widget window before text exists; one small frameless window after | NOT RUN | - |
| WN-ENV-005 | P | Quit leaves no orphan | one surface running | No `win_notes` process survives the close; no handle leak across 20 restarts | NOT RUN | - |

## Wave 2 — Hit-testing and geometry

| ID | Method | Overview | Required states | Expected behavior | End result | Fix |
|---|---|---|---|---|---|---|
| WN-DRAG-001 | G P | A drag moves the widget by exactly the delta | anchored, 5 consecutive drags | `−60,0` px moves the window `−60,0` px; not rounded, not clamped | NOT RUN | - |
| WN-DRAG-002 | G P | The size floor holds | a 900 px haul on one edge | The window stops at exactly 200×140 logical and never below | NOT RUN | - |
| WN-DRAG-003 | G P | Every edge resizes | a grab band within reach of each edge | All four edges resize; the bottom-right corner resizes both | NOT RUN | - |
| WN-DRAG-004 | U P | A scroll wins over a drag mid-list | more content below | The list scrolls and the window does not move | NOT RUN | - |
| WN-DRAG-005 | U P | At the top, a downward drag moves the window | the list at offset 0 | The window moves; no rubber-banding of the list | NOT RUN | - |
| WN-DRAG-006 | U P | The lock refuses without moving | `positionLocked` on | The window does not move and the hint appears | NOT RUN | - |
| WN-DRAG-007 | U P | A press that does not move is not a drag | down, 2 px, up | Nothing is handed to the runner; no drag occurs | NOT RUN | - |

## Wave 3 — Keyboard and focus

| ID | Method | Overview | Required states | Expected behavior | End result | Fix |
|---|---|---|---|---|---|---|
| WN-KEY-001 | U G P | Compose mode drops `WS_EX_NOACTIVATE` | composing, then closed | The style bit is cleared on entry and restored on exit, read by `GWL_EXSTYLE` | NOT RUN | - |
| WN-KEY-002 | U G P | Focus returns where it came from | keyboard borrowed by the widget, then released | `GetForegroundWindow` names the window it was taken from, not the widget | NOT RUN | - |
| WN-KEY-003 | U P | `WM_MOUSEACTIVATE` defers to compose mode | a click while composing | The widget does not take activation; the caret stays in the field | NOT RUN | - |
| WN-KEY-004 | P | Typing reaches the field | the composer open | `SendInput` VK codes land as the intended characters, not as layout-derived ones | NOT RUN | - |
| WN-KEY-005 | U P | A torn-down composer gives the keyboard back | quit while composing | The runner releases the keyboard; no window is left holding it | NOT RUN | - |

## Wave 4 — Compositing, tray, and the shell

| ID | Method | Overview | Required states | Expected behavior | End result | Fix |
|---|---|---|---|---|---|---|
| WN-SYS-001 | D | Acrylic is applied, and only when asked | on, then off | The editor is translucent with acrylic on and opaque with it off | NOT RUN | - |
| WN-SYS-002 | D | The tray icon and its menu | running, then right-clicked | The icon is present; the menu opens and its items act | NOT RUN | - |
| WN-SYS-003 | D M | The global hotkey registers, and collides correctly | no collision, then a collision | The first instance takes the hotkey; a second is refused, not silently accepted | NOT RUN | - |
| WN-SYS-004 | D | Autostart writes and removes its own entry | on, then off | `HKCU\…\Run` holds one entry; removal leaves none | NOT RUN | - |
| WN-SYS-005 | P | A second launch activates the first | two launches in a row | One process, and the existing window comes forward rather than a second appearing | NOT RUN | - |

## Wave 5 — Multi-monitor and DPI

| ID | Method | Overview | Required states | Expected behavior | End result | Fix |
|---|---|---|---|---|---|---|
| WN-DPI-001 | D M | Scaling at 100 / 125 / 150 % | a monitor at each scale | The grab band and the size floor are in logical pixels at every scale | NOT RUN | - |
| WN-DPI-002 | D | Per-monitor position restore | moved to monitor B, quit, relaunch | The widget returns to monitor B at the same relative position | NOT RUN | - |
| WN-DPI-003 | D | Disconnecting the monitor it is on | monitor B removed | The widget moves somewhere reachable rather than off-screen | NOT RUN | - |

## Wave 6 — Scale and responsiveness

| ID | Method | Overview | Required states | Expected behavior | End result | Fix |
|---|---|---|---|---|---|---|
| WN-SCALE-001 | W M | A large library stays responsive | 2,000 notes, search as you type | No frame over 16 ms while scrolling; typing stays ahead of the keystroke | NOT RUN | - |
| WN-SCALE-002 | W M | The widget with a long card list | 200 notes with text | Scrolling stays within budget and memory does not climb per rebuild | NOT RUN | - |

**No Class C device matrix here, deliberately.** There is no low-RAM phone and
no OEM ROM. The equivalent risk on Windows — a compositor that drops frames, a
DWM that refuses acrylic — is a machine-specific fact, and the honest form of
this row is "run it on the machines you ship to", not a tier name.

## What no row in this file can establish

That the app is correct on **your** machine, with **your** graphics driver,
**your** DPI and **your** display topology. Every row above is a claim about the
build and the code. Rows WN-SYS-001 through WN-DPI-003 are the ones most likely
to differ on someone else's desktop, and they are `D` — by hand — for exactly
that reason.