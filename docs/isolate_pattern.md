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

This used to be a divergence: ten constructions sat in `lib/src/ui/`, five in
`EditorApp` and five in `WidgetApp`, in `StatefulWidget`s whose `initState` built
four repositories, loaded settings, wired an event subscription, and whose
`dispose` flushed some of them in an order that mattered. There are **none** now.

The duplication was not stylistic. `_resolveBrightness` existed in **three** copies
across the two files — `editor_app.dart:241`, `widget_app.dart:108` and
`widget_app.dart:153` — and they disagreed: the editor fell back to a live
`_systemBrightness` field, the widget hardcoded `Brightness.light`. Two surfaces
that resolved "system" brightness differently would theme differently, and the only
symptom would be a widget that looks wrong after a Windows theme change.

That is fixed rather than recorded. `lib/src/state/providers.dart` holds the
declarations, both roots read `widgetSurfaceThemeProvider`, and
`isolate_guard_test` fails if either root grows a `_resolveBrightness` of its own —
matching a declaration rather than a mention, because both files *name* the old
function in a comment saying it is gone.

Both roots build the same graph from the same declarations. See
`docs/provider_pattern.md` §3.1.

### 3.2 `main()` branches, and owns the scope

`main()` is shared, so it must not hold per-surface state. It reads `bootstrap()`,
builds `AppPaths`, and branches on `launch.isWidgetSurface`.

**The scope is built here, above the branch.** That is a change from what this
document originally said, and the earlier reasoning was wrong. Keeping the scope
inside each root would have meant each root received the channel, the launch info
and the paths as constructor parameters — three parameters on both roots, which is
`AGENTS.md` §0.8 with an exception written into it. Putting the three into one
`ProviderScope` is what lets both roots take **no parameters at all**.

The "that would build the container twice" objection does not apply: `main()` runs
once per isolate, so each isolate builds exactly one container over its own channel.
The boundary this document depends on is per-isolate, not per-widget, and it is
unchanged. What is gone is the duplicated construction, not the isolation.

### 3.3 The DI root must not also own the `MaterialApp`

This is fixed. `editor_app.dart` used to carry a `GlobalKey<NavigatorState>` and a
comment explaining why: the State's own `context` sits **above** the `MaterialApp` it
returns, so it has no `Navigator` ancestor and `showDialog(context: context)`
throws rather than showing anything.

The comment said "that is why Settings appeared to do nothing", and it was right
about the symptom. It was not the cause. The cause was that one widget was both the
dependency-injection root and the application root, so its context was stranded
above the navigator. `navigatorKey` was a patch for that.

Both are gone. Construction moved into providers, and `EditorApp` became a
`ConsumerWidget` whose only job is to return the `MaterialApp` — so the widget that
opens the settings dialog sits below the `Navigator` like anything else, and
`openSettings(context, ref)` is called from a context that works. The `GlobalKey`
was not "kept for the genuine reason it is needed"; there was no such reason, and
carrying it forward would have been keeping a workaround for a cause that no longer
exists.

`EditorEventRouter` is the one place that genuinely needs a context below the
`MaterialApp`, and it is there rather than in the root — which is why `EditorHome`
exists as a separate widget below it.

### 3.4 Events are routed by the runner, never by both surfaces acting

Each root subscribes to `shell.events` and **switches on the kind**. The widget
explicitly breaks on `toggleCompleted` and `createNote`, with the reason written
down: those are requests addressed to the editor, and acting on them here would
put two writers on one file — the exact thing the routing prevents.

The subscription lives in a `ConsumerState` with a `StreamSubscription` field, not
in `build`. A bare `shell.events.listen` in `build` stacks a listener per rebuild,
and the symptom of that is a hotkey that raises the editor six times.

Both routers check `mounted` before touching `ref` or `context`, because an event
can arrive during teardown. See `docs/provider_pattern.md` §3.8.

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
| 3.1 | Construction lives in a provider | **guard** `isolate_guard_test` · *no widget constructs a repository or a controller*; *the scanner still finds the six types it claims to*; *both roots read the same providers, from the same declarations*; *the theme provider is under ui/, not state/*; **manual** - build a release, change the Windows theme while both surfaces are open |
| 3.2 | `main()` branches and owns the scope | **guard** `isolate_guard_test` * main() builds the scope and passes no state to either root*; **manual** - a probe reading both windows at once |
| 3.3 | The DI root is not the app root | **manual** - a probe driving the Settings menu and asserting a dialog appears. The `GlobalKey` that patched it is gone and no guard asserts its absence, because a check for "this workaround must not come back" is only worth having next to a reason it might. |
| 3.4 | Events routed, never double-handled | `widget_integration_test`; **manual** - completing a note in the widget and asserting one write |
| 3.5 | Observers are removed | `storage_guard_test` |
| - | No `ref` inside `dispose`, in either root | **guard** `isolate_guard_test` * the flush-on-teardown hazard is still named* |
| - | The flush hazard stays named | **guard** `isolate_guard_test` * the flush-on-teardown hazard is still named* |

---

## 8. Guarantees

- Two isolates, one `main()`, no second entrypoint to drift.
- One writer per file, with `selection.json` the single declared exception.
- **Zero** constructions in `lib/src/ui/`. The ten that were there are in
  `lib/src/state/providers.dart`, and both surfaces build the same graph from them.
- **One** `_resolveBrightness` — it is `widgetSurfaceThemeProvider`, and a guard
  fails if either root grows another.

Not guaranteed: §4.3. The unawaited flushes are a live hazard, they are not new,
and this document does not claim otherwise.