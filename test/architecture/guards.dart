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
    var dir = Directory.current;
    for (var i = 0; i < 8; i++) {
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
    final base = Directory('$root/$relative');
    if (!base.existsSync()) {
      throw StateError('No such directory: $relative');
    }
    final out = <String, List<String>>{};
    for (final entity in base.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      out[entity.path] = entity.readAsLinesSync();
    }
    return out;
  }

  String read(String relative) =>
      File('$root/$relative').readAsStringSync();

  String get runnerSource {
    final dir = Directory('$root/windows/runner');
    if (!dir.existsSync()) return '';
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.cpp') || f.path.endsWith('.h'))
        .map((f) => f.readAsStringSync())
        .join('\n');
  }

  bool exists(String relative) =>
      File('$root/$relative').existsSync() || Directory('$root/$relative').existsSync();
}

// --- Rule scanners -----------------------------------------------------------
// Each returns the violations it found, so the calling test can print them
// properly. A scanner that only returns a bool forces every failure message to
// be reconstructed inside the scanner, which is where good messages go to die.

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
  final banned = RegExp(
    r'''\b(File|Directory|Link)\s*\(|\.writeAsString|\.readAsString|'''
    r'''\.writeAsBytes|\.readAsBytes|\.existsSync|\.lengthSync|'''
    r'''\.lastModifiedSync|\.createSync''',
  );
  final violations = <String>[];
  for (final layer in ['lib/src/ui', 'lib/src/state', 'lib/src/platform']) {
    for (final entry in tree.dartFilesUnder(layer).entries) {
      // Comments are allowed to say "dart:io" — two of ours do, and both do it
      // to explain why the UI must not use it. Only real code counts.
      final code = entry.value
          .where((line) => !line.trimLeft().startsWith('//') && !line.trimLeft().startsWith('*'))
          .join('\n');
      for (var i = 0; i < code.split('\n').length; i++) {
        final line = code.split('\n')[i];
        if (banned.hasMatch(line)) {
          violations.add('${_rel(tree, entry.key)}:${i + 1}  ${line.trim()}');
        }
      }
    }
  }
  return violations;
}

