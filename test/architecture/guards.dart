/// Scans the source tree for rules that are architectural rather than
/// behavioural.
///
/// These exist because `docs/*_pattern.md` says things that a reader has no way
/// to check. A rule written in prose stops being true the moment someone is in a
/// hurry, and nothing fails. Each test here is the mechanical form of one line
/// of a pattern doc.
///
/// Two rules govern this file:
///
/// * **It reads files as text. It never imports `lib/`.** A guard that links
///   the code it guards cannot survive the code being refactored, and a
///   refactor is exactly when the guard is needed.
/// * **It has to be provably non-inert.** A scanner that cannot fail is worse
///   than no scanner, because it reads as enforcement. Every guard here has a
///   matching test that feeds it known-bad input and asserts it rejects it — see
///   `guards_test.dart`. That is the practice borrowed from
///   `docs/storage_pattern.md` §4, applied to itself.
library;

import 'dart:io';

/// One place that knows where the sources are and how to read them, so a rule
/// change is one edit rather than seven.
class SourceTree {
  SourceTree([String? root]) : root = root ?? _findRoot();

  /// The repository root: the nearest ancestor of the current directory that
  /// contains `pubspec.yaml`.
  final String root;

  static String _findRoot() {
    Directory dir = Directory.current;
    for (int i = 0; i < 8; i++) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
      dir = dir.parent;
    }
    throw StateError('Could not find pubspec.yaml above ${Directory.current.path}');
  }

  /// Every `.dart` file under [relative], as `path -> lines`.
  ///
  /// Absolute paths on Windows carry a backslash, and comparing them with a
  /// forward-slash literal silently matches nothing. Normalising here is what
  /// stops a guard passing vacuously.
  Map<String, List<String>> dartFilesUnder(String relative) {
    final Directory base = Directory('$root/$relative');
    if (!base.existsSync()) {
      throw StateError('No such directory: $relative');
    }
    final Map<String, List<String>> out = <String, List<String>>{};
    for (final FileSystemEntity entity in base.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      out[entity.path] = entity.readAsLinesSync();
    }
    return out;
  }

  String read(String relative) =>
      File('$root/$relative').readAsStringSync();

  /// The bytes of a file, for checking binary structure.
  ///
  /// Separate from [read] because a `.ico` is not text and reading one as a string
  /// loses the bytes above 0x7F - which for a PNG-backed icon is most of the file, and
  /// would make every frame size read as 0.
  List<int> readBytes(String relative) =>
      File('$root/$relative').readAsBytesSync();

  /// Project-relative path for [absolute], with forward slashes.
  ///
  /// `dartFilesUnder` keys by `entity.path`, which on Windows is absolute and
  /// backslashed. Anything comparing those keys against a set of repo-relative names
  /// - a list of files that are allowed to do something - matches nothing, finds
  /// nothing wrong, and reports a clean scan. That is the worst way for a guard to
  /// fail, so the normalisation lives here and is used by name rather than re-derived
  /// per guard; two guards each doing it by hand is how they came to disagree.
  String relativePath(String absolute) {
    final String full = absolute.replaceAll(r'\', '/');
    final String base = root.replaceAll(r'\', '/');
    return full.startsWith('$base/') ? full.substring(base.length + 1) : full;
  }

  /// As [dartFilesUnder], keyed by repo-relative path with forward slashes.
  Map<String, List<String>> dartFilesUnderRelative(String relative) => <String, List<String>>{
        for (final MapEntry<String, List<String>> entry in dartFilesUnder(relative).entries)
          relativePath(entry.key): entry.value,
      };

  String get runnerSource {
    final Directory dir = Directory('$root/windows/runner');
    if (!dir.existsSync()) return '';
    return dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.cpp') || f.path.endsWith('.h'))
        .map((File f) => f.readAsStringSync())
        .join('\n');
  }

  bool exists(String relative) =>
      File('$root/$relative').existsSync() || Directory('$root/$relative').existsSync();
}

// --- Rule scanners -----------------------------------------------------------
// Each returns the violations it found, so the calling test can print them
// properly. A scanner that only returns a bool forces every failure message to
// be reconstructed inside the scanner, which is where good messages go to die.

/// The subset of [layers] that exists on disk.
///
/// Widget dirs appear as the splits land (`settings/presentation/widgets` does
/// not exist until the dialog is split). Throwing on a missing dir would make
/// every widget split a guard fix first; silently defaulting would hide a typo.
/// The middle ground: skip what is absent, and let the decision table say which
/// dirs are expected to exist by the end.
List<String> _existingLayers(SourceTree tree, List<String> layers) =>
    layers.where(tree.exists).toList();

/// `dart:io` file operations are confined to `core/` and `data/`.
///
/// `docs/storage_pattern.md` §6 and `AGENTS.md` §3.
///
/// The write case is the one that bites: a `File(path).writeAsString` in a
/// widget is not atomic, so an interrupted write leaves a truncated file — and
/// for an export that file is what someone reaches for when everything else has
/// failed. The reads are untidy rather than hazardous, which is why the rule is
/// absolute anyway: a threshold is a negotiation, and this one has been settled.
List<String> findFileOperationsOutsideDataLayer(SourceTree tree) {
  // `.copy(` and `.rename(` are deliberately absent. They look like file
  // operations and are not: `Note.copy()` is a model clone, and it was the
  // first false positive this scanner produced. They cannot be reached without
  // a `File(` or `Directory(` somewhere first, which is already matched, so
  // listing them buys a false positive and no coverage.
  final RegExp banned = RegExp(
    r'''\b(File|Directory|Link)\s*\(|\.writeAsString|\.readAsString|'''
    r'''\.writeAsBytes|\.readAsBytes|\.existsSync|\.lengthSync|'''
    r'''\.lastModifiedSync|\.createSync''',
  );
  final List<String> violations = <String>[];
  for (final String layer in _existingLayers(tree, <String>[
    'lib/features/notes/presentation',
    'lib/features/widget/presentation',
    'lib/features/settings/presentation',
    'lib/core/platform',
    'lib/core/widgets',
  ])) {
    for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder(layer).entries) {
      // Comments are allowed to say "dart:io" — two of ours do, and both do it
      // to explain why the UI must not use it. Only real code counts.
      final String code = entry.value
          .where((String line) => !line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('*'))
          .join('\n');
      for (int i = 0; i < code.split('\n').length; i++) {
        final String line = code.split('\n')[i];
        if (banned.hasMatch(line)) {
          violations.add('${_rel(tree, entry.key)}:${i + 1}  ${line.trim()}');
        }
      }
    }
  }
  return violations;
}

