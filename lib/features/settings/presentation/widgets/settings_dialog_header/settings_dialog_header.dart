import 'package:flutter/material.dart';

class SettingsDialogHeader extends StatelessWidget {
  const SettingsDialogHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: <Widget>[
          Text(
            'Settings',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close settings',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
