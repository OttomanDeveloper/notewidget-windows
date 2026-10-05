# Platform Pattern - The Dart/Runner Contract

How Dart talks to `windows/runner/`, and what stops the two sides from disagreeing
without anyone noticing.

---

## 1. Architecture Overview

One `MethodChannel`, one Dart file, one C++ handler method. Everything else is
detail.

```
  ui/, state/, data/          platform/shell_channel.dart              windows/runner/
       │                              │                                      │
       │  no MethodChannel here ───────┤                                      │
       │                     ShellChannel                               │
       │                              │                                      │
       └──────────────────────────────┼──── 28 named methods ───────────────►│
                                      │                                      │
                                      ◄──── 6 `event.*` pushes ─────────────┘
```

`ShellChannel` is the only place a `MethodChannel` is constructed
(`AGENTS.md` §3, guard `layer_test`). This document is about the *contract* on top
of it: the names, the argument shapes, and what happens when a call fails.

---

## 2. The contract

28 methods, all of them declared in `platform_guard_test`'s
`platformMethodRegistry`. That test asserts the registry, the calls in
`shell_channel.dart`, and the runner's handler list are the same set — so this
table cannot drift away from the code without a red build.

| Method | Direction | Returns | Failure policy |
|---|---|---|---|
| `bootstrap` | out | `LaunchInfo?` map | `null` |
| `window.show` | out | — | swallowed |
| `window.hide` | out | — | swallowed |
| `window.focus` | out | — | swallowed |
| `window.setTitle` | out | — | swallowed |
| `widget.configure` | out | — | swallowed |
| `widget.setComposeMode` | out | — | swallowed |
| `widget.setGeometry` | out | — | swallowed |
| `widget.beginMove` | out | — | swallowed |
| `widget.beginResize` | out | — | swallowed |
| `widget.getBounds` | out | `NativeBounds?` | `null` |
| `note.create` | out | — | swallowed |
| `note.toggleCompleted` | out | — | swallowed |
| `shell.showEditor` | out | — | swallowed |
| `shell.showWidget` | out | — | swallowed |
| `shell.openSettings` | out | — | swallowed |
| `tray.notice` | out | — | swallowed |
| `path.open` | out | — | swallowed |
| `path.reveal` | out | — | swallowed |
| `editor.running` | out | `bool` | `false` |
| `app.quit` | out | — | swallowed |
| `dialog.confirmQuit` | out | `bool` | `false` |
| `autostart.query` | out | `bool` | `false` |
| `autostart.set` | out | `bool` | `false` |
| `hotkey.register` | out | `HotkeyRegistration?` | `null` |
| `path.pickFolder` | out | `String?` | `null` |
| `path.pickFile` | out | `String?` | `null` |
| `path.saveFile` | out | `String?` | `null` |

Inbound, runner to Dart, on the same channel: `event.hotkey`,
`event.openSettings`, `event.toggleCompleted`, `event.createNote`,
`event.geometry`, `event.visibility`. These are **not** in the outbound registry
and a test asserts the two sets are disjoint — they share one channel, which is
exactly why they are easy to confuse.

---

## 3. The rules

### 3.1 The method list is declared, in one place, and checked three ways

Adding a method means three edits: the registry in `platform_guard_test`, §2 above,
and the runner's handler. The test fails on any of:

- declared but never called from Dart (aspirational, not a contract),
- called but not declared (**the silent no-op** — see §4.1),
- declared but not handled by the runner.

The doc and the registry are also checked against each other. A name that exists
only in the test file is a private convention, not a contract.

The scanner that finds the calls matches **all four** dispatch idioms and runs
over joined text rather than line by line. Both details are load-bearing; see §4.2.

### 3.2 `bootstrap` is the only name without a namespace

Twenty-seven names are `namespace.verb`. `bootstrap` is bare, because it was
written first and the runner compares on the literal. It stays — renaming it would
be a change to a shipped contract for tidiness — but it is the one name a newcomer
will copy by accident, and §2 records it.

### 3.3 Pick the failure policy deliberately, from the table

Every method above declares what it does when the runner refuses. Four idioms
currently reach the channel and only two are helpers:

| Idiom | On `PlatformException` | Use for |
|---|---|---|
| `_fire('name')` | swallowed | conveniences: window, tray, gesture hand-off |
| `_invoke('name')` | returns `null` | anything whose answer is a value |
| `methodChannel.invokeMethod<T>` | hand-rolled per call | **avoid — see §4.3** |
| `methodChannel.invokeMapMethod<T,V>` | hand-rolled per call | **avoid — see §4.3** |

A failed `_fire` is not a bug. Making the widget disappear because a tray balloon
could not be shown would be worse than the missing balloon.

### 3.4 Arguments are an untyped map, so the key is the contract

Arguments go across as `Map<String, dynamic>`, and the runner reads keys by hand.
There is no schema and no check on either side. So:

- the keys in §2's Dart signature are the keys the runner must read, and
- a renamed key is a silent no-op, exactly like a renamed method.

`widget.beginMove` / `beginWidgetResize` carry `anchorX`/`anchorY`; those two names
are load-bearing for the drag arithmetic in `docs/widget_pattern.md` §3.3, and a
typo in either would leave the widget unmovable with no error anywhere.

### 3.5 Events arrive through `setMethodCallHandler`, not an `EventChannel`