/// Only `core/platform` constructs a `MethodChannel`.
///
/// `AGENTS.md` §3. Everything else goes through `ShellChannel`, so that the set
/// of method names lives in one file and can be checked against the runner.
List<String> findChannelsOutsidePlatform(SourceTree tree) {
  final List<String> violations = <String>[];
  for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder('lib').entries) {
    if (entry.key.replaceAll(r'\', '/').contains('/core/platform/')) continue;
    for (int i = 0; i < entry.value.length; i++) {
      final String line = entry.value[i];
      if (line.trimLeft().startsWith('//')) continue;
      if (RegExp(r'\bMethodChannel\s*\(').hasMatch(line)) {
        violations.add('${_rel(tree, entry.key)}:${i + 1}  ${line.trim()}');
      }
    }
  }
  return violations;
}

/// Every method name called from Dart is handled by the runner.
///
/// `AGENTS.md` §3. A name added on one side only is a silent no-op: the runner
/// answers `result->Success()` either way, so the Dart `await` completes and
/// nothing happens. That is why this is worth a scanner rather than a note.
///
/// Both entry points are matched — `_fire` and `_invoke` — because missing the
/// second one makes eleven methods look dead, which is exactly the false
/// positive this rule has already produced once.
Set<String> dartMethodNames(SourceTree tree) {
  final Set<String> names = <String>{};
  final RegExp literal = RegExp(r"""_fire\(\s*'([^']+)'""");
  final RegExp invoke = RegExp(r"""_invoke(?:<[^>]*>)?\(\s*'([^']+)'""");
  for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder('lib').entries) {
    for (final String line in entry.value) {
      for (final RegExpMatch m in literal.allMatches(line)) {
        names.add(m.group(1)!);
      }
      for (final RegExpMatch m in invoke.allMatches(line)) {
        names.add(m.group(1)!);
      }
    }
  }
  return names;
}

/// Method names the runner compares against.
Set<String> runnerMethodNames(SourceTree tree) {
  return RegExp(r'method\s*==\s*"([^"]+)"')
      .allMatches(tree.runnerSource)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}

/// The widget must never answer `HTCAPTION`.
///
/// `docs/widget_pattern.md` §3.1. This is the guard that matters most out of
/// all of them, because the failure it prevents is silent and total: with
/// `HTCAPTION` over the body the widget cannot be dragged, cards cannot be
/// tapped, and nothing throws. It shipped that way for the life of the project.
///
/// Scanned as text because it is a claim about code that no Dart test can
/// reach, and because the alternative — an integration test that drags the real
/// window — is exactly the tier `docs/testing_pattern.md` §2 records as not in
/// CI.
List<String> findCaptionHits(SourceTree tree) {
  final String source = tree.runnerSource;
  final List<String> violations = <String>[];
  // Strip line comments so the explanatory prose in HitTest, which mentions
  // HTCAPTION four times on purpose, does not trip the guard it is describing.
  final String code = source
      .split('\n')
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  for (final RegExpMatch m in RegExp(r'HTCAPTION').allMatches(code)) {
    final int line = code.substring(0, m.start).split('\n').length;
    final String text = code.split('\n')[line - 1].trim();
    violations.add('windows/runner: $line  $text');
  }
  // The mirror image is also forbidden: HTTOPLEFT and friends would resize the
  // window from a corner Dart already owns, and would fight the gesture.
  for (final String final_ in <String>['HTTOP', 'HTTOPLEFT', 'HTTOPRIGHT', 'HTBOTTOM',
      'HTBOTTOMLEFT', 'HTBOTTOMRIGHT', 'HTLEFT', 'HTRIGHT']) {
    if (RegExp('return\\s+$final_\\b').hasMatch(code)) {
      violations.add('windows/runner  returns $final_');
    }
  }
  return violations;
}

/// Ways the widget can end up above the editor, or below where it belongs.
///
/// `docs/widget_pattern.md` §3.17. Two separate faults, and the second is the
/// one that a partial fix leaves behind:
///
///  1. The editor being topmost. It is not — `StyleForRole` gives it no
///     `WS_EX_TOPMOST` — so this is the easy half, and it is checked because
///     "add the flag to the editor too" is such an obvious-looking wrong turn.
///  2. Demoting the widget *without* raising the editor. Taking the widget out
///     of the topmost band leaves it at the top of the ordinary band, which is
///     still above the editor — measured on a release build, not assumed from
///     the documentation. So the widget covers the editor *and* buries it, and
///     the symptom looks worse than before the fix rather than better.
///
/// Returns a list of human-readable faults; empty means the rule holds.
///
/// Takes the two runner sources as text rather than a [SourceTree], so a fault
/// can be injected without editing the repository. A guard that can only be
/// tested by breaking the real thing is a guard that gets left untested.
List<String> findWidgetAboveEditorFaults(String window, String host) {
  final List<String> faults = <String>[];

  /// The body of `signature`, or an empty string if it cannot be found.
  ///
  /// The parameter list is matched loosely and skipped: the signatures here are
  /// long, and a guard that has to be updated every time a parameter is added
  /// is a guard that will be deleted instead. An empty result is itself treated
  /// as a fault, so a regex that quietly stops matching fails loudly rather than
  /// reporting a clean bill of health.
  ///
  /// The closing brace is anchored to column 0 on purpose. Every nested block in
  /// this runner is indented, so column 0 is the end of the function and
  /// nothing else.
  String body(String source, String signature) {
    final String pattern =
        '${RegExp.escape(signature)}\\s*\\([^)]*\\)\\s*\\{(.*?)\\n\\}';
    return RegExp(pattern, dotAll: true).firstMatch(source)?.group(1) ?? '';
  }

  // 1. The editor must never be created topmost.
  final String style = body(window, 'void Window::StyleForRole');
  final String editorBranch = style.split('} else {').length > 1
      ? style.split('} else {').last
      : '';
  if (editorBranch.isEmpty) {
    faults.add(
      'StyleForRole has no editor branch, so the rule cannot be checked. '
      'If the roles were merged this guard is now vacuous.',
    );
  } else if (RegExp(r'WS_EX_TOPMOST').hasMatch(editorBranch)) {
    faults.add(
      'StyleForRole gives the editor WS_EX_TOPMOST. The editor is the window '
      'someone is deliberately looking at; it must behave like any other '
      'application window and sit behind other applications when they are '
      'raised.',
    );
  }

  // 2. SetAlwaysOnTop must stay widget-only, or toggling the setting would
  //    reach the editor through the back door.
  final String alwaysOnTop = body(window, 'void Window::SetAlwaysOnTop');
  if (alwaysOnTop.isEmpty) {
    faults.add('Window::SetAlwaysOnTop has gone; the guard cannot check it.');
  } else if (!RegExp(r'IsWidgetRole').hasMatch(alwaysOnTop)) {
    faults.add(
      'Window::SetAlwaysOnTop no longer checks IsWidgetRole, so the '
      'always-on-top setting can reach the editor.',
    );
  }

  // 3. The host must react to the editor being foreground at all.
  //
  // Matched as the *definition*, not the bare name. A loose `contains` would be
  // satisfied by the mention in a comment, so renaming the handler would leave
  // the guard reporting a rule that is no longer implemented.
  if (!RegExp(r'case WM_ACTIVATE').hasMatch(window)) {
    faults.add(
      'win_notes_window.cpp handles no WM_ACTIVATE, so the host is never told '
      'when the editor becomes the foreground window and the widget cannot '
      'get out of its way.',
    );
  }
  if (!RegExp(r'void Host::OnWindowActivationChanged\s*\(').hasMatch(host)) {
    faults.add(
      'win_notes_host.cpp does not define Host::OnWindowActivationChanged; the '
      'widget-above-editor rule is not implemented on the host side.',
    );
  }

  // 4. Both halves of the yield, together, in the same function.
  final String apply = body(host, 'void Host::ApplyWidgetTopmost');
  if (apply.isEmpty) {
    faults.add(
      'Host::ApplyWidgetTopmost has gone. If the yield is now inline, move it '
      'back so this guard has something to check.',
    );
  } else {
    final bool demotes = RegExp(r'SetAlwaysOnTop').hasMatch(apply);
    final bool raises = RegExp(r'editor_->Raise\(\)').hasMatch(apply);
    if (!demotes) {
      faults.add(
        'Host::ApplyWidgetTopmost never calls SetAlwaysOnTop, so the widget '
        'cannot leave the topmost band.',
      );
    }
    if (!raises) {
      faults.add(
        'Host::ApplyWidgetTopmost does not raise the editor.\n'
        'This is the half that is easy to leave out and impossible to guess. '
        'Dropping the widget out of the topmost band leaves it at the top of '
        'the *ordinary* band, which is still above the editor, so without the '
        'Raise the widget covers the editor and buries it at the same time.\n'
        'Verified by measurement on a release build: demote alone put the '
        'widget at z=2 with the editor at z=5; demote plus raise put the '
        'editor at z=2 and the widget at z=3.',
      );
    }
  }

  return faults;
}

