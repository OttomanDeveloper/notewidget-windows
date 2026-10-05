# Isolate Pattern - Two Surfaces, One `main()`, and What Must Not Cross

WinNotes runs two Flutter engines in one process. Each has its own isolate, its own
widget tree, and its own `main()`. This document is about that boundary, and about
the duplication that grew up on either side of it.

---

## 1. Architecture Overview

```
                 windows/runner/  (one process, two windows, two engines)
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
        editor isolate                widget isolate
        runApp(EditorApp)             runApp(WidgetApp)
              │                           │
        writes notes.json            reads notes.json
        writes settings.json         reads settings.json
        writes selection.json        reads selection.json   ← the only file both touch
                                        writes widget_state.json
```

The runner creates two windows, each with its own Flutter engine, and **both call
`lib/main.dart`**. `--surface` decides which. That is why there is no second
entrypoint to keep in sync.

What crosses the boundary is files, and only files. That is `PROJECT.md`'s
decision and it is not revisited here.

---

## 2. Who owns what

| | editor | widget |
|---|---|---|
| `notes.json` | **writes** | reads, watches |
| `settings.json` | **writes** | reads, watches |
| `selection.json` | **writes** | **writes** — the one exception, and it is deliberate |
| `widget_state.json` | reads | **writes** |
| hotkey, tray, autostart, single instance | owns | asks the editor |

`selection.json` has two writers because it is a single value — which note is
selected — that both surfaces must agree on immediately, and a file is cheaper than
a channel. Everything else has exactly one writer, and `docs/storage_pattern.md`
§3.1 is the rule that says why.

The widget never writes a note. When the user completes a note in the widget, the
widget sends `note.toggleCompleted` to the runner, the runner routes it to the
editor, and the editor writes. The widget then sees the change through the directory
watcher it already uses for everything else. That is not indirection for its own
sake: it means a note is written in the same place every other edit is made.

---

## 3. The rules

### 3.1 Construction lives in a provider, not in a root widget

Ten constructions sit in `lib/src/ui/` today: five in `EditorApp`, five in
`WidgetApp`. Both roots are `StatefulWidget`s whose `initState` builds four
repositories, loads settings, wires an event subscription, and whose `dispose`
flushes some of them in an order that matters.

That duplication is not stylistic. `_resolveBrightness` exists in **three** copies
across the two files — `editor_app.dart:241`, `widget_app.dart:108` and
`widget_app.dart:153` — and they disagree: the editor falls back to a live
`_systemBrightness` field, the widget hardcodes `Brightness.light`. Two surfaces
that resolved "system" brightness differently would theme differently, and the only
symptom would be a widget that looks wrong after a Windows theme change.

Both roots must build the same graph from the same declarations. See
`docs/provider_pattern.md` §3.1.

### 3.2 `main()` branches; each root owns its own scope

`main()` is shared, so it must not hold per-surface state. It reads
`bootstrap()`, builds `AppPaths`, and branches on `launch.isWidgetSurface`.

Each root then creates its own `ProviderScope`. Not above the branch — that would
build the container twice, which is harmless, while hiding the boundary the rest of
this document depends on.

### 3.3 The DI root must not also own the `MaterialApp`

`editor_app.dart:249-256` carries a `GlobalKey<NavigatorState>` and a comment
explaining why: the State's own `context` sits **above** the `MaterialApp` it
returns, so it has no `Navigator` ancestor and `showDialog(context: context)`
throws rather than showing anything.

The comment says "that is why Settings appeared to do nothing", and it is right
about the symptom. It is not the cause. The cause is that one widget is both the
dependency-injection root and the application root, so its context is stranded
above the navigator. `navigatorKey` is a patch for that.

Moving construction above `MaterialApp` deletes the cause. The key stays only for
the genuine reason it is needed — a context that is genuinely below the `Navigator`
for `ScaffoldMessenger` and `showDialog` calls made from outside the tree.

### 3.4 Events are routed by the runner, never by both surfaces acting

