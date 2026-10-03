import 'dart:io';

import 'package:flutter/material.dart';

import 'src/core/app_paths.dart';
import 'src/platform/shell_channel.dart';
import 'src/ui/editor/editor_app.dart';
import 'src/ui/theme.dart';
import 'src/ui/widget/widget_app.dart';

/// Entry point for both surfaces.
///
/// The runner creates two Windows windows, each with its own Flutter engine and
/// its own isolate, and both call `main()`. The `--surface` argument decides
/// which one this is. That is why there is no second entrypoint to keep in sync
/// with this one: the same bootstrapping runs on both sides and only the surface
/// differs.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final shell = ShellChannel();
  final launch = await shell.bootstrap();

  // No runner means `flutter test`, or a stale build. Either way there is no
  // desktop to put a window on, so a neutral editor keeps the failure visible
  // instead of crashing on a null.
  if (launch == null) {
    runApp(_ShellMissingApp());
    return;
  }

  final paths = AppPaths(
    dataDirectory: launch.dataDirectory,
    executablePath: launch.executablePath,
  );

  // Belt and braces: the runner also creates the directory before Dart starts,
  // but a data directory that does not exist means every read is a silent miss.
  Directory(launch.dataDirectory).createSync(recursive: true);

  if (launch.isWidgetSurface) {
    runApp(WidgetApp(shell: shell, launch: launch, paths: paths));
  } else {
    runApp(EditorApp(shell: shell, launch: launch, paths: paths));
  }
}

/// Shown when the native runner is not present.
class _ShellMissingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildWinNotesTheme(brightness: Brightness.light, highContrast: false),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.desktop_access_disabled, size: 40),
                SizedBox(height: 16),
                Text(
                  'WinNotes could not reach the Windows runner.',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'The app has to be built as a Windows executable; running it '
                  'any other way leaves nothing to draw a window on.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}