/// Only `platform/` constructs a `MethodChannel`.
///
/// `AGENTS.md` §3. Everything else goes through `ShellChannel`, so that the set
/// of method names lives in one file and can be checked against the runner.
List<String> findChannelsOutsidePlatform(SourceTree tree) {
  final violations = <String>[];
  for (final entry in tree.dartFilesUnder('lib/src').entries) {
    if (entry.key.replaceAll(r'\', '/').contains('/platform/')) continue;
    for (var i = 0; i < entry.value.length; i++) {
      final line = entry.value[i];
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
  final names = <String>{};
  final literal = RegExp(r"""_fire\(\s*'([^']+)'""");
  final invoke = RegExp(r"""_invoke(?:<[^>]*>)?\(\s*'([^']+)'""");
  for (final entry in tree.dartFilesUnder('lib/src').entries) {
    for (final line in entry.value) {
      for (final m in literal.allMatches(line)) {
        names.add(m.group(1)!);
      }
      for (final m in invoke.allMatches(line)) {
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
      .map((m) => m.group(1)!)
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
  final source = tree.runnerSource;
  final violations = <String>[];
  // Strip line comments so the explanatory prose in HitTest, which mentions
  // HTCAPTION four times on purpose, does not trip the guard it is describing.
  final code = source
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  for (final m in RegExp(r'HTCAPTION').allMatches(code)) {
    final line = code.substring(0, m.start).split('\n').length;
    final text = code.split('\n')[line - 1].trim();
    violations.add('windows/runner: $line  $text');
  }
  // The mirror image is also forbidden: HTTOPLEFT and friends would resize the
  // window from a corner Dart already owns, and would fight the gesture.
  for (final final_ in ['HTTOP', 'HTTOPLEFT', 'HTTOPRIGHT', 'HTBOTTOM',
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
  final faults = <String>[];

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
    final pattern =
        '${RegExp.escape(signature)}\\s*\\([^)]*\\)\\s*\\{(.*?)\\n\\}';
    return RegExp(pattern, dotAll: true).firstMatch(source)?.group(1) ?? '';
  }

  // 1. The editor must never be created topmost.
  final style = body(window, 'void Window::StyleForRole');
  final editorBranch = style.split('} else {').length > 1
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
  final alwaysOnTop = body(window, 'void Window::SetAlwaysOnTop');
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
  final apply = body(host, 'void Host::ApplyWidgetTopmost');
  if (apply.isEmpty) {
    faults.add(
      'Host::ApplyWidgetTopmost has gone. If the yield is now inline, move it '
      'back so this guard has something to check.',
    );
  } else {
    final demotes = RegExp(r'SetAlwaysOnTop').hasMatch(apply);
    final raises = RegExp(r'editor_->Raise\(\)').hasMatch(apply);
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
  final faults = <String>[];

  final m = RegExp(
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
  final body = (m.group(1) ?? '')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
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

  for (final field in ['ptMaxPosition', 'ptMaxSize']) {
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
  final lines = markdown.split('\n');

  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() == '## Unreleased') {
      start = i;
      break;
    }
  }
  // Nothing being written yet is not a fault. An absent section is the normal
  // state between releases, and failing on it would mean the guard could only
  // ever be satisfied by leaving something in the file.
  if (start < 0) return const [];

  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (RegExp(r'^##\s').hasMatch(lines[i])) {
      end = i;
      break;
    }
  }

  final faults = <String>[];
  var bulletLines = 0;
  var bulletAt = 0;
  var afterBlank = false;

  void closeBullet() => bulletLines = 0;

  for (var i = start + 1; i < end; i++) {
    final line = lines[i];

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
  // `lib/src/ui/common/markdown_text.dart` and is owned here.
  'markdown',
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
  final lines = <String>[];
  var inBlock = false;

  for (final line in pubspec.split('\n')) {
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

  final entryIndent = lines
      .map((line) => RegExp(r'^\s*').firstMatch(line)!.group(0)!.length)
      .reduce((a, b) => a < b ? a : b);

  final names = <String>{};
  for (final line in lines) {
    final indent = RegExp(r'^\s*').firstMatch(line)!.group(0)!.length;
    if (indent != entryIndent) continue;
    final entry = RegExp(r'^\s+([A-Za-z_][A-Za-z0-9_]*):').firstMatch(line);
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
  final declared = declaredRuntimeDependencies(pubspec);
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
    ).allMatches(markdown).map((m) => m.group(1)!).toList();

/// Test names the doc claims as pinning a rule, in italics or backticks.
Set<String> citedTestNames(String markdown) {
  final names = <String>{};
  // A row is any table line that cites a test file. The names are then pulled
  // from the whole row rather than from "the cell after the file", because a
  // row can legitimately cite two files and put the names in either cell -
  // scoping the search to one column is how this returned an empty set and
  // nearly shipped a guard that checked nothing.
  final file = RegExp(r'`\w+_test(?:\.dart)?`');
  for (final line in markdown.split('\n')) {
    if (!line.trimLeft().startsWith('|')) continue;
    if (!file.hasMatch(line)) continue;
    for (final t in RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)').allMatches(line)) {
      final name = t.group(1)!.trim();
      if (name.isNotEmpty) names.add(name);
    }
  }
  return names;
}

/// Every test name in the suite.
Set<String> allTestNames(SourceTree tree) {
  final names = <String>{};
  final decl = RegExp(r"test(?:Widgets)?\('((?:[^'\\]|\\.)*)'");
  for (final entry in tree.dartFilesUnder('test').entries) {
    final text = entry.value.join('\n');
    for (final m in decl.allMatches(text)) {
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
      allowance.values.fold(0, (sum, n) => sum + n);

  /// The budget's own sites that no longer exist, sorted.
  List<String> staleAllowances(Map<String, int> live) => allowance.keys
      .where((p) => !live.containsKey(p))
      .toList()
    ..sort();

  int liveTotal(Map<String, int> live) =>
      live.values.fold(0, (sum, n) => sum + n);

  List<String> faults(Map<String, int> live) {
    final out = <String>[];
    final paths = {...live.keys, ...allowance.keys}.toList()..sort();

    for (final path in paths) {
      final now = live[path] ?? 0;
      final allowed = allowance[path];

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
  final out = <String, int>{};
  for (final entry in tree.dartFilesUnder(relative).entries) {
    final path = _rel(tree, entry.key).replaceAll(r'\', '/');
    if (excludeGenerated && path.endsWith('.g.dart')) continue;
    final n = RegExp(pattern).allMatches(entry.value.join('\n')).length;
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

/// Every widget constructor field that carries shared state in from outside.
///
/// `AGENTS.md` §0.8: a widget below a `ProviderScope` reads state with `ref`, not
/// through a parameter. This counts the hand-rolled equivalent that exists today.
///
/// `notes` is deliberately absent from the alternation. `NotesLoaded(this.notes)`
/// is a load result, not an injected dependency, and a scan that cannot tell the
/// difference would carry a false positive forever — which is how a budget stops
/// being believed.
Map<String, int> injectedStateParamCounts(SourceTree tree) => countPerFile(
      tree,
      'lib/src/ui',
      r'\bthis\.(controller|shell|settings)\b',
    );

/// Every repository or controller constructed inside `lib/src/ui/`.
///
/// `AGENTS.md` §0.9 and `docs/isolate_pattern.md` §3.1: construction belongs to a
/// provider, so that both surfaces build the same graph instead of each writing
/// its own.
Map<String, int> uiConstructionCounts(SourceTree tree) => countPerFile(
      tree,
      'lib/src/ui',
      r'\b(?:Notes|Settings|Widget|Selection)Repository\s*\(|\b'
      r'(?:Notes|Settings|Widget)Controller\s*\(',
    );

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
  final names = <String>{};
  final text = tree.read('lib/src/platform/shell_channel.dart');

  final idioms = <RegExp>[
    RegExp(r"_fire\s*\(\s*'([^']+)'"),
    RegExp(r"_invoke(?:<[^>]*>)?\s*\(\s*'([^']+)'"),
    RegExp(r"invokeMethod(?:<[^>]*>)?\s*\(\s*'([^']+)'"),
    RegExp(r"invokeMapMethod(?:<[^>]*>)?\s*\(\s*'([^']+)'"),
  ];

  for (final idiom in idioms) {
    for (final m in idiom.allMatches(text)) {
      names.add(m.group(1)!);
    }
  }
  return names;
}

/// The inbound namespace the runner pushes *up* to Dart.
///
/// Separate from [channelMethodNames] by construction rather than by convention:
/// `event.*` is runner-to-Dart and `everything else` is Dart-to-runner, and the
/// two sets being disjoint is checked rather than assumed. They travel on one
/// channel, which is exactly why they are easy to confuse.
const Set<String> inboundEventPrefixes = {'event.'};

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
  final faults = <String>[];

  final declaredButNeverCalled = registry.difference(called).toList()..sort();
  if (declaredButNeverCalled.isNotEmpty) {
    faults.add(
      'The registry declares methods Dart never sends: '
      '${declaredButNeverCalled.join(', ')}.\n'
      '    Either the declaration is aspirational or the call was deleted. '
      'docs/platform_pattern.md §3.1 records what the contract *is*, not what '
      'it might become.',
    );
  }

  final calledButNotDeclared = called.difference(registry).toList()..sort();
  if (calledButNotDeclared.isNotEmpty) {
    faults.add(
      'Dart sends methods that are not in the registry: '
      '${calledButNotDeclared.join(', ')}.\n'
      '    An undeclared method is the failure this file exists to prevent: it '
      'works until the runner is renamed, and then result->Success() is '
      'returned anyway so the Dart await completes and nothing happens.',
    );
  }

  final declaredButUnhandled =
      registry.difference(handled).toList()..sort();
  if (declaredButUnhandled.isNotEmpty) {
    faults.add(
      'The registry declares methods the runner does not handle: '
      '${declaredButUnhandled.join(', ')}.',
    );
  }

  final handledButNotDeclared =
      handled.difference(registry).toList()..sort();
  if (handledButNotDeclared.isNotEmpty) {
    faults.add(
      'The runner handles methods that are not in the registry: '
      '${handledButNotDeclared.join(', ')}.',
    );
  }

  final inboundLeaked = registry
      .where((name) => inboundEventPrefixes.any(name.startsWith))
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