Each root subscribes to `shell.events` and **switches on the kind**. The widget
explicitly breaks on `toggleCompleted` and `createNote`, with the reason written
down: those are requests addressed to the editor, and acting on them here would
put two writers on one file — the exact thing the routing prevents.

That `break` is a rule, not a shrug. A future event that arrives at the wrong
surface should be ignored loudly in a test, not silently.

### 3.5 One `WidgetsBindingObserver` per root, removed on dispose

Both roots add themselves in `initState` and remove themselves in `dispose`. With a
provider holding the graph, brightness changes are a `ref.listen` on
`platformBrightness` rather than an observer — but the requirement does not change:
whoever registers must unregister, and the widget surface in particular must not
keep reacting to a binding it has left.

---

## 4. The traps

### 4.1 `dart:io` in an isolate is per-isolate

Each isolate has its own `Directory`, its own watcher, its own file handles. A
`StreamSubscription` on a directory watcher in the editor isolate has no
relationship to one in the widget isolate. Two watchers on the same directory is
correct here, not a duplicate.

### 4.2 The `ShellEvents` singleton is per-isolate, not per-process

Despite the name, each isolate has its own Dart heap, so each gets its own
`ShellEvents.instance`. There is no cross-isolate event bus and there must not be —
it would reintroduce exactly the shared-state coupling the file-based design
removes.

### 4.3 `flush()` on teardown is a real hazard, not a formality

`docs/storage_pattern.md` §3.11 says never lose a data file. The four
`unawaited(...flush())` calls in the two `dispose()` methods are an unawaited async
write in a teardown whose isolate is about to end.

Two things follow, and both matter for the migration:

- **This is pre-existing.** It is not caused by any provider work and should not be
  bundled into it as a drive-by fix.
- **`ref.onDispose` cannot fix it.** Riverpod's disposal hook is synchronous. An
  async flush moved into it would be dropped exactly as it is today.

The fix is not a `dispose` hook at all — it is making the write durable at the point
it happens rather than at teardown, which is a `storage_pattern.md` question.
Recorded here so it is not lost between two documents that both touch `dispose`.

---

## 5. Adding work

1. New surface? It gets its own isolate, its own root, its own scope — and it
   declares in §2 which files it writes. A second writer is a design change, not a
   default.
2. New event? Add it to the inbound set in `docs/platform_pattern.md` §2, and
   decide in **both** roots what the wrong surface does. The widget's `break` is
   the pattern to copy.
3. New shared state across surfaces? It goes in a file. There is no channel and no
   provider answer.

---

## 6. Layer isolation

Providers are per-isolate; repositories are not. `data/` holds no isolate-aware
code, which is why the same `NotesRepository` class serves both surfaces with
different `watchExternal` settings.

---

## 7. Tests

| § | Rule | Pinned by |
|---|---|---|
| 3.1 | Construction lives in a provider | **guard** `isolate_guard_test` · *no widget constructs a dependency beyond the recorded countdown*; *construction in a third file is a fault*; *the two roots are named, and they are the two roots*; **manual** - build a release, change the Windows theme while both surfaces are open |
| 3.2 | `main()` branches, each root scopes | **guard** `isolate_guard_test` · *main() still branches rather than being given both surfaces*; **manual** - a probe reading both windows at once |
| 3.3 | The DI root is not the app root | **manual** - a probe driving the Settings menu and asserting a dialog appears |
| 3.4 | Events routed, never double-handled | `widget_integration_test`; **manual** - completing a note in the widget and asserting one write |
| 3.5 | Observers are removed | `storage_guard_test` |
| - | The flush hazard stays named | **guard** `isolate_guard_test` · *the flush-on-teardown hazard is still named* |

---

## 8. Guarantees

- Two isolates, one `main()`, no second entrypoint to drift.
- One writer per file, with `selection.json` the single declared exception.
- 10 constructions in widgets, each on a per-file countdown.
- Three copies of `_resolveBrightness` recorded as the reason §3.1 exists.

Not guaranteed: §4.3. The unawaited flushes are a live hazard, they are not new,
and this document does not claim otherwise.