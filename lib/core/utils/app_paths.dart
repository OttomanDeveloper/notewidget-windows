/// Where WinNotes keeps its files.
///
/// Resolved once and passed down, rather than being recomputed from
/// `Platform.environment`, so there is exactly one place that knows where notes live
/// and a single place to change it.
///
/// **Two directories, not one.** [reportedDirectory] is what the native runner hands
/// us — `%APPDATA%\WinNotes` — and it is where `settings.json` is *always* readable,
/// because that file is how the app learns where the rest of its files are.
/// [dataDirectory] is where everything actually is, which is the same place unless
/// the person has pointed the app somewhere else in Settings.
///
/// They are kept apart because the app must be able to find `settings.json` before it
/// knows anything else. Collapsing them is how a custom location silently becomes
/// unfindable the first time someone changes it — and that failure looks exactly like
/// the notes having vanished.
class AppPaths {
  const AppPaths({
    required this.dataDirectory,
    required this.executablePath,
    this.reportedDirectory,
  });

  /// Overrides the data directory for one run. Set only by tooling that must not
  /// touch the real profile — see [resolve].
  ///
  /// Named for what it is rather than what it is for: it changes *where files go*,
  /// and nothing else. Not the format, not the debounce, not the recovery rules, and
  /// nothing a test would then be measuring something other than the app.
  static const String overrideVariable = 'WIN_NOTES_DATA_DIR';

  /// The paths for a normal launch, honouring both the run's override and any
  /// folder the person has chosen in Settings.
  ///
  /// [reported] is what the runner told us. [configured] is the
  /// `storageDirectory` from `settings.json`, or null when there is none.
  static AppPaths resolve({
    required String reported,
    required String executablePath,
    Map<String, String> environment = const {},
    String? configured,
  }) {
    final override = environment[overrideVariable];

    // An override outranks a configured location. It is the person running the
    // program telling it where to work for this run, which is a stronger signal
    // than a preference saved months ago — and it is what makes a verification run
    // independent of whatever the real profile happens to say.
    if (override != null && override.trim().isNotEmpty) {
      final trimmed = override.trim();
      // Absolute only, and no `..`. An override is supposed to name one directory
      // somewhere else; a relative one would resolve against whatever the runner's
      // working directory happens to be, and `..` would walk out of whatever the
      // caller intended. Refusing is better than quietly landing somewhere else,
      // because "somewhere else" is where notes get lost.
      if (!isUsableDirectory(trimmed)) {
        throw ArgumentError.value(
          trimmed,
          overrideVariable,
          'must be an absolute Windows path with no ".." in it, '
              r'e.g. C:\Users\someone\AppData\Local\Temp\winnotes-verify',
        );
      }
      return AppPaths(
        dataDirectory: trimmed,
        executablePath: executablePath,
        reportedDirectory: trimmed,
      );
    }

    return AppPaths(
      dataDirectory: configuredLocation(reported: reported, configured: configured),
      executablePath: executablePath,
      reportedDirectory: reported,
    );
  }

  /// The directory the person chose in Settings, or [reported] when they have not.
  ///
  /// Pure, and separate from [resolve], so the rule "a configured location must be
  /// an absolute Windows path or it is not used" has exactly one definition and can
  /// be tested without a runner, an environment or a provider container.
  ///
  /// A value that is not usable **falls back to [reported] rather than throwing.**
  /// Throwing would mean the app cannot start at all because of a string in a
  /// preferences file, and someone who cannot open their notes has no way to fix it
  /// from there. Falling back starts them in the default folder, where their notes
  /// still are, which is recoverable. [isUsableDirectory] still reports the bad
  /// value so the UI can say what happened rather than quietly disagreeing.
  static String configuredLocation({
    required String reported,
    required String? configured,
  }) {
    if (configured == null || !isUsableDirectory(configured)) return reported;
    return configured.trim();
  }

  /// Whether [path] names a directory this app is willing to read and write.
  ///
  /// Absolute, and no `..` — and those two are the whole rule. Both are about
  /// *intent*: a path someone typed, or a program chose, should name exactly one
  /// place. A relative path would resolve against the runner's working directory,
  /// and a `..` walks out of whatever was meant. In both cases nothing fails at the
  /// moment of setting it; the notes simply go somewhere else later.
  static bool isUsableDirectory(String path) {
    final trimmed = path.trim();
    // Three characters minimum: `X:\`. Anything shorter cannot name a directory.
    if (trimmed.length < 3) return false;
    if (trimmed[1] != r':' || trimmed[2] != r'\') return false;
    return !trimmed.contains('..');
  }

  /// Where the runner said to keep things: `%APPDATA%\WinNotes`.
  ///
  /// The runner creates it before Dart starts, because a widget that appears with a
  /// "cannot write" error is worse than one that appears late.
  ///
  /// **Always where `settings.json` is looked for**, whether or not a folder has been
  /// chosen. That file is the pointer to everything else, so it has to be findable
  /// before the pointer is known. `settings.json` in a chosen folder is read too, and
  /// preferred — see `docs/storage_pattern.md` §3.0a — so a chosen folder is
  /// self-contained and can be moved or backed up on its own.
  final String? reportedDirectory;

  /// Where files actually are.
  ///
  /// Equal to [reportedDirectory] unless a folder has been chosen, or
  /// [overrideVariable] is set for this run.
  final String dataDirectory;

  final String executablePath;

  /// Notes, the one file a person can find, read, back up or delete without
  /// this app in the way.
  String get notesFile => '$dataDirectory\\notes.json';

  /// Appearance, startup, hotkey, and where the person keeps their notes.
  ///
  /// Written to *both* [reportedDirectory] and [dataDirectory] — see
  /// `docs/storage_pattern.md` §3.0a. The copy in the default folder is the pointer
  /// that makes a chosen folder findable; the copy in the chosen folder is what makes
  /// that folder self-contained.
  String get settingsFile => '$dataDirectory\\settings.json';

  /// The pointer copy, always in the runner's directory. See [settingsFile].
  String get settingsPointerFile => '$reportedDirectory\\settings.json';

  /// Where the widget was left, and which monitor it was left on.
  String get widgetStateFile => '$dataDirectory\\widget_state.json';

  /// Which note is focused. Shared by both surfaces, so it gets its own tiny
  /// file rather than putting it in either surface's owned file.
  String get selectionFile => '$dataDirectory\\selection.json';

  /// `%APPDATA%\WinNotes`, the place to go back to.
  ///
  /// Not [reportedDirectory]: when an override is set for a run, "back to the default"
  /// means the real default rather than the override, which is a fact about the machine
  /// rather than about this run.
  String get defaultStorageDirectory =>
      reportedDirectory ?? dataDirectory;

  /// The same paths with a different data directory.
  ///
  /// Used once, in `main()`, to turn the runner's answer into the folder the person
  /// actually chose. Constructing a second `AppPaths` with the other field spelled out
  /// instead would be the same thing with a chance of forgetting one.
  AppPaths copyWith({String? dataDirectory, String? executablePath}) => AppPaths(
        dataDirectory: dataDirectory ?? this.dataDirectory,
        executablePath: executablePath ?? this.executablePath,
        reportedDirectory: reportedDirectory,
      );
}