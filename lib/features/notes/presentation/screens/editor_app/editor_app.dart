import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor_scope/editor_scope.dart';

/// Root widget for the editor surface. Owns both files; the widget reads them,
/// which is why there is no cross-isolate merge logic. One graph, not two: the
/// divergent brightness copies are one provider (`AGENTS.md` §4.7).
class EditorApp extends ConsumerWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const EditorScope();
}
