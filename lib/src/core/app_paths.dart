/// Where WinNotes keeps its files.
///
/// Resolved once from the native runner and passed down, rather than being
/// recomputed from `Platform.environment`, so there is exactly one place that
/// knows where notes live and a single place to change it.
class AppPaths {
  const AppPaths({required this.dataDirectory, required this.executablePath});

  /// The directory the native runner handed us: %APPDATA%\WinNotes.
  ///
  /// The runner creates it before Dart starts, because a widget that appears
  /// with an "cannot write" error is worse than one that appears late.
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