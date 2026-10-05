# Flutter Architecture, Performance & Riverpod Guidelines

A short rulebook for keeping the app fast, light on RAM/CPU, and easy to maintain.
Every rule here is meant to be followed in code review.

---

## Table of Contents

1. [Golden Rules (Quick Summary)](#1-golden-rules-quick-summary)
2. [File & Size Limits](#2-file--size-limits)
3. [Widget Rules](#3-widget-rules)
4. [Folder Structure](#4-folder-structure)
5. [Riverpod Best Practices](#5-riverpod-best-practices)
6. [Rebuild Only What Changed (Example)](#6-rebuild-only-what-changed-example)
7. [Performance Checklist (RAM & CPU)](#7-performance-checklist-ram--cpu)
8. [CustomPainter Rules](#8-custompainter-rules)
9. [Automated Checks](#9-automated-checks)
10. [Pull Request Checklist](#10-pull-request-checklist)

**Appendix: [How this document relates to this repository](#appendix-how-this-document-relates-to-this-repository)** — read this before applying anything above.

---

## 1. Golden Rules (Quick Summary)

| # | Rule |
|---|------|
| 1 | A **screen** has at most **500 lines**. A **widget** has at most **350 lines**. |
| 2 | A screen is **never one big widget**. It is a composition of many small widgets. |
| 3 | **No private widgets** (`_MyWidget`) and **no private build methods** (`Widget _buildBody()`). |
| 4 | **One widget per file**, and every widget lives in **its own folder**. |
| 5 | Rebuild **only the part that changes**, never the whole tree. |
| 6 | `ref.watch` in `build`, `ref.read` in callbacks, `ref.select` for partial state. |
| 7 | Business logic lives in **providers/notifiers**, never inside widgets. |
| 8 | Always test performance in **profile mode** on a **real device**. |

---

## 2. File & Size Limits

| Type | Max lines | If exceeded |
|------|-----------|-------------|
| Screen | **500** | Extract sections into widgets |
| Widget | **350** | Split into smaller widgets |
| Provider / Notifier | 300 (recommended) | Split by responsibility |

Notes:

- Lines are counted for **code only**. Imports, blank lines and comments do not
  count toward the limit. A file that explains itself is not a file that is too
  big, and a comment-heavy file that is small in code should not be split for the
  wrong reason.
- **Comments have their own limit: 2–3 lines each.** Past that a comment is no
  longer documenting the code, it is replacing the reading of it. Summarise
  rather than truncate — read the comment *and* the code it describes, then
  write the short version, because a summary written from the comment alone
  drops the part that was only in the code.
- Hitting the limit is a signal to split. Do not compress code to squeeze under it.
- A screen file contains **only the screen class**: `Scaffold`, layout, and the composition of widgets. No UI details.

---

## 3. Widget Rules

### 3.1 What counts as a "widget"

Any class that extends one of these:

- `StatelessWidget`
- `StatefulWidget`
- `ConsumerWidget`
- `ConsumerStatefulWidget`
- `CustomPainter`

(`Consumer` and `ConsumerStatefulWidget` are widgets too. The same rules apply.)

> The private `State` / `ConsumerState` class that goes with a `StatefulWidget` is **allowed**. It is not a separate widget. It must live in the same file as its widget.

### 3.2 No private widgets

```dart
// BAD
class _ProfileHeader extends StatelessWidget { ... }

// GOOD (public class, own file, own folder)
class ProfileHeader extends StatelessWidget { ... }
```

### 3.3 No private build functions

```dart
// BAD: rebuilds with the parent and cannot be skipped by Flutter
Widget _buildBody() { ... }
Widget _buildHeader() { ... }

// GOOD: separate widget, can be `const`, rebuilds independently
const ProfileBody()
const ProfileHeader()
```

Why this matters: helper methods run every time the parent builds. A separate widget class with a `const` constructor lets Flutter skip it completely.

### 3.4 A screen is a composition

```dart
// GOOD: the screen only arranges widgets
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: ProfileAppBar(),
      body: Column(
        children: [
          ProfileHeader(),
          ProfileTitleField(),
          ProfileStatsSection(),
          ProfileActionButtons(),
        ],
      ),
    );
  }
}
```

### 3.5 Every widget follows these habits

- Use a `const` constructor whenever possible.
- Keep `build()` short and free of heavy work (no parsing, sorting, or filtering inside it).
- Pass **only the data the widget needs** (small, specific parameters), not whole objects.
- Use `MediaQuery.sizeOf(context)` instead of `MediaQuery.of(context).size`, and `Theme.of(context).textTheme` once per build, so unrelated changes do not trigger rebuilds.

---

## 4. Folder Structure

Feature-first. Every widget gets **its own folder**, and the widget file sits inside it.

```
lib/
├── core/
│   ├── constants/
│   ├── theme/
│   ├── utils/
│   └── widgets/                      # Shared widgets used by many features
│       ├── app_button/
│       │   └── app_button.dart
│       └── loading_indicator/
│           └── loading_indicator.dart
│
├── features/
│   └── profile/
│       ├── data/                     # API, database, repositories (impl)
│       ├── domain/                   # Models, repository interfaces
│       └── presentation/
│           ├── providers/            # Riverpod providers / notifiers
│           │   └── profile_provider.dart
│           ├── screens/
│           │   └── profile_screen/
│           │       └── profile_screen.dart
│           └── widgets/
│               ├── profile_header/
│               │   └── profile_header.dart
│               ├── profile_title_field/
│               │   └── profile_title_field.dart
│               ├── profile_stats_section/
│               │   └── profile_stats_section.dart
│               └── profile_wave_painter/       # CustomPainter also gets a folder
│                   └── profile_wave_painter.dart
│
└── main.dart
```

Naming rules:

| Item | Convention | Example |
|------|-----------|---------|
| Folder | `snake_case`, same name as the widget | `profile_header/` |
| File | `snake_case.dart`, same name as the folder | `profile_header.dart` |
| Class | `PascalCase`, public | `ProfileHeader` |
| Provider file | `<feature>_provider.dart` | `profile_provider.dart` |

Other rules:

- **One widget class per file.**
- A widget used by **one feature** goes in that feature's `widgets/` folder.
- A widget used by **two or more features** moves to `core/widgets/`.
- Widgets never call APIs or databases directly. They talk to providers only.

---

## 5. Riverpod Best Practices

### 5.1 Quick decision table

| Method | Use it when | Where |
|--------|-------------|-------|
| `ref.watch(p)` | The UI must **rebuild** when the value changes | Inside `build()` or `Consumer` builder |
| `ref.read(p)` | You need the value **once**, no rebuild (button taps, form submit) | Callbacks, `initState`, event handlers |
| `ref.read(p.notifier)` | Call a method on a notifier | Callbacks (`onPressed`, `onChanged`) |
| `ref.watch(p.select(...))` | You need **only one field** of a bigger state | Inside `build()` |
| `ref.listen(p, ...)` | **Side effects**: snackbar, dialog, navigation | Inside `build()` of a Consumer |
| `ref.listenManual(p, ...)` | Side effects that start in `initState` | `initState` of `ConsumerStatefulWidget` |
| `await ref.watch(p.selectAsync(...))` | Inside **another provider**, wait for one field of an async provider | Provider body only |

### 5.2 `ref.watch`

Use it to display data.

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final count = ref.watch(counterProvider);
  return Text('$count');
}
```

Do not use `ref.watch`:

- Inside `onPressed`, `onChanged`, `onTap`, or any callback.
- Inside `initState`.
- At the top of a screen when only a small child needs the value.

### 5.3 `ref.read`

Use it for one-time actions.

```dart
ElevatedButton(
  onPressed: () => ref.read(counterProvider.notifier).increment(),
  child: const Text('Add'),
)
```

Do not use `ref.read` inside `build()` to get a value you display. The UI will never update.

> `ref.watch(p.notifier)` does not rebuild when state changes, but `ref.read(p.notifier)` in callbacks is the cleaner habit.

### 5.4 `ref.select`

Use it whenever you need **one field** of an object. The widget rebuilds only when that field changes.

```dart
// BAD: rebuilds when ANY field of the profile changes
final profile = ref.watch(profileProvider);
return Text(profile.title);

// GOOD: rebuilds only when `title` changes
final title = ref.watch(profileProvider.select((p) => p.title));
return Text(title);
```

Rules for `select`:

- The selected value must have a proper `==` (primitives, records, or immutable classes with `==`).
- Selecting a new `List` or `Map` each time defeats the purpose, because a new object is never equal to the old one.
- To read several fields, select a record: `select((p) => (p.title, p.subtitle))`.

For async providers in widgets:

```dart
final name = ref.watch(
  userProvider.select((async) => async.valueOrNull?.name),
);
```

(In Riverpod 3.x, `valueOrNull` is simply `value`.)

### 5.5 `selectAsync`

Use it **inside providers** when you depend on an async provider but only need one part of it.

```dart
final userNameLengthProvider = FutureProvider<int>((ref) async {
  final name = await ref.watch(userProvider.selectAsync((u) => u.name));
  return name.length;
});
```

Do not use it in widgets. In widgets use `select` or `.when`.

### 5.6 `ref.listen` for side effects

Never trigger navigation, snackbars, or dialogs from `build()` using `watch`. Use `listen`.

```dart
ref.listen(loginProvider, (previous, next) {
  if (next.hasError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${next.error}')),
    );
  }
});
```

### 5.7 Where to place `Consumer`

**Rule: watch as low in the tree as possible, in the smallest widget that needs the data.**

| Situation | Use |
|-----------|-----|
| A whole small widget depends on a provider | `ConsumerWidget` |
| A small widget with controllers, animations, or focus nodes | `ConsumerStatefulWidget` |
| Only one part inside a larger widget depends on a provider | `Consumer` around **just that part** |
| Widget needs no provider | `StatelessWidget` (keeps it `const` and cheap) |

Use the `child` parameter to keep static content out of rebuilds:

```dart
Consumer(
  child: const ExpensiveStaticPart(),   // built once
  builder: (context, ref, child) {
    final value = ref.watch(valueProvider);
    return Column(children: [Text('$value'), child!]);
  },
)
```

Do not make the whole screen a `ConsumerWidget` that watches everything and passes data down to children. Let each child widget watch what it needs.

### 5.8 Provider design rules

- Define providers **at top level** (never inside `build()` or widgets).
- Use `Notifier` / `AsyncNotifier` for state with logic. Use plain `Provider` for derived or read-only values.
- Keep state **immutable** (use `copyWith`, `freezed`, or `Equatable`).
- Use `autoDispose` for screen-scoped state so it is freed when the screen closes. Use `keepAlive` only for data that must survive (auth, settings).
- Use `.family` for parameterized providers (e.g., by item ID).
- Split large state into **several small providers** instead of one giant state class.
- Derived data (filtering, sorting, totals) belongs in a separate provider, not in `build()`.
- Do not call `ref.read` inside a provider to get state that should be watched. Use `ref.watch` so the provider updates.
- Do not store `BuildContext` or widgets in providers.

---

## 6. Rebuild Only What Changed (Example)

**Scenario:** the user edits the title. Only the title widget should rebuild. The avatar, stats, and buttons must stay untouched.

### Bad

```dart
// The whole screen watches everything: every keystroke rebuilds ALL of it
class ProfileScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      body: Column(
        children: [
          Avatar(url: profile.avatarUrl),
          Text(profile.title),
          Stats(stats: profile.stats),
        ],
      ),
    );
  }
}
```

### Good

**State:**

```dart
// features/profile/presentation/providers/profile_provider.dart
final profileProvider = NotifierProvider<ProfileNotifier, ProfileState>(
  ProfileNotifier.new,
);

class ProfileNotifier extends Notifier<ProfileState> {
  @override
  ProfileState build() => const ProfileState();

  void updateTitle(String title) {
    state = state.copyWith(title: title);
  }
}
```

**Screen (no provider watching, fully `const`):**

```dart
// screens/profile_screen/profile_screen.dart
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          ProfileAvatar(),
          ProfileTitleField(),
          ProfileStatsSection(),
        ],
      ),
    );
  }
}
```

**Title widget (watches only `title`):**

```dart
// widgets/profile_title_field/profile_title_field.dart
class ProfileTitleField extends ConsumerStatefulWidget {
  const ProfileTitleField({super.key});

  @override
  ConsumerState<ProfileTitleField> createState() => _ProfileTitleFieldState();
}

class _ProfileTitleFieldState extends ConsumerState<ProfileTitleField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // read once: we only need the initial value
    _controller = TextEditingController(
      text: ref.read(profileProvider).title,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      // read in callback: no rebuild needed
      onChanged: ref.read(profileProvider.notifier).updateTitle,
    );
  }
}
```

**Another widget that only displays the title:**

```dart
// widgets/profile_title_text/profile_title_text.dart
class ProfileTitleText extends ConsumerWidget {
  const ProfileTitleText({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(profileProvider.select((s) => s.title));
    return Text(title);
  }
}
```

Result: typing in the field rebuilds only `ProfileTitleText`. The avatar and stats never rebuild.

---

## 7. Performance Checklist (RAM & CPU)

### 7.1 Reduce CPU (rebuilds & rendering)

- [ ] `const` constructors everywhere possible.
- [ ] Granular state: `select`, small `Consumer`s, small widgets.
- [ ] No heavy work in `build()` (sorting, filtering, JSON parsing, regex).
- [ ] Heavy work runs off the UI thread: `compute()` or `Isolate.run()`.
- [ ] `RepaintBoundary` around frequently repainting parts (animations, charts, video, painters).
- [ ] Avoid `Opacity`, `ClipRRect`, `ShaderMask`, and other `saveLayer` widgets inside animations. Use `FadeTransition` or `AnimatedOpacity`.
- [ ] `AnimatedBuilder` / `ValueListenableBuilder` with the `child` parameter for static content.
- [ ] Use `Key`s (`ValueKey(id)`) on list items that reorder or change.
- [ ] Debounce search fields and rapid events (300–500 ms).
- [ ] Avoid `IntrinsicHeight` / `IntrinsicWidth` in long lists (expensive layout).

### 7.2 Reduce RAM

- [ ] Long lists use `ListView.builder`, `GridView.builder`, or slivers. Never `Column(children: bigList)`.
- [ ] Give list items a fixed `itemExtent` or `prototypeItem` when sizes are uniform.
- [ ] Dispose everything in `dispose()`: `AnimationController`, `TextEditingController`, `ScrollController`, `FocusNode`, `StreamSubscription`, `Timer`.
- [ ] Images: use `cached_network_image` and set `cacheWidth` / `cacheHeight` (or `ResizeImage`) so images decode at display size.
- [ ] Prefer WebP, and compress or resize before upload and display.
- [ ] Use `autoDispose` providers for screen-scoped state.
- [ ] Paginate API data (load 20–50 items at a time). Do not hold thousands of items in memory.
- [ ] No large objects in global singletons or static variables.
- [ ] Do not use `AutomaticKeepAliveClientMixin` on every tab or item. Keep alive only when truly needed.

### 7.3 Build & release

- [ ] Profile with `flutter run --profile` on a **real device**. Never judge performance in debug mode.
- [ ] Release build: `--obfuscate --split-debug-info=build/symbols`.
- [ ] Android: `--split-per-abi` (or build an App Bundle).
- [ ] Use deferred loading (`deferred as`) for rarely used heavy features.
- [ ] Keep Impeller enabled (default on modern Flutter).
- [ ] Remove unused packages and assets.

### 7.4 Measure, don't guess

| Tool | What it finds |
|------|---------------|
| DevTools: Performance | Jank, slow frames (over 16 ms) |
| DevTools: Memory | Leaks, large allocations |
| DevTools: CPU Profiler | Slow functions |
| "Track widget rebuilds" | Unnecessary rebuilds |
| Performance Overlay | UI vs raster thread problems |

---

## 8. CustomPainter Rules

A `CustomPainter` is a widget under these rules. Put it in its own folder and file:

```
widgets/profile_wave_painter/profile_wave_painter.dart
```

- Public class, one painter per file, max 350 lines.
- Implement `shouldRepaint` correctly. Return `true` only when painted data actually changed.
- Pass a `repaint` listenable (e.g., an `AnimationController`) to the super constructor instead of rebuilding the widget each frame.
- Wrap the `CustomPaint` in a `RepaintBoundary`.
- Create `Paint`, `Path`, and `TextPainter` objects **once** (as fields), not on every `paint()` call.
- Never allocate large objects or run heavy calculations inside `paint()`.

```dart
class ProfileWavePainter extends CustomPainter {
  ProfileWavePainter({required this.progress, required Listenable repaint})
      : super(repaint: repaint);

