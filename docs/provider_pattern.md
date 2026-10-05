# Provider Pattern - Riverpod, `ref`, and the End of `setState`

How shared state is created, read, and rebuilt in WinNotes, and why the widget tree
does not receive it by constructor.

---

## 1. Architecture Overview

```
  main()                    runs once per isolate; branches on the surface
    │
    ├── runApp(EditorApp) ──┐
    └── runApp(WidgetApp) ──┤
                            │  each root owns a ProviderScope
                            ▼
       ProviderScope
         ├── shellProvider          ShellChannel        (platform/)
         ├── appPathsProvider       AppPaths            (core/)
         ├── notesRepositoryProvider     NotesRepository   (data/)
         ├── settingsRepositoryProvider  SettingsRepository(data/)
         ├── notesProvider           Notifier<NotesState>
         ├── settingsProvider        Notifier<Settings>
         └── widgetProvider          Notifier<WidgetState>   (widget only)
                            │
                            ▼
       ConsumerWidget / ConsumerStatefulWidget  ── ref.watch / ref.read
```

Two surfaces, two isolates, two scopes. They never share a provider instance and
must not — they share **files**, which is `PROJECT.md`'s decision, not a provider
decision. `docs/isolate_pattern.md` owns that boundary; this document owns what
happens inside one scope.

---

## 2. `watch`, `read`, and what they cost

| | Rebuilds the widget | Use for |
|---|---|---|
| `ref.watch(p)` | yes, when `p` changes | anything the widget *draws* |
| `ref.select(p, (s) => s.foo)` | yes, only when `foo` changes | a slice of a big state |
| `ref.read(p)` | no | an action: a button handler, `initState` |

The rule that matters: **if it is drawn, it was watched.** Reading something you
draw is how a widget shows stale data until something else happens to rebuild it,
and that is not a bug anyone reports — it is a bug nobody notices.

`ref.select` is the narrowness tool. The note list watches a projection of the
notes provider, not the provider itself, so typing in one note's body does not
rebuild the list of every note.

---

## 3. The rules

### 3.1 A provider constructs; a widget reads

Nothing under `lib/src/ui/` constructs a repository or a controller. There are 10
such sites today, in two files, and they are the reason the two surfaces have
drifted: `_resolveBrightness` exists in three copies across `EditorApp` and
`WidgetApp`, and they disagree about what "system" brightness means when no system
brightness has been reported. That is what duplication of construction looks like
once nobody is watching.

Consequence worth stating: a repository that changes its constructor is **one
edit**, not two.

### 3.2 Each isolate gets its own container

`main()` runs once per isolate. Both surfaces call it, and it branches on
`launch.isWidgetSurface`. So a `ProviderScope` belongs inside each root, never
above the branch and never in `main()`.

This is the single largest trap in the whole migration. Wrapping `runApp` in
`ProviderScope` in `main()` looks right and builds the container twice — which is
correct — while hiding the boundary the rest of this document depends on. The
per-isolate rule is asserted by
*main() still branches rather than being given both surfaces*.

### 3.3 Providers are `Notifier`, not `ChangeNotifier`

The three controllers in `lib/src/state/` are `ChangeNotifier` subclasses totalling
989 lines. They are being rewritten as Riverpod notifiers, not wrapped.

The reason is `AsyncValue`, and it pays for the rewrite:

- `NotesController.corrupt` (`notes_controller.dart:61`) is a hand-rolled error
  field, read in four places and rendered by `EditorView` at `editor_view.dart:50`.
  As an `AsyncNotifier` it is `AsyncError.error` — the same information, with the
  loading state that currently does not exist yet.
- `EditorView._busy` (`editor_view.dart:305`), checked at 8 call sites to disable
  buttons while a recovery runs, becomes `isLoading`.
- `WidgetApp._ready` (`widget_app.dart:46`) becomes `isLoading`.

That is 3 of the 24 `setState` sites removed by a state-model change rather than a
mechanical rewrite, which is most of the argument for doing it this way.

A `ChangeNotifier` wrapped in `ChangeNotifierProvider` would have been about a day
instead of a week. It was rejected because it keeps the hand-rolled loading and
error state this document is trying to delete.

### 3.4 `setState` is gone, and there are two replacements, not one

No excuse is accepted (`AGENTS.md` §0.7). The choice is between:

| The state is | Replacement | Example |
|---|---|---|
| shared, outlives the widget | a provider | `_busy`, `_ready`, `_showListOnNarrow`, `_narrowShowsPreview` |
| genuinely ephemeral | a `ValueNotifier` + `ValueListenableBuilder` | `_hovering`, `_lockedHint`, `_composing`, `_pending` |

The dividing line is **lifetime**, not importance. `_hovering` is not
unimportant, but it is true for one frame and nobody else will ever ask; `_busy`
is true for the length of an await and a button six rows away has to know.

`widget_surface.dart:49` already does this once, for thumb opacity. The pattern is
in the tree.

The `State` class is not deleted. It stays as the disposal shell — for a
`TextEditingController`, a `ScrollController`, a `FocusNode`. What it must not do
is hold a bool that a provider could hold, because that is `setState` with extra
steps.

