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

The three controllers in `lib/src/state/` were `ChangeNotifier` subclasses totalling
989 lines. They are now Riverpod `AsyncNotifier`s — rewritten, not wrapped.

The reason was `AsyncValue`, and it paid for the rewrite:

- `NotesController.corrupt` was a hand-rolled error field, read in four places and
  rendered by `EditorView`.
- `EditorView._busy`, checked at 8 call sites to disable buttons while a recovery
  ran, became `isLoading`.
- `WidgetApp._ready` became `isLoading`.

**One prediction did not hold, and the code says so.** `corrupt` is *not*
`AsyncError.error`. A file that cannot be read is a state this app *recovers from*
rather than an exception it propagates — there is a whole recovery screen for it,
with three actions and per-outcome advice — so modelling it as a thrown error would
mean every reader had to know it is special. It is a field on `NotesState`, and
`isReadOnly` is what the mutations check. `isLoading` and `hasValue` come from the
`AsyncValue` around it, which is where the debounced watcher re-reads show up.

A `ChangeNotifier` wrapped in `ChangeNotifierProvider` would have been about a day
instead of a week. It was rejected because it keeps the hand-rolled loading and
error state this document is trying to delete.

### 3.4 `setState` is gone, and there are two replacements, not one

No excuse is accepted (`AGENTS.md` §0.7). The choice is between:

| The state is | Replacement | Example |
|---|---|---|
| shared, outlives the widget | a provider | `_busy`, `_ready`, `_showListOnNarrow`, `_narrowShowsPreview` |
| genuinely ephemeral | a `ValueNotifier` + a listener | `_hovering`, `_lockedHint`, `_composing`, `_pending` |

The dividing line is **lifetime**, not importance. `_hovering` is not
unimportant, but it is true for one frame and nobody else will ever ask; `_busy`
is true for the length of an await and a button six rows away has to know.

**A `ValueNotifier` does not rebuild anything.** This is the one thing the
migration got wrong four times, and it is worth stating as its own rule because
nothing about it is visible in the code. `setState` did two jobs: it held a value
*and* it rebuilt the widget. A `ValueNotifier` only does the first, so replacing
one with the other produces a field that compiles, analyzes clean, passes every
test that does not happen to look at the result, and does nothing.

What each of the four looked like:

- `note_editor_pane.dart` — the Preview button read `_narrowShowsPreview.value`
  outside the builder that wrapped the pane, so the label never changed. The button
  now takes the flag as a parameter, so there is no second reader to drift.
- `widget_surface.dart` — `_lockedHint` had no listener at all, so a refused drag
  said nothing. Three notifiers there are now merged into one
  `ListenableBuilder(listenable: Listenable.merge([...]))`.
- `settings_dialog.dart` — `_pending` had no listener, so the hotkey capture
  dialog kept showing the combination it opened with, with "Use this" disabled.
- `editor_view.dart` — `_busy` was read by eight button callbacks in a build with
  no listener, so recovery buttons never disabled themselves.

`no_set_state_test` fails on a file that declares a `ValueNotifier` and contains no
listener at all. It is coarse — it cannot prove *which* notifier is wired — and it
is not claiming to. It is claiming the replacement was used as a replacement rather
than as a field.

The `State` class is not deleted. It stays as the disposal shell — for a
`TextEditingController`, a `ScrollController`, a `FocusNode`. What it must not do
is hold a bool that a provider could hold, because that is `setState` with extra
steps.

### 3.5 No widget receives a dependency by parameter

Below a `ProviderScope`, a widget reads state with `ref`. 23 constructor
parameters used to do this by hand, 13 of them in `settings_dialog.dart`. There are
none now.

What is still allowed to cross a boundary as a parameter is **a value**: an
`int index`, a `String path`, a `void Function()` callback. What is not allowed is
anything that holds state — a controller, the shell channel, a settings object.

The two per-widget resources that used to trip this are named for what they are:
`WidgetSurface`'s scroll is `scroll`, and the composer field is `field`. Neither is
shared state; both are created, passed and disposed by the widget that owns them.

**A plain class may hold a notifier, and two do.** `EditorBootstrap` and
`EditorTeardown` in `editor_app.dart` take notifiers as constructor parameters,
because a `WidgetRef` cannot survive an `await` or be read inside `dispose` — see
§3.8. The rule is about *widgets*, so the guard decides "is this a widget" from the
nearest preceding `class` line. That is an approximation and it is stated in
`guards.dart`; it would be wrong in a codebase whose classes nest.

### 3.6 A provider is small enough to read in one sitting — and two are not

`hellobiller` caps its providers and splits anything larger into a main provider
plus satellites. The same cap here, at **200 lines** per provider file.

**The migration did not meet it, and the honest reason is ordering.** The two
large files were the two the rewrite had to get right first, and the split was
written as a follow-up rather than as part of the same change:

| File | Lines | Over by |
|---|---|---|
| `settings_controller.dart` | 187 | — |
| `providers.dart` | 133 | — |
| `widget_controller.dart` | 413 | 213 |
| `notes_controller.dart` | 621 | 421 |

The split that was intended for notes is `notesProvider` for the list, selection
and search, and a separate one for corrupt-file recovery — because recovery is the
part that most needs a test of its own, and it currently cannot have one without
also constructing the whole list.