  final double progress;
  final Paint _paint = Paint()..color = const Color(0xFF2196F3);

  @override
  void paint(Canvas canvas, Size size) {
    // draw using _paint
  }

  @override
  bool shouldRepaint(ProfileWavePainter old) => old.progress != progress;
}
```

---

## 9. Automated Checks

Run these from the project root (CI or pre-commit). Each command should print **nothing** when the rules are respected.

**Screens over 500 lines**

```bash
find lib -path "*screens*" -name "*.dart" | xargs wc -l | awk '$1 > 500 && $2 != "total"'
```

**Widgets over 350 lines**

```bash
find lib -path "*widgets*" -name "*.dart" | xargs wc -l | awk '$1 > 350 && $2 != "total"'
```

**Private widget classes**

```bash
grep -rnE "class _\w+ extends (StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|CustomPainter)" lib
```

**Private build methods**

```bash
grep -rnE "Widget _\w+\(" lib
```

**Recommended `analysis_options.yaml` lints**

```yaml
linter:
  rules:
    - prefer_const_constructors
    - prefer_const_literals_to_create_immutables
    - prefer_const_declarations
    - avoid_unnecessary_containers
    - sized_box_for_whitespace
    - use_key_in_widget_constructors
    - close_sinks
    - cancel_subscriptions
```

---

## 10. Pull Request Checklist

**Structure**
- [ ] Screen is 500 lines or fewer. Every widget is 350 lines or fewer. Code only — comments are not counted.
- [ ] No comment runs past 2–3 lines. Longer ones were summarised against the code they describe, not truncated.
- [ ] Screen is a composition of widgets, not one giant widget.
- [ ] No private widgets and no `_buildXyz()` methods.
- [ ] One widget per file, inside its own folder.

**Riverpod**
- [ ] `watch` only in `build`, `read` only in callbacks and `initState`.
- [ ] `select` used when only part of a state is needed.
- [ ] `ref.listen` used for snackbars, dialogs, navigation.
- [ ] `Consumer` / `ConsumerWidget` wraps only the part that needs the data.
- [ ] Providers are top-level, state is immutable, `autoDispose` used where suitable.

**Performance**
- [ ] `const` used wherever possible.
- [ ] Lists use builder constructors.
- [ ] All controllers, timers, and subscriptions are disposed.
- [ ] Images are sized with `cacheWidth` / `cacheHeight`.
- [ ] Heavy work is off the UI thread.
- [ ] Checked in profile mode with DevTools.

---

## Appendix. How this document relates to this repository

**This is a general Flutter rulebook, carried in as a reference for future work. It
is not a description of how this project is built, and it is not enforced here.**

It was copied in verbatim on purpose, so that the guidance is available unchanged for
new work. Nothing in it was rewritten to match the current tree, which means several
of its rules actively contradict this repository. Read the conflicts before applying
any of it:

| This doc says | This repository does | Authority |
|---|---|---|
| §4 `features/<feature>/{data,domain,presentation}` | `ui/ → state/ → data/ → core/`, plus `platform/` | `AGENTS.md` §3 |
| §4, §3.2 one widget per file, each in its own folder | `settings_dialog.dart` holds 12 widget classes, `widget_surface.dart` 6, `widget_app.dart` 5 | `AGENTS.md` §0.8 |
| §3.2 no private widgets | private widget classes exist and are allowed | `AGENTS.md` §0.8 exempts `EditorBootstrap` / `EditorTeardown` |
| §2 provider 300 lines | 200 | `docs/provider_pattern.md` §3.6 |
| §2 comments do not count toward the cap | `provider_guard_test` counts every line, comments included (`entry.value.length`) | this is a rule to make, not one that is real |
| §2 a comment runs at most 2–3 lines | the house style is a multi-paragraph comment explaining why, everywhere | this is a rule to make, not one that is real |
| §2 screen 500 / widget 350 | a 200-line cap on providers, with two recorded breaches | `AGENTS.md` §4.8 |
| §7.2 `cached_network_image`, paginate API data | there is no network code at all | `PROJECT.md`, `AGENTS.md` §1 |
| §7.3 Android `--split-per-abi`, App Bundle | Windows desktop only | `PROJECT.md` |
| §9 `find lib -path "*screens*"` | matches nothing; no `features/` or `screens/` directory | — |
| §5.4 `valueOrNull` is `value` in Riverpod 3.x | **accurate** — `pubspec.yaml` pins `^3.4.3` | — |

**On a conflict, `AGENTS.md` §0.1 decides: `PROJECT.md` is the product authority, and
nothing here overrides it.** To make one of these rules real for this repository it has
to become a frozen rule in `AGENTS.md` §0 and a guard in `test/architecture/`, the same
way every existing rule was made enforceable — see `AGENTS.md` §3.1. A guideline that is
only written down is a comment, not a rule.

Two of these rules *are* already real here and agree with this doc: `ref.watch` in
`build` and `ref.read` in callbacks (`AGENTS.md` §0.8), and the dispose-everything
discipline in §7.2, which `isolate_guard_test` partly covers.