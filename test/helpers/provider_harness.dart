/// Builds a real `ProviderContainer` over a temp directory, for tests that need
/// the graph rather than one class.
///
/// The controllers used to be constructible in one line, which is why the old tests
/// did exactly that. They are not any more: `notesProvider` needs a repository,
/// which needs a path, which needs a `LaunchInfo` and a `ShellChannel`. That is
/// three overrides of ceremony per test file, and getting it subtly wrong produces a
/// test that passes because nothing was ever wired up.
///
/// So it lives here once, and every test that needs a container gets one from
/// [TestHarness.build].
library;

import 'dart:io';

import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/src/framework.dart';
import 'package:win_notes/core/utils/app_paths.dart';
import 'package:win_notes/core/utils/atomic_json_file.dart';
import 'package:win_notes/features/notes/domain/note.dart';
import 'package:win_notes/features/notes/data/notes_repository.dart';
import 'package:win_notes/core/platform/shell_channel.dart';
import 'package:win_notes/features/notes/presentation/providers/notes_controller.dart';
import 'package:win_notes/features/notes/domain/repositories.dart';
import 'package:win_notes/features/notes/presentation/providers/notes_providers.dart';
import 'package:win_notes/core/utils/app_providers.dart';
import 'package:win_notes/features/settings/presentation/providers/settings_controller.dart';
import 'package:win_notes/features/widget/presentation/providers/widget_controller.dart';

/// A container over a temporary profile directory, plus the plumbing to shut it down
/// in the right order.
class TestHarness {
  TestHarness._(this._temp, this.container, this._notesJson);

  final Directory _temp;
  final ProviderContainer container;

  /// The `notes.json` handle the container's repository was built over.
  ///
  /// Held here rather than left to `notesRepositoryProvider` to build for itself, and
  /// the reason is `cancelPendingWrites` - the only synchronous way to drop a debounced
  /// write that a widget test will never let elapse. The repository does not expose it,
  /// so a test that owns the `AtomicJsonFile` is a test that can reach it.
  final AtomicJsonFile _notesJson;

  /// Drops a queued `notes.json` write without performing it.
  ///
  /// Synchronous on purpose. A widget test's fake clock never advances the 250ms
  /// debounce, so *awaiting* the write is what hangs - `docs/testing_pattern.md` §4.
  /// The old `markdown_test` did this per group with its own `AtomicJsonFile`, and the
  /// migration lost it: reaching the file through the container is not possible, so the
  /// tests that used it began awaiting `flush()` and timing out.
  void cancelPendingWrites() => _notesJson.cancelPendingWrites();

  /// The temp directory backing this container.
  ///
  /// Exposed because a good number of tests do not go through the notifier at all:
  /// they write a corrupt `notes.json` directly and assert the app refuses it, or hold
  /// an exclusive lock and assert the retry ladder behaves. Those tests are about the
  /// *file*, not about Riverpod, and reaching the file by path is honest.
  String get path => _temp.path;

  /// `<path>\notes.json`, with a doubled separator because these are Dart strings
  /// holding Windows paths, which is how the tests that reach for the file have always
  /// written them.
  String get notesFile => '$path\\notes.json';

  /// The rolling backup beside it. See [notesFile] on the doubled separator.
  String get backupFile => '$path\\notes.json.bak';

  /// Wraps [child] so it reads *this harness's* container.
  ///
  /// A widget cannot read a bare `ProviderContainer`, which is what
  /// `UncontrolledProviderScope` exists for. It is the right tool rather than a
  /// second `ProviderScope` carrying the same overrides, and the difference is not
  /// cosmetic: a second scope means a second container, so a tap inside the widget
  /// mutates a provider the test cannot see, and the assertion then runs against a
  /// container nothing has touched. That is exactly what happened the first time
  /// this was written, and it is worth the extra line of explanation.
  Widget wrap(Widget child) {
    // A widget that pumps the editor or the settings dialog builds those providers
    // on its own, with no call through [notes] or [settings]. Marking them here is
    // what lets [drain] reach them without also building the widget surface's.
    _used.add(_Kind.notes);
    _used.add(_Kind.settings);
    return UncontrolledProviderScope(container: container, child: child);
  }
  bool _disposed = false;