It is in `AGENTS.md` §4 as a divergence rather than quietly reworded here, because
lowering the cap to 650 to match the code would make this section a description of
what happened instead of a rule.

What *is* enforced is the direction that was still open. A cap nobody checks is a
number in a document, and two files over it is a very short way from being three —
so `provider_guard_test` fails on a **third**, and fails again if either of the two
recorded files comes under the cap without the record being updated in the same
change. That makes the breach bounded rather than fixed: it cannot widen while
someone is working on the split, and it cannot be quietly forgotten after.

### 3.7 Repositories are plain classes; controllers are providers

`data/` stays as it is: plain classes over `AtomicJsonFile`, constructed by
providers, injected into them. The one-writer-per-file rule in
`docs/storage_pattern.md` is unchanged and is not a provider concern.

### 3.8 A `WidgetRef` has a short life

Riverpod invalidates a `WidgetRef` in two situations, and both throw
`Bad state: Using "ref" when a widget is about to or has been unmounted`:

- **across an `await`** — the ref is stale by the time the continuation runs;
- **inside `dispose`** — asserted on *any* `ref` use there, not merely use after
  an await, so even `unawaited(ref.read(x).flush())` throws.

Both were hit during the migration, and both are invisible until something goes
wrong at the wrong moment:

- `EditorBootstrap.start(ref)` was called from `initState` and held the ref across
  four awaits. It only failed when the window was closed while the startup ladder
  was still running — which is exactly what a user quitting immediately does.
- `dispose` failures land during *tree finalisation*, after the test that closed
  the surface has already passed. Flutter reports them as a separate error, so a
  suite can be green and the failure still scrolls past.

The rule is short: **read what you need into ordinary objects, then do the async
work.** `EditorBootstrap` and `EditorTeardown` take notifiers and futures as
constructor fields and are built in `initState`, which is the one place a
`ConsumerState` may read its ref. `WidgetSurface` captures its notifier the same
way, because it has to tell the runner to give the keyboard back when torn down
with its composer open — a widget destroyed mid-compose would otherwise leave the
native window holding the keyboard with no field visible to type into.

---

## 4. Adding work

1. Put the state in a provider, not in a `State`.
2. `ref.watch` it where it is drawn. `ref.read` it in handlers.
3. If a widget needs it, do not add a parameter — add a `ref.watch`.
4. If it is one frame long, use a `ValueNotifier` **and a listener**. Writing the
   field is not enough; see §3.4.
5. Never keep a `WidgetRef` past an `await` or into `dispose`; see §3.8.
6. Keep the provider under 200 lines; split before you cross it.

---

## 5. What Riverpod does not do here

Recorded so nobody discovers it later and thinks the migration was a mistake:

- **It does not cross the isolate boundary.** Two containers, no shared instances.
  `PROJECT.md`'s one-writer-per-file rule is untouched.
- **It does not help `markdown_text.dart` (1072 lines) or `widget_surface.dart`
  (841 lines).** Together they are 38% of `lib/`, both are pure UI, and neither
  moves.
- **It does not fix the unawaited flush in `dispose()`.** `ref.onDispose` is
  synchronous and cannot await; the `unawaited(...flush())` calls are a
  pre-existing hazard with its own entry in `docs/isolate_pattern.md` §4.3 and a
  guard that keeps it named.
- **Prop-drilling savings are smaller here than in hellobiller.** This tree is
  shallow — `MaterialApp → EditorView → panes`. The real win was deleting a
  duplicated bootstrap and the three divergent brightness resolvers inside it, not
  flattening a deep tree.
- **It does not make a widget test see the file system.** A provider builds on
  first read, and a first read during `pumpWidget` issues its file I/O under the
  fake clock — which never completes, so the provider stays in `isLoading` and
  every finder returns nothing. No exception and no log. Tests must warm the
  providers inside `tester.runAsync` *before* the first pump; see
  `docs/testing_pattern.md` §4.

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
| 3.1 | Providers construct; widgets read | **guard** `isolate_guard_test` * no widget constructs a repository or a controller*; *the scanner still finds the six types it claims to*; *the theme provider is under ui/, not state/* |
| 3.2 | One container per isolate | **guard** `isolate_guard_test` * main() builds the scope and passes no state to either root*; **manual** - a probe reading both windows at once |
| 3.3 | Notifier, not ChangeNotifier | `notes_controller_test`, `widget_integration_test` |
| 3.4 | No `setState`, and a `ValueNotifier` has a listener | **guard** `no_set_state_test` * lib/ has no setState calls at all*; *the scanner still finds them, or the rule above is vacuous*; *the two replacements are the only two*; *every ValueNotifier is listened to, or nothing rebuilds* |
| 3.5 | No dependency by parameter | **guard** `provider_guard_test` * no widget holds shared state by constructor parameter*; *the scanner still matches the names it claims to*; *a value is not a dependency*; *a load result is not an injected dependency*; *callbacks are allowed, and are what the roots pass* |
| 3.6 | A provider is under 200 lines | **guard** `provider_guard_test` * no more provider files are over the cap than are already recorded*, *the scanner measures what it claims to measure* — the two breaches stay named and the count cannot grow |
| 3.7 | Repositories stay plain | `storage_guard_test` |
| 3.8 | A `WidgetRef` is not held across an `await` or into `dispose` | **guard** `isolate_guard_test` * the flush-on-teardown hazard is still named* |

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