The runner pushes with `InvokeMethod` on the *same* channel Dart calls out on, so
they arrive via `setMethodCallHandler`. An `EventChannel` here would silently
receive nothing — no error, no events, a hotkey that never fires. `ShellEvent.
fromMethod` decodes them by string switch.

### 3.6 `ShellEvents.instance` is a process-wide singleton

One stream controller for the whole isolate, installed once. It is a known
property rather than an oversight; §4.4 says why it is acceptable and what would
have to change. A test asserts it is *still* a singleton, so it cannot be changed
without the doc being updated in the same commit.

---

## 4. The traps

### 4.1 A method added on one side only is a silent no-op

`result->Success()` is returned either way, so the Dart `await` completes and
nothing happens. No exception, no log, no test failure. This is why §3.1 is a
declared registry and not the `AGENTS.md` §3 sentence it replaces.

### 4.2 The scan has to see a name on the next line

The original `dartMethodNames` matched `_fire(` and `_invoke(` **line by line**.
`_fire(\n  'widget.beginResize',\n  {...})` has its name on the following line, so
it was invisible. Five real methods were never parity-checked as a result:
`dialog.confirmQuit`, `path.pickFile`, `path.pickFolder`, `path.saveFile` and
`widget.beginResize`.

All five are handled by the runner, so no code was wrong. But the guard was
reporting on 19 of 24 methods and calling that parity — and its own
`greaterThan(15)` assertion passed *partly because* of what it missed. A floor
assertion is not evidence that a scan is complete.

`\s` matches a newline in a Dart RegExp, so matching against joined text rather
than lines is the entire fix. `platform_guard_test` pins it with
*the scan covers all four dispatch idioms*.

### 4.3 Seven methods bypass the helpers

`bootstrap`, `autostart.query`, `autostart.set`, `hotkey.register`, `dialog.
confirmQuit`, `path.pickFolder`, `path.pickFile` and `path.saveFile` call
`methodChannel.invokeMethod` / `invokeMapMethod` directly, each with its own
hand-rolled `try`. So the failure policy in §3.3 is not enforced anywhere — it is
re-decided at each call site by which idiom the author reached for.

One of them is inconsistent: `confirmQuit` catches `PlatformException` but **not**
`MissingPluginException`, unlike every neighbour. Under `flutter test`, where there
is no runner, that one throws where the others return `false`.

Consolidating them into `_invoke` is a small, safe change and is left for the
migration pass; recording it here is what stops it being rediscovered as a bug.

### 4.4 The event singleton, and what would have to change

`ShellEvents.instance` is reachable from anywhere, so a test cannot substitute a
fake event stream. It survives because each isolate has exactly one runner and
exactly one channel, and because the alternative — an `EventChannel` — is worse
(§3.5). What would change it: a second channel, or a widget test that needs to
drive a hotkey. Until then it is a fact, not a defect.

---

## 5. Adding work

1. Add the handler in `windows/runner/`, matching on `method == "your.name"`.
2. Add the Dart method in `shell_channel.dart` using `_fire` or `_invoke`
   **per §3.3**.
3. Add the name to `platformMethodRegistry`.
4. Add the row to §2, with its failure policy.
5. Add an inbound event to `inboundEvents` too, if the runner pushes one.

Skip step 3 or 4 and the guard says so by name.

---

## 6. Layer isolation

`platform/` owns `MethodChannel`. No file in `ui/`, `state/` or `data/` constructs
one; they call `ShellChannel`. `layer_test` fails on any that does, and on any
method called from Dart that the runner does not handle.

---

## 7. Tests

| § | Rule | Pinned by |
|---|---|---|
| 3.1 | Contract declared three ways | **guard** `platform_guard_test` · *registry, Dart calls and runner handlers all agree*; *the registry names exactly what the runner handles*; *the doc lists the same 28 names the registry does*; *an inbound event in the outbound registry is a fault*; *a method called but not declared is a fault*; *a declared method the runner ignores is a fault*; *an empty registry is a fault, not a pass* |
| 3.2 | `bootstrap` is un-namespaced | **guard** `platform_guard_test` · *the doc lists the same 28 names the registry does* |
| 3.3 | Failure policy is chosen, not inherited | `layer_test`; no test — the seven bypassing methods are `docs/platform_pattern.md` §4.3 |
| 3.4 | Argument keys are the contract | `layer_test`; no test — the map is untyped on both sides |
| 3.5 | Events use a method-call handler | `layer_test` · *every method called from Dart is handled by the runner* |
| 3.6 | `ShellEvents` is a singleton | **guard** `platform_guard_test` · *ShellEvents is still a process-wide singleton, and that is named* |
| - | A name on the next line is still seen | **guard** `platform_guard_test` · *the scan covers all four dispatch idioms*; `layer_test` · *every method called from Dart is handled by the runner* |
| 3.1 | The two directions stay disjoint | **guard** `platform_guard_test` · *the two directions have separate namespaces* |

---

## 8. Guarantees

- 28 outbound methods, declared in one place, agreed by both sides, checked in CI.
- 6 inbound events, provably disjoint from the outbound set.
- Adding a method on one side only is a red build, not a silent no-op.
- Every method's behaviour on failure is written down before it is written.

The seven methods that bypass the helpers (§4.3) are the known gap. It is
recorded, it is harmless today, and it is not in §8's guarantees.