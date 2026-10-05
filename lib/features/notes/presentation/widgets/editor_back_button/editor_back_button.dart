import 'package:flutter/material.dart';

class EditorBackButton extends StatelessWidget {
  const EditorBackButton({super.key, required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to notes',
            onPressed: onBack,
          ),
        ),
      );
}
