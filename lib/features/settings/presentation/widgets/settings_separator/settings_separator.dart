import 'package:flutter/material.dart';

class SettingsSeparator extends StatelessWidget {
  const SettingsSeparator({super.key});
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Theme.of(context).dividerColor);
}