/// Faults in the editor's minimum-size enforcement.
///
/// `docs/widget_pattern.md` §3.18. Three ways to write this handler and have
/// it not work, all silent, all invisible in a diff:
///
///  1. **No DPI scaling.** `ptMinTrackSize` is in physical pixels. Written as a
///     literal `520`, the floor is 520 physical pixels — which is a 520px floor
///     at 100% and a 347px *logical* floor at 150%, so the window people
///     actually use is the one that gets the wrong answer.
///  2. **Writing `ptMaxPosition` or `ptMaxSize` as well.** `ptMaxPosition`
///     governs how far the window may be dragged off-screen, which
///     `ClampToReachableScreen` already owns. Setting it here is a second,
///     conflicting answer to the same question.
///  3. **Using `ptMinSize` instead of `ptMinTrackSize`.** `ptMinSize` also caps
///     programmatic sizing, so Dart asking for a particular size would be
///     silently ignored.
List<String> findEditorMinSizeFaults(String window) {
  final List<String> faults = <String>[];

  final RegExpMatch? m = RegExp(
    r'case WM_GETMINMAXINFO:(.*?)\n    \}',
    dotAll: true,
  ).firstMatch(window);
  if (m == null) {
    faults.add(
      'win_notes_window.cpp handles no WM_GETMINMAXINFO, so the editor has no '
      'minimum size and can be dragged down to nothing.\n'
      'This is the only hook that governs the size the user can reach by '
      'dragging a frame edge; nothing else in this runner does.',
    );
    return faults;
  }
  // Line comments stripped first. This handler explains at length why
  // ptMaxPosition and ptMaxSize are *not* written, and a scanner that reads its
  // own explanation as code would fail on the comment that documents the rule.
  // The same reason findCaptionHits strips comments.
  final String body = (m.group(1) ?? '')
      .split('\n')
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  if (!RegExp(r'ptMinTrackSize').hasMatch(body)) {
    faults.add(
      'WM_GETMINMAXINFO does not set ptMinTrackSize, so the minimum size has '
      'no effect.\n'
      'ptMinTrackSize is the user-resizable floor. ptMinSize would also cap '
      'programmatic sizing, which would silently ignore Dart asking for a '
      'particular size.',
    );
  }

  if (!RegExp(r'kMinEditorWidth').hasMatch(body) ||
      !RegExp(r'kMinEditorHeight').hasMatch(body)) {
    faults.add(
      'WM_GETMINMAXINFO does not use kMinEditorWidth/kMinEditorHeight, so the '
      'floor is a literal that cannot be found or changed in one place.',
    );
  }

  if (!RegExp(r'ScaleForWindow').hasMatch(body)) {
    faults.add(
      'WM_GETMINMAXINFO writes the minimum unscaled.\n'
      'ptMinTrackSize is in *physical* pixels. A literal 520 is a 520px floor '
      'at 100% scaling and a 347 logical-pixel floor at 150%, so the displays '
      'people actually use get the wrong answer and nothing looks wrong.',
    );
  }

  for (final String field in <String>['ptMaxPosition', 'ptMaxSize']) {
    if (RegExp(field).hasMatch(body)) {
      faults.add(
        'WM_GETMINMAXINFO writes $field.\n'
        '${field == 'ptMaxPosition' ? 'It governs how far the window may be dragged off-screen, which ClampToReachableScreen already owns - a second conflicting answer to the same question.' : 'The maximum is the system limit; the widget has its own clamp for the frameless case.'}\n'
        'Only the minimum belongs here.',
      );
    }
  }

  return faults;
}

/// The most lines a `CHANGELOG.md` bullet may occupy, counting the `- `.
///
/// Three is roughly a lead sentence and two wrapped lines. Enough to say what
/// changed and where; not enough to argue for it.
const int kChangelogBulletLines = 3;

/// Faults in the `## Unreleased` section of the changelog.
///
/// `AGENTS.md` §0.6: one bullet per change, saying what changed. The reasoning
/// belongs in `PROJECT.md` or a pattern doc.
///
/// Two faults, and the second is the one that matters:
///
///  1. A bullet longer than [kChangelogBulletLines].
///  2. **An indented line following a blank line with no bullet above it.**
///     That is the fingerprint of an entry written as an essay: a wrapped
///     bullet, a blank line, then a second paragraph still indented under it.
///     Terse entries cannot produce it, because a wrapped bullet has no blank
///     line inside it. So this catches multi-paragraph entries without needing
///     to judge the prose.
///
/// Only the `Unreleased` section is judged. Released sections are historical
/// record, and rewriting a shipped changelog to match a newer house style is a
/// worse trade than inconsistent formatting.
///
/// Takes the text rather than a [SourceTree] so a violation can be injected
/// without editing the repository — which is the only way to prove the scanner
/// still bites.
List<String> findChangelogFaults(String markdown) {
  final List<String> lines = markdown.split('\n');

  int start = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].trim() == '## Unreleased') {
      start = i;
      break;
    }
  }
  // Nothing being written yet is not a fault. An absent section is the normal
  // state between releases, and failing on it would mean the guard could only
  // ever be satisfied by leaving something in the file.
  if (start < 0) return const <String>[];

  int end = lines.length;
  for (int i = start + 1; i < lines.length; i++) {
    if (RegExp(r'^##\s').hasMatch(lines[i])) {
      end = i;
      break;
    }
  }

  final List<String> faults = <String>[];
  int bulletLines = 0;
  int bulletAt = 0;
  bool afterBlank = false;

  void closeBullet() => bulletLines = 0;

  for (int i = start + 1; i < end; i++) {
    final String line = lines[i];

    if (RegExp(r'^#{2,3}\s').hasMatch(line)) {
      closeBullet();
      afterBlank = false;
      continue;
    }

    if (line.trim().isEmpty) {
      closeBullet();
      afterBlank = true;
      continue;
    }

    if (RegExp(r'^-\s').hasMatch(line)) {
      closeBullet();
      bulletAt = i;
      bulletLines = 1;
      afterBlank = false;
      continue;
    }

    if (RegExp(r'^\s+\S').hasMatch(line)) {
      if (afterBlank) {
        faults.add(
          'CHANGELOG.md:${i + 1}  an indented line with no bullet above it.\n'
          '    A blank line ends a bullet. Text still indented under it is a '
          'second paragraph, which §0.6 does not allow: one bullet says what '
          'changed. Put the reasoning in PROJECT.md or a pattern doc.',
        );
      }
      bulletLines++;
      if (bulletLines > kChangelogBulletLines) {
        faults.add(
          'CHANGELOG.md:${bulletAt + 1}  a bullet of $bulletLines lines; the '
          'limit is $kChangelogBulletLines including the `- `.\n'
          '    Say what changed and stop. If it needs more, the entry is '
          'describing a decision rather than a change, and the decision '
          'belongs in PROJECT.md.',
        );
        closeBullet();
      }
      continue;
    }

    // Column-zero prose that is not a bullet: not part of the entry format.
    closeBullet();
    afterBlank = false;
  }

  return faults;
}