  /// Releases the file handles and deletes the temp directory.
///
/// Idempotent, and it **retries** the deletion rather than deleting once and hoping.
/// A widget test tears the tree down after `tearDown`, so at this point a provider
/// may still be mid-write and holding a handle on the directory; deleting on the
/// first attempt fails with `PathAccessException`, which is the same flake
/// `docs/testing_pattern.md` records for the older controller-based harness.
///
/// The retry is bounded and generous - five seconds - because the alternative is a
/// suite that fails roughly one run in six for no reason anyone can see.
Future<void> dispose({bool keepProfile = false}) async {
    if (_disposed) return;
    _disposed = true;
    container.dispose();

    // Wait for the last write to let go before deleting.
    try {
      await drain();
    } catch (_) {
      // Nothing queued, or the provider was never built.
    }

    final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_temp.existsSync()) {
      if (keepProfile) return;
      try {
        _temp.deleteSync(recursive: true);
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) {
          // Leaving the directory behind is strictly better than failing the test:
          // it costs a folder in %TEMP% and nothing else.
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// Disposes without deleting the profile directory.
  ///
  /// For a **second launch over the same profile**, which [build] can then be pointed
  /// at with `at:`. This exists because the obvious sequence -
  /// `await dispose(); build(at: dir)` - is a first launch wearing a second one's
  /// name: dispose has already deleted the directory, so the rebuild starts from
  /// nothing, creates a fresh note, and the test that means to prove persistence
  /// passes against a provider that never wrote anything. Which is exactly what
  /// happened the first time this was written.
  Future<void> disposeKeepingProfile() => dispose(keepProfile: true);

  /// Builds a harness whose data directory is a fresh temp folder.
  ///
  /// [isWidgetSurface] decides which graph the repository providers see, and defaults
  /// to the editor.
  ///
  /// [at] points the harness at an existing directory instead of a new one, which is
  /// what a **second launch** over the same profile is. Added because "build a second
  /// harness in a new folder and read notes from it" is not a second launch at all -
  /// it finds an empty directory, creates a note, and looks like it worked, which is
  /// how a provider that never writes anything can pass a test that means to prove it
  /// does.
  ///
  /// The trap that made this necessary twice: **[dispose] deletes the directory.** So
  /// "dispose, then build again `at` the same path" is another first launch - the
  /// folder is gone and will be recreated empty - and the test that means to check
  /// persistence silently checks nothing. A second launch has to dispose *without*
  /// removing the directory; see [disposeKeepingProfile].
  ///
  /// Watchers are **not** started. `AtomicJsonFile` watches with real timers that
  /// `flutter_test`'s fake clock never advances, so a watched repository leaves a test
  /// hanging on a callback that cannot fire. The old controller-based tests had a
  /// `watchExternal` flag for the same reason; this is that flag, gone - because no
  /// test needs it, not because it was forgotten.
  static TestHarness build({
    bool isWidgetSurface = false,
    LaunchInfo? launch,
    String? at,
  }) {
    final Directory temp = at == null
        ? Directory.systemTemp.createTempSync('winnotes_providers')
        : Directory(at);
    final AppPaths paths = AppPaths(
      dataDirectory: temp.path,
      executablePath: temp.path,
    );
    final LaunchInfo resolved = launch ?? launchFor(paths, isWidgetSurface: isWidgetSurface);

    // Owned here so [cancelPendingWrites] can reach it. Overriding the provider
    // rather than duplicating the construction is what keeps the container reading
    // the same file the tests write to.
    final AtomicJsonFile notesJson = AtomicJsonFile(paths.notesFile);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        shellProvider.overrideWithValue(ShellChannel()),
        launchInfoProvider.overrideWithValue(resolved),
        appPathsProvider.overrideWithValue(paths),
        notesRepositoryProvider.overrideWithValue(
          NotesRepository(notesJson),
        ),
      ],
    );

    return TestHarness._(temp, container, notesJson);
  }

  /// A `LaunchInfo` with everything off except what a test asks for.
  ///
  /// Exposed because the widget-surface tests need `isWidgetSurface: true` and the
  /// integration tests need a specific launch mode, and building the whole record
  /// again in each of them is how a required field gets forgotten.
  static LaunchInfo launchFor(
    AppPaths paths, {
    required bool isWidgetSurface,
    String launchMode = 'manual',
    bool isSystemDark = false,
    bool animationsEnabled = true,
    bool acrylicSupported = false,
  }) {
    return LaunchInfo(
      role: isWidgetSurface ? 'shell' : 'editor',
      launchMode: launchMode,
      isWidgetSurface: isWidgetSurface,
      dataDirectory: paths.dataDirectory,
      executablePath: paths.executablePath,
      isSystemDark: isSystemDark,
      animationsEnabled: animationsEnabled,
      highContrast: false,
      acrylicSupported: acrylicSupported,
      buildNumber: 0,
      monitors: const <MonitorInfo>[],
      autostartEnabled: false,
      autostartCommand: '',
      defaultWidgetBounds: const NativeBounds(
        left: 0,
        top: 0,
        width: 360,
        height: 480,
      ),
    );
  }

