import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Shown when the native runner is not present.
class ShellMissingApp extends StatelessWidget {
  const ShellMissingApp({super.key});

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
              children: <Widget>[
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
