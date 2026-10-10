/// Where WinNotes keeps its files: the runner's directory for the pointer, and
/// the data directory for everything else. Resolved once, so one place knows
/// where notes live. Collapsing them loses custom locations silently.
class AppPaths {
  const AppPaths({
    required this.dataDirectory,
    required this.executablePath,
    this.reportedDirectory,
    this.unreachableDirectory,
  });

  /// Overrides the data directory for one run. Tooling only: it changes where
  /// files go, and nothing else.
  static const String overrideVariable = 'WIN_NOTES_DATA_DIR';

  /// Paths for a normal launch: the runner's report, the override, then any
  /// folder chosen in Settings. [configured] is null when there is none.
  static AppPaths resolve({
    required String reported,
    required String executablePath,
    Map<String, String> environment = const <String, String>{},
    String? configured,
  }) {
    final String? override = environment[overrideVariable];

    // An override outranks a saved preference: the person running the program
    // names the folder for this run, which beats a months-old setting.
    if (override != null && override.trim().isNotEmpty) {
      final String trimmed = override.trim();
      // Absolute only, no `..`: anything else lands somewhere unasked-for,
      // which is where notes get lost.
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

  /// The directory chosen in Settings, or [reported]. Pure, so the rule has one
  /// definition testable without a runner. Unusable values fall back rather than
  /// throwing: no preference string may prevent startup.
  static String configuredLocation({
    required String reported,
    required String? configured,
  }) {
    if (configured == null || !isUsableDirectory(configured)) return reported;
    return configured.trim();
  }

  /// Whether [path] names a directory we read and write: absolute, no `..`.
  /// Anything else resolves somewhere unasked-for, silently.
  static bool isUsableDirectory(String path) {
    final String trimmed = path.trim();
    // Three characters minimum: `X:\`. Anything shorter cannot name a directory.
    if (trimmed.length < 3) return false;
    if (trimmed[1] != r':' || trimmed[2] != r'\') return false;
    return !trimmed.contains('..');
  }

  /// Where the runner said to keep things. Always where `settings.json` is
  /// looked for: that file is the pointer to everything else (`§3.0a`).
  final String? reportedDirectory;

  /// A folder chosen in Settings that could not be reached at launch, or null.
  /// Carried, not acted on: [dataDirectory] is still the fallback, so a missing
  /// drive is never recreated. `storage_pattern.md` §3.0a.
  final String? unreachableDirectory;

  /// Where files actually are: [reportedDirectory], a chosen folder, or the
  /// run's [overrideVariable].
  final String dataDirectory;

  final String executablePath;

  /// Notes, the one file a person can find, read, back up or delete without
  /// this app in the way.
  String get notesFile => '$dataDirectory\\notes.json';

  /// Appearance, startup, hotkey, and notes location. Written to both folders
  /// (`§3.0a`): the default copy is the pointer, the chosen copy stands alone.
  String get settingsFile => '$dataDirectory\\settings.json';

  /// The pointer copy, always in the runner's directory. See [settingsFile].
  String get settingsPointerFile => '$reportedDirectory\\settings.json';

  /// Where the widget was left, and which monitor it was left on.
  String get widgetStateFile => '$dataDirectory\\widget_state.json';

  /// Which note is focused. Shared by both surfaces, so it gets its own tiny
  /// file rather than putting it in either surface's owned file.
  String get selectionFile => '$dataDirectory\\selection.json';

  /// Where crashes are appended. Not a data file: nothing reads it back, and
  /// losing it costs nothing (`docs/storage_pattern.md` §3.13a).
  String get crashLogFile => '$dataDirectory\\crash.log';

  /// `%APPDATA%\WinNotes`. Not [reportedDirectory]: under an override, "back to
  /// the default" means the machine's default, not this run's.
  String get defaultStorageDirectory =>
      reportedDirectory ?? dataDirectory;

  /// The same paths with a different data directory. Used once, in `main()`,
  /// to turn the runner's answer into the chosen folder.
  AppPaths copyWith({String? dataDirectory, String? executablePath, String? unreachableDirectory}) => AppPaths(
        dataDirectory: dataDirectory ?? this.dataDirectory,
        executablePath: executablePath ?? this.executablePath,
        reportedDirectory: reportedDirectory,
        unreachableDirectory: unreachableDirectory ?? this.unreachableDirectory,
      );
}
