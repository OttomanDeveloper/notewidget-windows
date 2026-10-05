import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor_scope/editor_scope.dart';

/// Root widget for the editor surface.
///
/// Owns notes.json and settings.json. The widget surface reads both and writes
/// neither, which is the whole reason there is no cross-isolate merge logic
/// anywhere in this project.
///
/// Now a `ConsumerWidget` over a `ProviderScope` it creates itself, rather than a
/// `StatefulWidget` that constructed four repositories in `initState` and disposed
/// them in `dispose`. Three things follow, and they are the reason this file is 285
/// lines shorter than it was:
///
///  - `_resolveBrightness` and `_systemBrightness` are gone. Both surfaces now
///    resolve the theme through `widgetSurfaceThemeProvider`, which is what
///    stopped the three divergent copies (`AGENTS.md` §4.7).
///  - The `GlobalKey<NavigatorState>` is gone. It existed because this State was
///    *also* the app root, so its own `context` sat above the `MaterialApp` it
///    returned and had no `Navigator` ancestor - which is why Settings appeared to
///    do nothing. A `ConsumerWidget` below the `MaterialApp` has an ordinary context.
///  - The seven `unawaited(...flush())` calls are now one call to a provider's
///    `flush`, and still unawaited. `AGENTS.md` §4.7: `onDispose` is synchronous,
///    so this hazard is unchanged by the rewrite and is recorded rather than fixed.
class EditorApp extends ConsumerWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const EditorScope();
}
