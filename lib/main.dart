import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/utils/app_paths.dart';
import './features/settings/data/storage_location.dart';
import './core/platform/shell_channel.dart';
import './core/utils/app_providers.dart';
import './features/notes/presentation/screens/editor_app/editor_app.dart';
import 'core/widgets/shell_missing/shell_missing_app.dart';
import './features/widget/presentation/screens/widget_app/widget_app.dart';

/// Entry point for both surfaces: two Windows windows, two isolates, one `main()`.
/// `--surface` picks the surface, so no second entrypoint to keep in sync.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final shell = ShellChannel();
  final launch = await shell.bootstrap();

  // No runner means `flutter test`, or a stale build. Either way there is no
  // desktop to put a window on, so a neutral editor keeps the failure visible
  // instead of crashing on a null.
  if (launch == null) {
    runApp(const ShellMissingApp());
    return;
  }

  // Two steps: reported paths first (settings.json lives there and names the
  // real folder), then real paths. Without the second step the Storage picker
  // saved a path while every file still went to `%APPDATA%\WinNotes`.
  final reported = AppPaths.resolve(
    reported: launch.dataDirectory,
    executablePath: launch.executablePath,
    // Read once, from the real environment rather than injected, because this is
    // the entry point and there is nothing above it to pass anything down. Tests do
    // not come through here; they override `appPathsProvider` instead.
    environment: Platform.environment,
  );

  final paths = reported.copyWith(
    dataDirectory: StorageLocation.resolveDataDirectory(reported),
  );

  // `paths.dataDirectory`, not `launch.dataDirectory`: with `WIN_NOTES_DATA_DIR`
  // set they differ, and creating the reported one would touch the real profile
  // the override exists to avoid.
  Directory(paths.dataDirectory).createSync(recursive: true);

  // The `ProviderScope` lives here so both roots take no parameters (`AGENTS.md`
  // §0.8). The three overrides are what a container can't discover: channel,
  // launch report, and file paths. One scope per isolate (`docs/isolate_pattern.md` §2).
  runApp(
    ProviderScope(
      overrides: [
        shellProvider.overrideWithValue(shell),
        launchInfoProvider.overrideWithValue(launch),
        appPathsProvider.overrideWithValue(paths),
      ],
      child: launch.isWidgetSurface ? const WidgetApp() : const EditorApp(),
    ),
  );
}