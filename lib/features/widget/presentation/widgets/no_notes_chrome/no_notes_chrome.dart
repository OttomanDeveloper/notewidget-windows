import 'package:flutter/material.dart';

import '../../../../../core/theme/theme.dart';

class NoNotesChrome extends StatelessWidget {
  const NoNotesChrome({super.key, required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final muted = widgetMutedColor(dark ? Brightness.dark : Brightness.light);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No notes',
          style: TextStyle(color: muted, fontSize: 13),
        ),
      ),
    );
  }
}