/// SDK packages, which are named in `dependencies` but are not dependencies.
///
/// `flutter:` is listed there because that is where it belongs; counting it as a
/// third-party package would make the count wrong in a way that hides the real
/// one.
const Set<String> sdkPackages = <String>{'flutter'};

/// The third-party runtime packages this app is allowed to depend on.
///
/// `AGENTS.md` §0.4. One entry, and it is a list rather than a boolean because
/// the rule is not "no dependencies" — it is "every dependency is a decision
/// somebody made on purpose". Adding to this set is the visible form of that
/// decision, and `docs/storage_pattern.md` §7 is where the reasoning lives.
const Set<String> approvedDependencies = <String>{
  // The CommonMark parser. Added 2026-10-04 with the reversal of "no Markdown".
  // Everything the package does *not* do - the renderer, the two density
  // budgets, the palette styling, what is deliberately not rendered - is in
  // `lib/core/widgets/markdown_text/markdown_text.dart` and is owned here.
  'markdown',

  // State management and DI. Added 2026-10-05, completing the provider pattern
  // after the research that found this repo had none: two hand-written
  // `_bootstrap` methods constructing the same five things, with
  // `_resolveBrightness` already forked into three copies that disagree
  // (AGENTS.md section 4.7).
  //
  // Why this passes the test PROJECT.md 167 sets - "verifiable by reading the
  // code instead of by trusting a dependency" - while `window_manager` and
  // friends would not: Riverpod does no I/O, spawns nothing, touches no platform
  // channel, and generates no code. Its whole behaviour is watch/read and
  // disposal, all of which is written down in `docs/provider_pattern.md` and none
  // of which is delegated. What stays owned here: every provider, the per-file
  // countdowns, and the decision of what is state at all.
  //
  // Unlike `markdown`, this one is load-bearing for the app's structure, so the
  // dependency guard is joined by `provider_guard_test` and `no_set_state_test`,
  // which fail if the plumbing comes back by hand.
  'riverpod',

  // The Flutter bindings for the above: same version, same author.
  //
  // A separate entry rather than a transitive one because `riverpod` alone has no
  // `ConsumerWidget` - it is pure Dart and knows nothing about Flutter, which is
  // exactly the split that makes it auditable. This is the only place
  // Flutter-specific state management exists, and the one a future dependency
  // review has to look at.
  //
  // `riverpod` is listed alongside it even though importing it is reachable
  // transitively. The rule is about what `pubspec.yaml` declares, and it declares
  // both.
  'flutter_riverpod',
};

/// Every package named under the top-level `dependencies:` block of a pubspec.
///
/// Takes the file's text rather than a [SourceTree] so the rule can be checked
/// against a pubspec that is not the real one. That is what makes the
/// corresponding test able to prove the scanner still bites: a guard whose only
/// input is the live repository cannot be shown to reject a violation without
/// making the violation real first.
///
/// `dev_dependencies` are deliberately not read. A test-only package cannot
/// reach the shipped app, and `flutter_lints` has been there the whole time.
Set<String> declaredRuntimeDependencies(String pubspec) {
  // Collected first, because the entry level is the *shallowest* indentation in
  // the block rather than a fixed number of spaces. Assuming two spaces would
  // read a four-space pubspec as having no dependencies at all, which is the
  // failure mode that reads as enforcement: a guard that finds nothing because
  // it looked in the wrong place.
  final List<String> lines = <String>[];
  bool inBlock = false;

  for (final String line in pubspec.split('\n')) {
    if (RegExp(r'^dependencies:\s*$').hasMatch(line)) {
      inBlock = true;
      continue;
    }
    if (!inBlock) continue;

    // A blank line is not the end of the block - pubspecs are usually written
    // with one before the next top-level key.
    if (line.trim().isEmpty) continue;
    if (!RegExp(r'^\s').hasMatch(line)) break;
    lines.add(line);
  }

  if (lines.isEmpty) return <String>{};

  final int entryIndent = lines
      .map((String line) => RegExp(r'^\s*').firstMatch(line)!.group(0)!.length)
      .reduce((int a, int b) => a < b ? a : b);

  final Set<String> names = <String>{};
  for (final String line in lines) {
    final int indent = RegExp(r'^\s*').firstMatch(line)!.group(0)!.length;
    if (indent != entryIndent) continue;
    final RegExpMatch? entry = RegExp(r'^\s+([A-Za-z_][A-Za-z0-9_]*):').firstMatch(line);
    if (entry != null) names.add(entry.group(1)!);
  }

  return names.difference(sdkPackages);
}

/// Dependencies that are not on the approved list.
///
/// `AGENTS.md` §0.4.
List<String> unapprovedDependencies(
  String pubspec, {
  Set<String> approved = approvedDependencies,
}) {
  final Set<String> declared = declaredRuntimeDependencies(pubspec);
  return declared.difference(approved).toList()..sort();
}

/// Headings of the numbered rules in a pattern doc.
///
/// `multiLine: true` rather than an inline `(?m)`: Dart's RegExp is ECMAScript,
/// which has no inline mode flags, and `RegExp(r'(?m)...')` does not silently
/// ignore them - it fails to compile.
List<String> ruleHeadings(String markdown) => RegExp(
      r'^#{2,4}\s+(3\.\d+)',
      multiLine: true,
    ).allMatches(markdown).map((RegExpMatch m) => m.group(1)!).toList();

/// Test names the doc claims as pinning a rule, in italics or backticks.
Set<String> citedTestNames(String markdown) {
  final Set<String> names = <String>{};
  // A row is any table line that cites a test file. The names are then pulled
  // from the whole row rather than from "the cell after the file", because a
  // row can legitimately cite two files and put the names in either cell -
  // scoping the search to one column is how this returned an empty set and
  // nearly shipped a guard that checked nothing.
  final RegExp file = RegExp(r'`\w+_test(?:\.dart)?`');
  for (final String line in markdown.split('\n')) {
    if (!line.trimLeft().startsWith('|')) continue;
    if (!file.hasMatch(line)) continue;
    for (final RegExpMatch t in RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)').allMatches(line)) {
      final String name = t.group(1)!.trim();
      if (name.isNotEmpty) names.add(name);
    }
  }
  return names;
}