**A `State` may still hold ephemeral fields, read through a `ValueNotifier`, and
never call `setState`.** That is the whole of the remaining freedom, and
`ValueListenableBuilder` is what renders it.

### 3.5 No widget receives a dependency by parameter

Below a `ProviderScope`, a widget reads state with `ref`. 23 constructor
parameters do this by hand today, 13 of them in `settings_dialog.dart`.

What is still allowed to cross a boundary as a parameter is **a value**: an
`int index`, a `String path`, a `void Function()` callback. What is not allowed is
anything that holds state — a controller, the shell channel, a settings object.

This rule is about *where state comes from*, not about which package is
installed. That is deliberate: it means the rule survives a change of state
management library, and it means the guard has something to say today, before
Riverpod is in `pubspec.yaml`.

### 3.6 A provider is small enough to read in one sitting

`hellobiller` caps its providers and splits anything larger into a main provider
plus satellites. The same cap here, at **200 lines** per provider file.

`NotesController` is 482 lines and `WidgetController` is 376. Both will be split
rather than migrated whole — `notesRepositoryProvider`, `notesProvider` for the
list and selection, and a separate one for recovery — because a 482-line provider
is not a unit you can test, and the corrupt-file recovery is exactly the part that
needs a test of its own.

### 3.7 Repositories are plain classes; controllers are providers

`data/` stays as it is: plain classes over `AtomicJsonFile`, constructed by
providers, injected into them. The one-writer-per-file rule in
`docs/storage_pattern.md` is unchanged and is not a provider concern.

---

## 4. Adding work

1. Put the state in a provider, not in a `State`.
2. `ref.watch` it where it is drawn. `ref.read` it in handlers.
3. If a widget needs it, do not add a parameter — add a `ref.watch`.
4. Keep the provider under 200 lines; split before you cross it.
5. Remove the `setState` budget line you just emptied, or the guard goes red.

---

## 5. What Riverpod does not do here

Recorded so nobody discovers it later and thinks the migration was a mistake:

- **It does not cross the isolate boundary.** Two containers, no shared instances.
  `PROJECT.md`'s one-writer-per-file rule is untouched.
- **It does not help `markdown_text.dart` (1072 lines) or `widget_surface.dart`
  (841 lines).** Together they are 38% of `lib/`, both are pure UI, and neither
  moves.
- **It does not fix the unawaited flush in `dispose()`.** `ref.onDispose` is
  synchronous and cannot await; the four existing `unawaited(...flush())` calls
  are a pre-existing hazard with its own entry in `docs/isolate_pattern.md` §5.
- **Prop-drilling savings are smaller here than in hellobiller.** This tree is
  shallow — `MaterialApp → EditorView → panes`. The real win is deleting a
  duplicated bootstrap, not flattening a deep tree.

---

## 6. Layer isolation

```
ui/  ──>  state/  ──>  data/  ──>  core/
 └─────────┴───────────┴──>  platform/shell_channel.dart
```

Unchanged from `AGENTS.md` §3. Providers live in `state/` and are constructed from
it; `ui/` never reaches past `state/` to build one.

---

## 7. Tests

| § | Rule | Pinned by |
|---|---|---|
| 3.1 | Providers construct; widgets read | **guard** `isolate_guard_test` · *no widget constructs a dependency beyond the recorded countdown*; *construction in a third file is a fault*; *the two roots are named, and they are the two roots* |
| 3.2 | One container per isolate | **guard** `isolate_guard_test` · *main() still branches rather than being given both surfaces* |
| 3.3 | Notifier, not ChangeNotifier | `notes_controller_test`; no new test until the rewrite lands |
| 3.4 | No `setState` | **guard** `no_set_state_test` · *lib/ has no setState beyond the recorded countdown*; *a new setState is a fault*; *one more in a counted file is a fault*; *one fewer is also a fault, and says why*; *a file emptied completely has its budget line removed*; *the scanner counts a setState wherever it is written*; *a name containing setState is not a setState call* |
| 3.5 | No dependency by parameter | **guard** `provider_guard_test` · *lib/src/ui has no injected state beyond the recorded countdown*; *a new injected parameter is a fault*; *a removed parameter has its budget line taken out*; *a value type passed as a parameter is not a fault*; *a widget holding state by parameter is a fault*; *a load result is not an injected dependency*; *the budget names every file that currently injects* |
| 3.6 | A provider is under 200 lines | **manual** — no provider exists to measure yet; the cap is checked by `dart analyze` file sizes at review |
| 3.7 | Repositories stay plain | `storage_guard_test` |

---

## 8. Guarantees

- 24 `setState` sites, each on a per-file countdown that falls in both directions.
- 23 injected parameters, same mechanism.
- 10 constructions in widgets, same mechanism.
- Both surfaces build the same graph from the same declarations.
- One direction of failure per channel call, written down before it is written.

Not guaranteed, and recorded rather than hidden: the seven methods in
`docs/platform_pattern.md` §4.3 that bypass their helpers, and the unawaited
flushes in `docs/isolate_pattern.md` §5.