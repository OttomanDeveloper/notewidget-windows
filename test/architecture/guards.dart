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