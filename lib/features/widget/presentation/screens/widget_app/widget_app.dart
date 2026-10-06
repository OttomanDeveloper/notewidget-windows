import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widget_scope/widget_scope.dart';

/// Root widget for the widget surface. Own isolate, same files; owns only
/// `widget_state.json` (one writer per file). Same declarations as the editor:
/// one graph, one brightness provider (`AGENTS.md` §4.7).
class WidgetApp extends ConsumerWidget {
  const WidgetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const WidgetScope();
}