  /// The notes notifier, with the first load already awaited.
  ///
  /// Awaiting here rather than at each call site is deliberate: the old tests called
  /// `load()` themselves, and forgetting it produced a test that asserted against an
  /// empty list and passed.
  Future<NotesNotifier> notes() async {
    _used.add(_Kind.notes);
    await container.read(notesProvider.future);
    return container.read(notesProvider.notifier);
  }

  /// The current notes state, for assertions.
  NotesState notesState() => container.read(notesProvider).requireValue;

  Future<SettingsNotifier> settings() async {
    _used.add(_Kind.settings);
    await container.read(settingsProvider.future);
    return container.read(settingsProvider.notifier);
  }

  SettingsState settingsState() => container.read(settingsProvider).requireValue;

  Future<WidgetNotifier> widgetState() async {
    _used.add(_Kind.widget);
    await container.read(widgetProvider.future);
    return container.read(widgetProvider.notifier);
  }

  /// Which providers this harness has actually built.
  ///
  /// Set by the `notes()`, `settings()` and `widgetState()` helpers rather than
  /// guessed. The first version of [drain] read all three notifiers unconditionally,
  /// which *builds* any provider it had not been asked for - and building
  /// `widgetProvider` does real file I/O under `flutter_test`'s fake clock, so it never
  /// completed and the teardown hung until the test timed out. Draining a provider the
  /// test never used is not a no-op; it is starting it.
  final Set<_Kind> _used = <_Kind>{};

  /// Drains the debounced writers of the providers that were actually built.
  ///
  /// Call before [dispose]; the order is the whole point. A queued write outlives the
  /// test that made it, and `AtomicJsonFile` creates its parent directory before every
  /// write. Delete the directory first and the write recreates it - hundreds of them
  /// left in the developer's `%TEMP%`, with every test green. That happened once.
  Future<void> drain() async {
    final List<Future<void> Function()> flushes = <Future<void> Function()>[
      if (_used.contains(_Kind.notes))
        () => container.read(notesProvider.notifier).flush(),
      if (_used.contains(_Kind.settings))
        () => container.read(settingsProvider.notifier).flush(),
      if (_used.contains(_Kind.widget))
        () => container.read(widgetProvider.notifier).flush(),
    ];
    for (final Future<void> Function() flush in flushes) {
      try {
        await flush();
      } catch (_) {
        // The provider may have been disposed mid-teardown. Nothing to drain.
      }
    }
  }
}

/// The widget surface's state and actions, over the provider.
///
/// The counterpart to [Notes] for `widget_integration_test`. Same reasoning: the old
/// tests drove a `WidgetController` directly, and `WidgetSurface` no longer takes
/// one, so they read state through a small facade rather than through
/// `container.read(widgetProvider).requireValue` at all thirty-odd assertions.
///
/// Every getter reads the container fresh, so a mutation followed by an assertion
/// sees the new value.
class WidgetNotes {
  WidgetNotes(this.harness);

  final TestHarness harness;

  ProviderContainer get _c => harness.container;
  WidgetNotifier get _n => _c.read(widgetProvider.notifier);
  WidgetSurfaceState get _s => _c.read(widgetProvider).requireValue;

  // --- values, from the state ---
  List<Note> get notes => _s.notes;
  Note? get focusedNote => _s.focusedNote;
  bool get widgetVisible => _s.visible;
  bool get hasAnyNoteWithText => _s.hasAnyNoteWithText;
  String? get selectedId => _s.selectedId;

  // --- actions, on the notifier ---
  Future<void> toggleCompleted(String id) => _n.toggleCompleted(id);
  Future<bool> addNote({required String title, required String body}) =>
      _n.addNote(title: title, body: body);
  Future<void> focusNote(String id) async => _n.focusNote(id);
  Future<void> onGeometryChanged(NativeBounds bounds) async =>
      _n.onGeometryChanged(bounds);
  Future<void> setWidgetVisible({required bool visible}) =>
      _n.setWidgetVisible(visible: visible);

