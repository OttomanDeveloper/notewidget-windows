/// Where WinNotes keeps its files.
///
/// Resolved once from the native runner and passed down, rather than being
/// recomputed from `Platform.environment`, so there is exactly one place that
/// knows where notes live and a single place to change it.
class AppPaths {
  const AppPaths({required this.dataDirectory, required this.executablePath});

  /// Overrides the data directory. Set only by tooling that must not touch the
  /// real profile — see [resolve].
  ///
  /// Named for what it is rather than what it is for: it changes *where files go*,
  /// and nothing else. It does not change the format, the debounce, the recovery
  /// rules or anything the tests would then be measuring something other than the
  /// app.
  static const String overrideVariable = 'WIN_NOTES_DATA_DIR';

  /// The real directory when nothing has asked for another one.
  ///
  /// [reported] is what the runner told us, which is `%APPDATA%\WinNotes`.
  static AppPaths resolve({
    required String reported,
    required String executablePath,
    Map<String, String> environment = const {},
  }) {
    final override = environment[overrideVariable];
    if (override == null || override.trim().isEmpty) {
      return AppPaths(dataDirectory: reported, executablePath: executablePath);
    }

    // Absolute only, and no `..`. An override is supposed to name one directory
    // somewhere else; a relative one would resolve against whatever the runner's
    // working directory happens to be, and `..` would walk out of whatever the
    // caller intended. Refusing is better than quietly landing somewhere else,
    // because "somewhere else" is where notes get lost.
    final trimmed = override.trim();
    final absolute = trimmed.length > 2 && trimmed[1] == r':' && trimmed[2] == r'\';
    if (!absolute || trimmed.contains('..')) {
      throw ArgumentError.value(
        trimmed,
        overrideVariable,
        'must be an absolute Windows path with no ".." in it, '
            'e.g. C:\\Users\\someone\\AppData\\Local\\Temp\\winnotes-verify',
      );
    }
    return AppPaths(dataDirectory: trimmed, executablePath: executablePath);
  }

  /// The directory the native runner handed us: %APPDATA%\WinNotes.
  ///
  /// The runner creates it before Dart starts, because a widget that appears
  /// with an "cannot write" error is worse than one that appears late.
  ///
  /// Not the real directory when [overrideVariable] is set — see [resolve].
  final String dataDirectory;

  final String executablePath;

  /// Notes, the one file a person can find, read, back up or delete without
  /// this app in the way.
  String get notesFile => '$dataDirectory\\notes.json';

  /// Appearance, startup, hotkey and storage location.
  String get settingsFile => '$dataDirectory\\settings.json';

  /// Where the widget was left, and which monitor it was left on.
  String get widgetStateFile => '$dataDirectory\\widget_state.json';

  /// Which note is focused. Shared by both surfaces, so it gets its own tiny
  /// file rather than putting it in either surface's owned file.
  String get selectionFile => '$dataDirectory\\selection.json';

  String get defaultStorageDirectory => dataDirectory;
}