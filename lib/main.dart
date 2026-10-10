import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'core/utils/app_paths.dart';
import 'core/utils/crash_log.dart';
import 'core/utils/diagnostics.dart';
import 'core/utils/frame_log.dart';
import './features/settings/data/storage_location.dart';
import './core/platform/shell_channel.dart';
import './core/utils/app_providers.dart';
import './features/notes/presentation/screens/editor_app/editor_app.dart';
import 'core/widgets/shell_missing_app/shell_missing_app.dart';
import './features/widget/presentation/screens/widget_app/widget_app.dart';

/// Entry point for both surfaces: two Windows windows, two isolates, one `main()`.
/// `--surface` picks the surface, so no second entrypoint to keep in sync.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final ShellChannel shell = ShellChannel();
  final LaunchInfo? launch = await shell.bootstrap();

  // No runner means `flutter test`, or a stale build. Either way there is no
  // desktop to put a window on, so a neutral editor keeps the failure visible
  // instead of crashing on a null.
  if (launch == null) {
    runApp(const ProviderScope(child: ShellMissingApp()));
    return;
  }

  // Two steps: reported paths first (settings.json lives there and names the
  // real folder), then real paths. Without the second step the Storage picker
  // saved a path while every file still went to `%APPDATA%\WinNotes`.
  final AppPaths reported = AppPaths.resolve(
    reported: launch.dataDirectory,
    executablePath: launch.executablePath,
    // Read once, from the real environment rather than injected, because this is
    // the entry point and there is nothing above it to pass anything down. Tests do
    // not come through here; they override `appPathsProvider` instead.
    environment: Platform.environment,
  );

  final AppPaths paths = reported.copyWith(
    dataDirectory: StorageLocation.resolveDataDirectory(reported),
    // Kept rather than resolved away: an unreachable chosen folder makes the
    // resolver fall back to the default - right for reading, wrong for writing.
    // Carried so the editor says where the notes are (`storage_pattern.md` §3.0a).
    unreachableDirectory: StorageLocation.unreachableChoice(reported),
  );

  // `paths.dataDirectory`, not `launch.dataDirectory`: with `WIN_NOTES_DATA_DIR`
  // set they differ, and creating the reported one would touch the real profile
  // the override exists to avoid.
  Directory(paths.dataDirectory).createSync(recursive: true);

  // Installed here because this is the only point both surfaces share, and
  // before `runApp` because a build failure throws inside `runApp` and a
  // release build has no console to print it to (`docs/storage_pattern.md` §3.13a).
  installCrashHandlers(CrashLog(paths.crashLogFile));

  // Before `runApp`, and off unless `WIN_NOTES_FRAME_LOG` names a file. A widget
  // test cannot see a stall that lives in real file IO or the platform
  // text-input path, and two fixes aimed at the wrong place were green all along.
  FrameLog.attachIfEnabled();

  // `win_notes.exe --diagnose <path>`: write one snapshot and exit. Read from
  // the launch report, not `args` - the runner owns the Dart entrypoint
  // arguments and the process command line never reaches them.
  if (launch.diagnosePath.isNotEmpty) {
    // Built directly, not through a container: all three values are already
    // local, and a container built only to dispose would make the Riverpod lint
    // read `main` as a root that is not a `ProviderScope`.
    await Diagnostics(shell, paths, launch).writeTo(launch.diagnosePath);
    exit(0);
  }

  // The `ProviderScope` lives here so both roots take no parameters (`AGENTS.md`
  // §0.8). The three overrides are what a container can't discover: channel,
  // launch report, and file paths. One scope per isolate (`docs/isolate_pattern.md` §2).
  runApp(
    ProviderScope(
// ignore: always_specify_types - Override is not public in flutter_riverpod either.
      overrides: [
        shellProvider.overrideWithValue(shell),
        launchInfoProvider.overrideWithValue(launch),
        appPathsProvider.overrideWithValue(paths),
      ],
      child: launch.isWidgetSurface ? const WidgetApp() : const EditorApp(),
    ),
  );
}
