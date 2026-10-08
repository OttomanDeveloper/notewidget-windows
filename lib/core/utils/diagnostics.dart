import 'dart:convert';
import 'dart:io';

import 'package:riverpod/riverpod.dart';

import '../platform/shell_channel.dart';
import 'app_paths.dart';
import 'app_providers.dart';

/// Writes a one-shot snapshot of what diagnoses a "nothing happens" report.
/// On demand, never on a schedule: `docs/storage_pattern.md` §3.13b has why.
class Diagnostics {
  const Diagnostics(this._shell, this._paths, this._launch);

  final ShellChannel _shell;
  final AppPaths _paths;
  final LaunchInfo _launch;

  /// Assembles the report. Does not throw: a dump that fails is the one moment
  /// it must not, because the failure is usually the thing being diagnosed.
  Future<Map<String, dynamic>> collect() async {
    final Map<String, dynamic> dump = <String, dynamic>{
      'writtenAt': DateTime.now().toUtc().toIso8601String(),
      'profile': _profile(),
      'runner': await _runnerFacts(),
    };
    return dump;
  }

  Future<void> writeTo(String path) async {
    final Map<String, dynamic> dump = await collect();
    try {
      final File file = File(path);
      // The caller names the file, not the directory they want it in. Without
      // this a missing parent throws and the catch below hides it, so "no
      // exception" reads as "the dump was written" when nothing was.
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(dump)}\n',
        flush: true,
      );
    } on Object {
      // An unwritable destination is reported by the absence of the file, and
      // there is nowhere else to say so.
    }
  }

  Map<String, dynamic> _profile() {
    final Map<String, dynamic> profile = <String, dynamic>{
      'dataDirectory': _paths.dataDirectory,
      'files': <String, dynamic>{},
    };
    final Map<String, dynamic> files = profile['files']! as Map<String, dynamic>;
    // Sizes and parse verdicts, never contents. A corrupt file is the single
    // most useful thing to learn and needs no content to say it.
    for (final MapEntry<String, String> entry in <MapEntry<String, String>>[
      MapEntry<String, String>('notes', _paths.notesFile),
      MapEntry<String, String>('settings', _paths.settingsFile),
      MapEntry<String, String>('widgetState', _paths.widgetStateFile),
      MapEntry<String, String>('selection', _paths.selectionFile),
    ]) {
      files[entry.key] = _describeFile(entry.value);
    }
    return profile;
  }

  Map<String, dynamic> _describeFile(String path) {
    final File file = File(path);
    if (!file.existsSync()) {
      return <String, dynamic>{'exists': false};
    }
    final Map<String, dynamic> described = <String, dynamic>{
      'exists': true,
      'bytes': file.lengthSync(),
      'modified': file.lastModifiedSync().toUtc().toIso8601String(),
    };
    try {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      described['parses'] = true;
      if (decoded is List) described['entries'] = decoded.length;
    } on Object {
      described['parses'] = false;
    }
    return described;
  }

  /// The autostart half is the point: `syncPlatform()` only runs when the app
  /// starts, so a stale registry entry cannot repair itself, and "does not
  /// survive the restart" was unanswerable without seeing both sides at once.
  Future<Map<String, dynamic>> _runnerFacts() async {
    final Map<String, dynamic> facts = <String, dynamic>{
      'launchMode': _launch.launchMode,
      'role': _launch.role,
      'monitors': <Map<String, int>>[
        for (final MonitorInfo m in _launch.monitors)
          <String, int>{
            'left': m.left,
            'top': m.top,
            'width': m.width,
            'height': m.height,
          },
      ],
      'defaultWidgetBounds': <String, int>{
        'left': _launch.defaultWidgetBounds.left,
        'top': _launch.defaultWidgetBounds.top,
        'width': _launch.defaultWidgetBounds.width,
        'height': _launch.defaultWidgetBounds.height,
      },
      'autostartEnabled': _launch.autostartEnabled,
      // What the app would write. NOT what the registry holds - see
      // [_autostartTargetExists], which reads the entry back for that reason.
      'autostartCommand': _launch.autostartCommand,
      'autostartRegistryEntry': _readRunEntry(),
      'autostartTargetExists': _autostartTargetExists(),
      'executablePath': _launch.executablePath,
      'acrylicSupported': _launch.acrylicSupported,
      'highContrast': _launch.highContrast,
    };
    try {
      // A map, not the `NativeBounds`: `jsonEncode` throws on an arbitrary
      // object, and `writeTo`'s catch would swallow that, leaving no file and
      // no error. Everything here has to be plain JSON.
      final NativeBounds? live = await _shell.widgetBounds();
      facts['liveWidgetBounds'] = live == null
          ? null
          : <String, int>{
              'left': live.left,
              'top': live.top,
              'width': live.width,
              'height': live.height,
            };
    } on Object {
      facts['liveWidgetBounds'] = null;
    }
    return facts;
  }

  /// Whether the path the Run key *holds* exists. Not `_launch.autostartCommand`,
  /// which is what the app would write from its own exe path — WN-DIAG-003.
  bool _autostartTargetExists() {
    try {
      final String? entry = _readRunEntry();
      if (entry == null || entry.isEmpty) return false;
      return File(_executableFrom(entry)).existsSync();
    } on Object {
      return false;
    }
  }

  /// `reg query` separates columns with runs of spaces. Hoisted: a pattern is
  /// constant (§3.5).
  static final RegExp _columnGap = RegExp(r'\s{2,}');

  /// The `WinNotes` value under `HKCU\…\Run`, or null when absent. `reg query`
  /// rather than a registry package: §0.4 enumerates the dependencies.
  static String? _readRunEntry() {
    final ProcessResult result = Process.runSync(
      'reg',
      <String>['query', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run', '/v', 'WinNotes'],
    );
    if (result.exitCode != 0) return null;
    for (final String line in (result.stdout as String).split('\n')) {
      if (!line.trimLeft().startsWith('WinNotes')) continue;
      final List<String> parts = line.trim().split(_columnGap);
      return parts.length >= 3 ? parts.sublist(2).join(' ').trim() : null;
    }
    return null;
  }

  static String _executableFrom(String entry) {
    final String command = entry.trim();
    if (command.startsWith('"')) {
      final int close = command.indexOf('"', 1);
      return close < 0 ? command : command.substring(1, close);
    }
    final int space = command.indexOf(' ');
    return space < 0 ? command : command.substring(0, space);
  }
}

final Provider<Diagnostics> diagnosticsProvider = Provider<Diagnostics>(
  (Ref ref) => Diagnostics(
    ref.watch(shellProvider),
    ref.watch(appPathsProvider),
    ref.watch(launchInfoProvider),
  ),
);