/// Every test name in the suite.
Set<String> allTestNames(SourceTree tree) {
  final Set<String> names = <String>{};
  final RegExp decl = RegExp(r"test(?:Widgets)?\('((?:[^'\\]|\\.)*)'");
  for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder('test').entries) {
    final String text = entry.value.join('\n');
    for (final RegExpMatch m in decl.allMatches(text)) {
      names.add(m.group(1)!.replaceAll(r"\'", "'"));
    }
  }
  return names;
}

String _rel(SourceTree tree, String path) =>
    path.replaceAll(r'\', '/').replaceFirst('${tree.root.replaceAll(r'\', '/')}/', '');

// --- Removal budgets -------------------------------------------------------------
//
// The repo has decided that `setState`, injected controllers, and construction
// inside a widget all go. Removing 24 call sites is one piece of work, and this
// class is how the rule is enforced *during* that work rather than after it.
//
// It is deliberately not a list of exempted *paths*. `AGENTS.md` §3.1 says the
// layer guards carry no such list on purpose, and the reason applies here too: an
// exemption list is where exceptions go to hide, and a bare path says nothing about
// how many sites sit under it.
//
// So what is recorded is a **count per file**, which is a budget. Two properties
// follow, and both are load-bearing:
//
//   - A file with *more* sites than its budget is a fault. So is a file not in
//     the budget at all. Adding one is caught.
//   - A file with *fewer* is also a fault: the budget line is stale and must be
//     deleted. Fixing a site and leaving the number behind is caught too, which
//     is what stops the countdown from being quietly raised to match the code.
//
// A budget that only ever goes down is the only kind worth having.

/// A per-file count of a construct this repo is removing.
class RemovalBudget {
  const RemovalBudget({
    required this.what,
    required this.allowance,
    required this.rule,
  });

  /// What is being counted, for the failure message.
  final String what;

  /// Repo-relative path -> the number of sites still permitted there.
  final Map<String, int> allowance;

  /// What to do instead, named in every fault.
  final String rule;

  int get allowanceTotal =>
      allowance.values.fold(0, (int sum, int n) => sum + n);

  /// The budget's own sites that no longer exist, sorted.
  List<String> staleAllowances(Map<String, int> live) => allowance.keys
      .where((String p) => !live.containsKey(p))
      .toList()
    ..sort();

  int liveTotal(Map<String, int> live) =>
      live.values.fold(0, (int sum, int n) => sum + n);

  List<String> faults(Map<String, int> live) {
    final List<String> out = <String>[];
    final List<String> paths = <String>{...live.keys, ...allowance.keys}.toList()..sort();

    for (final String path in paths) {
      final int now = live[path] ?? 0;
      final int? allowed = allowance[path];

      if (allowed == null) {
        out.add(
          '$path has $now ${now == 1 ? 'site' : 'sites'} of $what and is not in '
          'the budget at all.\n'
          '    $rule\n'
          '    If this is genuinely unavoidable, say so in the pattern doc and '
          'record it in AGENTS.md §4. A budget line added silently is the '
          'exception this exists to prevent.',
        );
        continue;
      }

      if (now > allowed) {
        out.add(
          '$path has $now ${now == 1 ? 'site' : 'sites'} of $what; the budget '
          'allows $allowed.\n'
          '    $rule',
        );
      } else if (now < allowed) {
        out.add(
          '$path has $now ${now == 1 ? 'site' : 'sites'} of $what but the '
          'budget still allows $allowed.\n'
          '    You removed one and left the number behind. Delete the line: a '
          'budget that does not fall is how a countdown stops counting.',
        );
      }
    }

    return out;
  }
}

/// Occurrences of [pattern] per file under [relative], excluding `*.g.dart`.
///
/// Counting per file rather than in total is what lets [RemovalBudget] notice a
/// site moving between files, and what lets the fault name the file a reader
/// has to open.
Map<String, int> countPerFile(
  SourceTree tree,
  String relative,
  String pattern, {
  bool excludeGenerated = true,
}) {
  final Map<String, int> out = <String, int>{};
  for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder(relative).entries) {
    final String path = _rel(tree, entry.key).replaceAll(r'\', '/');
    if (excludeGenerated && path.endsWith('.g.dart')) continue;
    final int n = RegExp(pattern).allMatches(entry.value.join('\n')).length;
    if (n > 0) out[path] = n;
  }
  return out;
}

/// Every `setState(` call site under `lib/`, per file.
///
/// `AGENTS.md` §0.7: none, no excuse accepted. The three replacements are a
/// Riverpod provider, a `ValueNotifier`, and a `State` that only holds things it
/// is allowed to hold.
Map<String, int> setStateCounts(SourceTree tree) =>
    countPerFile(tree, 'lib', r'\bsetState\s*\(');

/// Every **widget** constructor field that carries shared state in from outside.
///
/// `AGENTS.md` §0.8: a widget below a `ProviderScope` reads state with `ref`, not
/// through a parameter. This counts the hand-rolled equivalent that used to exist -
/// 23 parameters on 2026-10-05, now zero.
///
/// **Two limits, both stated rather than hidden.**
///
///  - *It matches names, not types.* A dependency arriving as `this.foo` would not
///    be caught. The alternative cannot be done by scanning text, and the two
///    `ScrollController` and `TextEditingController` fields this rule legitimately
///    tolerates are the price of a check that runs in CI. Both were given honest
///    names - `scroll`, `field` - so a reader can see they are per-widget resources
///    rather than shared state.
///  - *It decides "is this a widget" by reading the nearest preceding `class`
///    line.* That is an approximation: it is right for this codebase, where classes
///    do not nest and no class is declared inside a method, and it would be wrong in
///    one where they do. Brace-matching source text to find a class body is a
///    reliable way to get a guard that fails on a string literal.
///
/// The class test matters because §0.8 is about *widgets*, and two plain classes in
/// `editor_app.dart` legitimately hold notifiers: `EditorBootstrap` and
/// `EditorTeardown`. They exist precisely because a `WidgetRef` cannot be held across
/// an await or read inside `dispose` - Riverpod throws in both cases - so the
/// dependencies are resolved in `initState` and handed to a plain object that has no
/// widget to be unmounted from. Counting those as violations would be the guard
/// insisting on a rule the framework makes impossible, which is how a guard gets
/// disabled.
Map<String, int> injectedStateParamCounts(SourceTree tree) {
  final RegExp field = RegExp(
    r'\bthis\.(controller|shell|settings|notifier|store|model|repo|repository|viewModel)\b',
  );
  final RegExp classLine = RegExp(r'^\s*class\s+(\w+)', multiLine: true);

  final Map<String, int> counts = <String, int>{};
  for (final String layer in _existingLayers(tree, <String>[
    'lib/features/notes/presentation/screens',
    'lib/features/notes/presentation/widgets',
    'lib/features/widget/presentation/screens',
    'lib/features/widget/presentation/widgets',
    'lib/features/settings/presentation/screens',
    'lib/features/settings/presentation/widgets',
    'lib/core/widgets',
  ])) {
    for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder(layer).entries) {
      final String path = _rel(tree, entry.key).replaceAll(r'\', '/');
      final String source = entry.value.join('\n');

    // Offsets of every class declaration, so a hit can be attributed to one.
    final Map<int, String> declarations = <int, String>{};
    for (final RegExpMatch m in classLine.allMatches(source)) {
      declarations[m.start] = m.group(1) ?? '';
    }

    int found = 0;
    for (final RegExpMatch hit in field.allMatches(source)) {
      final int? owner = _enclosingClass(declarations.keys.toSet(), hit.start);
      if (owner == null) continue;
      if (_isWidgetClass(source, owner)) found++;
    }
    if (found > 0) counts[path] = found;
    }
  }
  return counts;
}

/// The offset of the last class declared before [offset].
int? _enclosingClass(Set<int> starts, int offset) {
  int? best;
  for (final int start in starts) {
    if (start > offset) break;
    best = start;
  }
  return best;
}

/// Whether the class declared at [offset] is a widget.
///
/// True for anything extending a `*Widget`, and for a `State` subclass - which is
/// how the rule reaches a `ConsumerStatefulWidget`'s own constructor, since the
/// widget's fields are inherited rather than repeated.
bool _isWidgetClass(String source, int offset) {
  final int end = source.indexOf('{', offset);
  if (end < 0) return false;
  final String header = source.substring(offset, end > offset + 300 ? offset + 300 : end);
  return RegExp(r'extends\s+[\w<>,\s]*?(Widget|State<)\b').hasMatch(header);
}

/// Every repository or controller constructed where widgets live.
///
/// `AGENTS.md` §0.9 and `docs/isolate_pattern.md` §3.1: construction belongs to a
/// provider, so that both surfaces build the same graph instead of each writing
/// its own. Scoped to screens and widgets, not the providers dirs - building a
/// repository inside its provider file is the rule, not the violation.
Map<String, int> uiConstructionCounts(SourceTree tree) {
  final Map<String, int> out = <String, int>{};
  for (final String layer in _existingLayers(tree, <String>[
    'lib/features/notes/presentation/screens',
    'lib/features/notes/presentation/widgets',
    'lib/features/widget/presentation/screens',
    'lib/features/widget/presentation/widgets',
    'lib/features/settings/presentation/screens',
    'lib/features/settings/presentation/widgets',
    'lib/core/widgets',
  ])) {
    for (final MapEntry<String, int> entry in countPerFile(
      tree,
      layer,
      r'\b(?:Notes|Settings|WidgetState|Selection)Repository\s*\(|\b'
      r'(?:Notes|Settings|Widget)Controller\s*\(',
    ).entries) {
      out[entry.key] = (out[entry.key] ?? 0) + entry.value;
    }
  }
  return out;
}

/// Every method name Dart sends to the runner, across **all four** dispatch idioms.
///
/// `shell_channel.dart` dispatches four ways, and the original version of this
/// scanner matched two of them *line by line*, which missed every call whose name
/// sat on the following line. Five real methods were never parity-checked as a
/// result: `dialog.confirmQuit`, `path.pickFile`, `path.pickFolder`,
/// `path.saveFile` and `widget.beginResize`. All five are handled by the runner,
/// so no code was wrong — but the guard was reporting on 19 of 24 methods and
/// calling that parity.
///
/// `\s` matches a newline in a Dart RegExp, so matching against the joined text
/// rather than line by line is the whole fix. `docs/platform_pattern.md` §3.1 is
/// why the registry exists at all: once the names are declared in one place, a
/// blind spot in a scanner is a smaller loss than an undeclared contract.
///
/// The four idioms, all of which must be covered:
///
///  1. `_fire('name')` - fire and forget, failures swallowed.
///  2. `_invoke('name')` - returns a value, `PlatformException` becomes null.
///  3. `methodChannel.invokeMethod<T>('name')` - direct, hand-rolled catch.
///  4. `methodChannel.invokeMapMethod<T,V>('name')` - as 3, returning a map.
Set<String> channelMethodNames(SourceTree tree) {
  final Set<String> names = <String>{};
  final String text = tree.read('lib/core/platform/shell_channel.dart');

  final List<RegExp> idioms = <RegExp>[
    RegExp(r"_fire\s*\(\s*'([^']+)'"),
    RegExp(r"_invoke(?:<[^>]*>)?\s*\(\s*'([^']+)'"),
    RegExp(r"invokeMethod(?:<[^>]*>)?\s*\(\s*'([^']+)'"),
    RegExp(r"invokeMapMethod(?:<[^>]*>)?\s*\(\s*'([^']+)'"),
  ];

  for (final RegExp idiom in idioms) {
    for (final RegExpMatch m in idiom.allMatches(text)) {
      names.add(m.group(1)!);
    }
  }
  return names;
}

/// The same four idioms, kept apart, so a test can ask *how* a method is called and
/// not merely *that* it is.
///
/// Split out rather than re-derived in each test because the two answers have to
/// come from one list. The first version of the §4.3 drift check listed the
/// bypassing methods in the test body while the parity scanner listed them
/// separately, which is two definitions of the same thing and therefore two things
/// that can disagree - and they did, by one.
///
/// Keys are `fire`, `invoke`, `direct`, `directMap`. The last two are the ones
/// `docs/platform_pattern.md` §3.3 says to avoid: they reach the channel without a
/// helper, so each one re-decides its own failure policy.
Map<String, Set<String>> channelMethodNamesByIdiom(SourceTree tree) {
  final String text = tree.read('lib/core/platform/shell_channel.dart');
  final Map<String, Set<String>> out = <String, Set<String>>{
    'fire': <String>{},
    'invoke': <String>{},
    'direct': <String>{},
    'directMap': <String>{},
  };

  final Map<String, RegExp> idioms = <String, RegExp>{
    'fire': RegExp(r"_fire\s*\(\s*'([^']+)'"),
    'invoke': RegExp(r"_invoke(?:<[^>]*>)?\s*\(\s*'([^']+)'"),
    'direct': RegExp(r"(?<!Map)invokeMethod(?:<[^>]*>)?\s*\(\s*'([^']+)'"),
    'directMap': RegExp(r"invokeMapMethod(?:<[^>]*>)?\s*\(\s*'([^']+)'"),
  };

  for (final MapEntry<String, RegExp> entry in idioms.entries) {
    for (final RegExpMatch m in entry.value.allMatches(text)) {
      out[entry.key]!.add(m.group(1)!);
    }
  }
  return out;
}

/// The inbound namespace the runner pushes *up* to Dart.
///
/// Separate from [channelMethodNames] by construction rather than by convention:
/// `event.*` is runner-to-Dart and `everything else` is Dart-to-runner, and the
/// two sets being disjoint is checked rather than assumed. They travel on one
/// channel, which is exactly why they are easy to confuse.
const Set<String> inboundEventPrefixes = <String>{'event.'};

/// Faults between a declared method registry and the two sides of the channel.
///
/// Three-way on purpose: the doc, the Dart calls and the runner's handler list
/// must all say the same thing. A registry is only worth having if nothing can
/// drift away from it.
List<String> platformRegistryFaults({
  required Set<String> registry,
  required Set<String> called,
  required Set<String> handled,
}) {
  final List<String> faults = <String>[];

  final List<String> declaredButNeverCalled = registry.difference(called).toList()..sort();
  if (declaredButNeverCalled.isNotEmpty) {
    faults.add(
      'The registry declares methods Dart never sends: '
      '${declaredButNeverCalled.join(', ')}.\n'
      '    Either the declaration is aspirational or the call was deleted. '
      'docs/platform_pattern.md §3.1 records what the contract *is*, not what '
      'it might become.',
    );
  }

  final List<String> calledButNotDeclared = called.difference(registry).toList()..sort();
  if (calledButNotDeclared.isNotEmpty) {
    faults.add(
      'Dart sends methods that are not in the registry: '
      '${calledButNotDeclared.join(', ')}.\n'
      '    An undeclared method is the failure this file exists to prevent: it '
      'works until the runner is renamed, and then result->Success() is '
      'returned anyway so the Dart await completes and nothing happens.',
    );
  }

  final List<String> declaredButUnhandled =
      registry.difference(handled).toList()..sort();
  if (declaredButUnhandled.isNotEmpty) {
    faults.add(
      'The registry declares methods the runner does not handle: '
      '${declaredButUnhandled.join(', ')}.',
    );
  }

  final List<String> handledButNotDeclared =
      handled.difference(registry).toList()..sort();
  if (handledButNotDeclared.isNotEmpty) {
    faults.add(
      'The runner handles methods that are not in the registry: '
      '${handledButNotDeclared.join(', ')}.',
    );
  }

  final List<String> inboundLeaked = registry
      .where((String name) => inboundEventPrefixes.any(name.startsWith))
      .toList()
    ..sort();
  if (inboundLeaked.isNotEmpty) {
    faults.add(
      'Inbound event names in the outbound registry: ${inboundLeaked.join(', ')}.\n'
      '    `event.*` travels runner-to-Dart. It shares the channel, not the '
      'direction, and listing it here would mean a Dart call that no runner '
      'ever answers.',
    );
  }

  if (registry.isEmpty) {
    faults.add(
      'The registry is empty, which would make every check above pass '
      'vacuously.',
    );
  }

  return faults;
}

/// Comment blocks longer than three lines under `lib/`.
///
/// `docs/flutter_architecture_pattern.md` §2: past 2–3 lines a comment replaces
/// reading the code. Each entry is `path:first-line (length)`.
List<String> findLongComments(SourceTree tree) {
  final List<String> out = <String>[];
  for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder('lib').entries) {
    final String path = _rel(tree, entry.key).replaceAll(r'\', '/');
    final List<String> lines = entry.value;
    int i = 0;
    while (i < lines.length) {
      if (!lines[i].trimLeft().startsWith('//')) {
        i++;
        continue;
      }
      int j = i;
      while (j < lines.length && lines[j].trimLeft().startsWith('//')) {
        j++;
      }
      if (j - i > 3) {
        out.add('$path:${i + 1} (${j - i} lines)');
      }
      i = j;
    }
  }
  return out;
}

/// Code-only line count per §2: imports, blank lines and comments do not count.
int codeOnlyLines(List<String> lines) {
  int n = 0;
  for (final String line in lines) {
    final String trimmed = line.trimLeft();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('//')) continue;
    if (trimmed.startsWith('import ') ||
        trimmed.startsWith('export ') ||
        trimmed == 'library;') {
      continue;
    }
    n++;
  }
  return n;
}

/// The bodies of every `marker:` argument in [source], by brace counting.
///
/// The parenthesised argument list is returned as well as any braced body: an
/// arrow callback (`() => t?.cancel()`) has no braces, so a scanner that only
/// looked for them would report a clean tree.
List<String> bodiesAfterMarker(String source, String marker) {
  final List<String> out = <String>[];
  int from = 0;
  while (true) {
    final RegExpMatch? match = RegExp(RegExp.escape(marker)).firstMatch(source.substring(from));
    if (match == null) break;
    final int start = from + match.end;
    int parens = 0;
    int closed = -1;
    for (int i = start; i < source.length; i++) {
      final int unit = source.codeUnitAt(i);
      if (unit == 0x28) {
        parens++;
      } else if (unit == 0x29) {
        parens--;
        if (parens == 0) {
          closed = i;
          break;
        }
      }
    }
    if (closed < 0) break;
    out.add(source.substring(start, closed));
    final int arrowEnd = source.indexOf(';', closed);
    final int braceStart = source.indexOf('{', closed);
    if (braceStart >= 0 && (arrowEnd < 0 || braceStart < arrowEnd)) {
      int depth = 0;
      bool started = false;
      for (int j = braceStart; j < source.length; j++) {
        final int unit = source.codeUnitAt(j);
        if (unit == 0x7B) {
          depth++;
          started = true;
        } else if (unit == 0x7D) {
          depth--;
          if (started && depth == 0) {
            out.add(source.substring(braceStart, j));
            break;
          }
        }
      }
    }
    from = closed + 1;
  }
  return out;
}

/// The widget classes declared in each `lib/` file, keyed by repo-relative path.
///
/// A `State`/`ConsumerState` paired with its widget is not a second widget —
/// §3.1 says so explicitly — so the `State` classes are read and dropped
/// rather than counted. A file that declares two real widgets is the violation.
final RegExp _widgetClassPattern = RegExp(
  r'^\s*(?:abstract\s+)?class\s+(\w+)\s+extends\s+'
  r'(?:\w*StatelessWidget|\w*StatefulWidget|ConsumerWidget|'
  r'ConsumerStatefulWidget|CustomPainter)\b',
  multiLine: true,
);

final RegExp _stateClassPattern = RegExp(
  r'^\s*class\s+(\w+)\s+extends\s+(?:Consumer)?State<(\w+)>',
  multiLine: true,
);

/// Every widget class in the file, by repo-relative path.
///
/// The values are the class names, in declaration order.
Map<String, List<String>> widgetClassesByFile(SourceTree tree) {
  final Map<String, List<String>> out = <String, List<String>>{};
  for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder('lib').entries) {
    final String path = _rel(tree, entry.key).replaceAll(r'\', '/');
    final String code = entry.value
        .where((String l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    final Set<String> states = _stateClassPattern
        .allMatches(code)
        .map((RegExpMatch m) => m.group(2)!)
        .toSet();
    final List<String> widgets = _widgetClassPattern
        .allMatches(code)
        .map((RegExpMatch m) => m.group(1)!)
        .where((String name) => !states.contains(name))
        .toList();
    if (widgets.isNotEmpty) out[path] = widgets;
  }
  return out;
}

/// `docs/flutter_architecture_pattern.md` §3.1: one widget class per file.
///
/// Each entry is `path: classA, classB`.
List<String> findFilesWithSeveralWidgets(SourceTree tree) {
  final List<String> out = <String>[];
  widgetClassesByFile(tree).forEach((String path, List<String> names) {
    if (names.length > 1) out.add('$path: ${names.join(', ')}');
  });
  return out..sort();
}

String _snakeCase(String className) =>
    className.replaceAllMapped(RegExp(r'(?<!^)([A-Z])'), (Match m) => '_${m[1]}').toLowerCase();

/// `docs/flutter_architecture_pattern.md` §4: folder and file named after the widget.
///
/// A widget whose folder or file is named something else cannot be found by
/// either name, which is the whole reason for the convention. The class is the
/// only thing that cannot be renamed cheaply — the folder and file follow it.
///
/// Each entry is `path: class C, expected folder/file E`.
List<String> findWidgetsMisnamed(SourceTree tree) {
  final List<String> out = <String>[];
  widgetClassesByFile(tree).forEach((String path, List<String> names) {
    // A file holding exactly one widget is the case the rule is about. A file
    // with several is reported by [findFilesWithSeveralWidgets] instead, and
    // naming one of several after the other would be a second complaint about
    // the same thing.
    if (names.length != 1) return;
    final String expected = _snakeCase(names.single);
    final List<String> segments = path.split('/');
    final String folder = segments[segments.length - 2];
    final String file = segments.last.replaceAll('.dart', '');
    if (folder != expected || file != expected) {
      out.add('$path: class ${names.single}, expected $expected/');
    }
  });
  return out..sort();
}

/// The repo-relative path of each feature's root screen.
const Map<String, String> _featureRoots = <String, String>{
  'notes': 'lib/features/notes/presentation/screens/editor_app/editor_app.dart',
  'widget':
      'lib/features/widget/presentation/screens/widget_app/widget_app.dart',
  'settings':
      'lib/features/settings/presentation/screens/settings_dialog/settings_dialog.dart',
};

/// The `lib/` files each feature can reach through its imports.
///
/// Transitive, because a feature reaches a shared widget through whatever it
/// imports, not only through what it names. Both `package:win_notes/...` and
/// relative imports are followed, since the tree uses both.
Map<String, Set<String>> widgetReachabilityByFeature(SourceTree tree) {
  final Map<String, List<String>> edges = <String, List<String>>{};
  for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder('lib').entries) {
    final String path = _rel(tree, entry.key).replaceAll(r'\', '/');
    final List<String> segments = path.split('/');
    final List<String> directory = segments.sublist(0, segments.length - 1);
    final List<String> deps = <String>[];
    for (final String line in entry.value) {
      final RegExpMatch? match = RegExp(r"import\s+'([^']+)'").firstMatch(line);
      if (match == null) continue;
      final String target = match.group(1)!;
      if (target.startsWith('package:win_notes/')) {
        // Both key sets are repo-relative *with* the `lib/` prefix, which is what
        // `_rel` produces. Dropping it here is what made every core widget look
        // private to whichever feature was walked first.
        deps.add(target);
      } else if (target.startsWith('package:') || target.startsWith('dart:')) {
        continue;
      } else {
        final List<String> parts = <String>[...directory];
        for (final String segment in target.split('/')) {
          if (segment == '..') {
            if (parts.isNotEmpty) parts.removeLast();
          } else if (segment != '.' && segment.isNotEmpty) {
            parts.add(segment);
          }
        }
        deps.add(parts.join('/'));
      }
    }
    edges[path] = deps;
  }

  final Map<String, Set<String>> out = <String, Set<String>>{};
  _featureRoots.forEach((String feature, String root) {
    final Set<String> seen = <String>{};
    final List<String> queue = <String>[root];
    while (queue.isNotEmpty) {
      final String next = queue.removeLast();
      if (!seen.add(next)) continue;
      for (final String dep in edges[next] ?? const <String>[]) {
        if (edges.containsKey(dep)) queue.add(dep);
      }
    }
    out[feature] = seen;
  });
  return out;
}

/// `docs/flutter_architecture_pattern.md` §4: shared means two or more features.
///
/// A widget only `notes` reaches is `notes`' private widget and belongs in its
/// `widgets/` folder; one two features reach is genuinely shared. Reachability
/// is computed, so this is a fact about the tree rather than an opinion about
/// a file's location.
///
/// Each entry is `path: reached by notes, widget`.
List<String> findWidgetsInTheWrongHome(SourceTree tree) {
  final Map<String, Set<String>> reach = widgetReachabilityByFeature(tree);
  final List<String> out = <String>[];
  widgetClassesByFile(tree).forEach((String path, List<String> names) {
    if (!path.startsWith('lib/core/widgets/')) return;
    // `core/widgets` also holds plain functions and painters reached from
    // `main.dart`, which is not a feature. Only a file reachable from exactly
    // one feature is the violation; zero or two or more is fine.
    final List<String> users = reach.entries
        .where((MapEntry<String, Set<String>> e) => e.value.contains(path))
        .map((MapEntry<String, Set<String>> e) => e.key)
        .toList()
      ..sort();
    if (users.length == 1) {
      out.add('$path: ${names.join(', ')} -> reached only by ${users.single}');
    }
  });
  return out..sort();
}

/// `docs/flutter_architecture_pattern.md` §7.1: `ValueKey(id)` on list rows.
///
/// A row built in a `ListView.builder` whose widget takes no `key:` cannot be
/// matched to its note, so when the list reorders the element state goes with
/// the index rather than the note.
///
/// Each entry is `path:line`.
List<String> findUnkeyedListRows(SourceTree tree) {
  final List<String> out = <String>[];
  for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder('lib').entries) {
    final String path = _rel(tree, entry.key).replaceAll(r'\', '/');
    final List<String> lines = entry.value;
    for (int i = 0; i < lines.length; i++) {
      if (!RegExp(r'ListView\.(builder|separated)\(').hasMatch(lines[i])) continue;
      // The builder's body, to the closing of that call, by brace counting.
      final String body =
          bodiesAfterMarker(lines.sublist(i).join('\n'), 'itemBuilder:').join('\n');
      if (body.isEmpty) continue;
      final Set<String> rows = RegExp(r'return\s+(\w+)\(')
          .allMatches(body)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();
      for (final String row in rows) {
        // `key:` anywhere in the builder body counts: it may be passed through
        // a named parameter rather than set literally.
        if (RegExp(r'\bkey\s*:').hasMatch(body)) continue;
        out.add('$path:${i + 1}  $row has no key: in a ListView.builder');
      }
    }
  }
  return out..sort();
}

/// `docs/flutter_architecture_pattern.md` §7.2: a `FocusNode` needs an owner.
///
/// `FocusScope.of(context).requestFocus(FocusNode())` attaches a node to the
/// tree with no field holding it, so `dispose` cannot reach it and it is never
/// disposed. One per call, and this is on a focus path.
///
/// Each entry is `path:line`.
List<String> findLeakedFocusNodes(SourceTree tree) {
  final List<String> out = <String>[];
  for (final MapEntry<String, List<String>> entry in tree.dartFilesUnder('lib').entries) {
    out.addAll(focusNodeLeaksIn(
      entry.value,
      _rel(tree, entry.key).replaceAll(r'\', '/'),
    ));
  }
  return out..sort();
}

/// The inline-`FocusNode` leaks in one file's lines. Each is `path:line`.
///
/// Split out so a planted body can be checked without planting a file: a
/// scanner that only ever ran over `lib/` would report a clean tree when the
/// tree had no such leak, which is the same as reporting one when it did.
List<String> focusNodeLeaksIn(List<String> lines, String path) {
  final List<String> out = <String>[];
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trimLeft().startsWith('//')) continue;
    // A `FocusNode()` argument to anything but `attach`/`dispose` is the leak:
    // a node held in a field is fine, and one being disposed is being fixed.
    if (!RegExp(r'\(\s*FocusNode\s*\(\s*\)\s*\)').hasMatch(line)) continue;
    if (RegExp(r'\b(attach|dispose)\s*\(').hasMatch(line)) continue;
    out.add('$path:${i + 1}  ${line.trim()}');
  }
  return out;
}