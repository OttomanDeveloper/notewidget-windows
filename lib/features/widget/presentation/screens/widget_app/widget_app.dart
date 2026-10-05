import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widget_scope/widget_scope.dart';

/// Root widget for the widget surface.
///
/// Runs in its own isolate, reads the same files the editor writes, and never
/// writes notes. There is one writer per file in this app and this side owns only
/// `widget_state.json`.
///
/// Now a `ConsumerWidget` creating its own `ProviderScope`, against the same
/// declarations the editor uses. That is what `docs/isolate_pattern.md` §3.1 asked
/// for: the two surfaces build one graph rather than each writing its own, so the
/// three copies of `_resolveBrightness` that disagreed with each other are now one
/// provider (`AGENTS.md` §4.7).
class WidgetApp extends ConsumerWidget {
  const WidgetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const WidgetScope();
}