  /// Re-reads `notes.json`, as the directory watcher would.
  ///
  /// Called `load` because that is what the old `WidgetController.load` was called
  /// and these tests drive the surface through an external file change - they write
  /// the file and then ask the surface to notice. On the notifier the same operation
  /// is `reloadNotes`, because `build` already did the initial load.
  Future<void> load() => _n.reloadNotes();

  Future<void> flush() => _n.flush();

  /// What `WidgetController.release` was: push everything this surface has queued.
  ///
  /// Called from inside `runAsync` in the tests that assert on the file afterwards,
  /// because flushing under a widget test's fake clock never completes. Kept as a
  /// distinct name from [flush] for that reason - they are the same work, but only
  /// one of them is called where a real clock is running.
  Future<void> release() => flush();
}

///
/// This exists so 45 behavioural tests did not have to be rewritten to read state
/// through `container.read(notesProvider).requireValue` at every assertion. It is a
/// *test* facade, not production code, and it is deliberately the shape the controller
/// was: `notes.notes` for a value that lives in the state, and `notes.createNote()`
/// for an action on the notifier.
///
/// Every getter reads the container fresh, so a test that mutates and then asserts
/// sees the new value - the property the old `ChangeNotifier` gave for free by
/// notifying, and the reason this cannot be a snapshot.
class Notes {
  Notes(this.harness);

  final TestHarness harness;

  ProviderContainer get _c => harness.container;
  NotesNotifier get _n => _c.read(notesProvider.notifier);
  NotesState get _s => _c.read(notesProvider).requireValue;

  // --- values, from the state ---
  List<Note> get notes => _s.notes;
  List<Note> get visibleNotes => _s.visible;
  Note? get selectedNote => _s.selectedNote;
  Note? get focusedNote => _s.focusedNote;
  String? get selectedId => _s.selectedId;
  String get query => _s.query;
  CorruptDataFileError? get corrupt => _s.corrupt;
  bool get isReadOnly => _s.isReadOnly;
  PendingUndo? get pendingUndo => _s.pendingUndo;
  bool get hasBackup => _n.hasBackup;

  // --- actions, on the notifier ---
  void addNote({required String title, required String body}) =>
      _n.addNote(title: title, body: body);
  void toggleCompleted(String id) => _n.toggleCompleted(id);
  void setMarkdown(String id, {required bool enabled}) =>
      _n.setMarkdown(id, enabled: enabled);
  void deleteNote(String id) => _n.deleteNote(id);
  bool undoDelete() => _n.undoDelete();
  void clearPendingUndo() => _n.clearPendingUndo();
  void replaceAll(List<Note> incoming) => _n.replaceAll(incoming);
  void merge(List<Note> incoming) => _n.merge(incoming);
  void ensureAtLeastOneNote() => _n.ensureAtLeastOneNote();
  Future<void> load() => _n.reload();
  Future<void> retryLoad() => _n.retryLoad();
  Future<RecoveryOutcome> restoreBackup() => _n.restoreBackup();
  Future<({RecoveryOutcome outcome, String? keptAt})> startFresh() =>
      _n.startFresh();
  Future<void> flush() => _n.flush();

  /// How many times the notes state has changed identity since this facade was made.
  ///
  /// Replaces `addListener`. The old tests counted notifications to prove a mutation
  /// was idempotent - `setQuery` with the value it already has must not produce a new
  /// state - and that is still worth asserting.
  ///
  /// Counted by comparing state identity around an action rather than by listening to
  /// the provider: `container.listen` needs a live subscription kept alive by the
  /// caller, and the thing under test is the mutation. Identity is the right measure
  /// anyway - these states compare by identity, so a Riverpod listener fires on them.
  int changes = 0;

  /// Runs [action] and counts it if it produced a new state.
  T _counted<T>(T Function() action) {
    final AsyncValue<NotesState> before = _c.read(notesProvider);
    final T result = action();
    if (!identical(before, _c.read(notesProvider))) changes++;
    return result;
  }

  // Only the four the idempotence tests exercise are counted. Counting all of them
  // would mean a test that mutates five things has to know that number, and the
  // number would mean nothing.
  void setQuery(String value) => _counted(() => _n.setQuery(value));
  void select(String? id) => _counted(() => _n.select(id));
  Note? createNote() => _counted(_n.createNote);
  void updateNote(String id, {String? title, String? body}) => _counted(
        () => _n.updateNote(id, title: title, body: body),
      );
}

/// Which of the three providers a harness has built. See [TestHarness.drain].
enum _Kind { notes, settings, widget }
