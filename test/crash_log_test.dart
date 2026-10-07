/// The crash log, because a release build has nowhere else to put an error.
///
/// `main.cpp` creates a console only when a debugger is attached, so a build
/// launched at login prints nothing. This app has no telemetry and no upload
/// (`PROJECT.md`), so this file is the only way a failure is ever reported.
///
/// The property that matters most is not tested here: that the log never carries
/// note content. It is tested by [a crash log carries no note text] below, which
/// is the test that would stop someone adding a convenient `notes` field.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter_test/flutter_test.dart';
import 'package:win_notes/core/utils/crash_log.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('wn_crashlog'));
  tearDown(() {
    if (temp.existsSync()) {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // A locked handle is a temp folder, not a failure.
      }
    }
  });

  String logPath() => '${temp.path}\\crash.log';
  String previousPath() => '${logPath()}.1';

  test('a crash is written with its stack, not just its message', () {
    CrashLog(logPath()).record(
      StateError('the widget was told to restore nothing'),
      StackTrace.current,
    );

    final File file = File(logPath());
    expect(file.existsSync(), isTrue,
        reason: 'the whole point: an uncaught error that only reached a console '
            'nobody is watching found nobody');

    // The file is a sequence of entries, not one object, so a single crash is
    // parsed by trimming its trailing brace. A `\\n` is not valid between JSON
    // values, which is why it is one object per line-group rather than NDJSON.
    final String raw = file.readAsStringSync();
    final Map<String, dynamic> entry =
        jsonDecode(raw.substring(0, raw.lastIndexOf('}') + 1)) as Map<String, dynamic>;
    expect(entry['error'], contains('the widget was told to restore nothing'));
    expect(entry['stack'], isNotEmpty, reason: 'a message alone cannot be acted on');
    expect(entry['source'], 'dart');
    expect(entry['at'], isNotNull, reason: 'an incident with no time is hard to match to a launch');
  });

  test('each crash is its own entry, so a second one does not overwrite the first', () {
    final CrashLog log = CrashLog(logPath());
    log.record(StateError('first'), StackTrace.current);
    log.record(StateError('second'), StackTrace.current);

    // Counted by its own closing brace, not by line: the entry is indented
    // multi-line JSON, so two crashes are not two lines.
    final String body = File(logPath()).readAsStringSync();
    expect('}'.allMatches(body).length, 2,
        reason: 'a second incident losing the first is the same failure as '
            '`docs/storage_pattern.md` §3.11, one level up');

    expect(body, contains('first'));
    expect(body, contains('second'));
  });

  test('a crash log carries no note text', () {
    // The one test that must never be relaxed. This file gets pasted into a
    // public issue (`ISSUE_REPORTING.md`), so a note title in it is a note
    // published. Sizes and lengths are enough to tell "the notes failed to parse"
    // from "there were no notes", and nothing more is worth the risk.
    final File notes = File('${temp.path}\\notes.json');
    notes.writeAsStringSync(
      '[{"id":"a","title":"Dentist Tuesday","body":"bring the referral letter"}]',
    );

    CrashLog(logPath()).record(
      StateError('failed while reading notes'),
      StackTrace.current,
    );

    final String body = File(logPath()).readAsStringSync();
    expect(body, isNot(contains('Dentist')));
    expect(body, isNot(contains('referral letter')));
    expect(body, isNot(contains(notes.readAsStringSync())),
        reason: 'the file itself must not be quoted into the log');
    expect(body, contains('notesBytes'),
        reason: 'the size is the part that is safe and still useful');
  });

  test('rotation renames rather than deletes, so the previous crash survives', () {
    final File live = File(logPath());
    // Under the cap in one write: a full 256 KB of padding per test would be
    // slow, and the cap itself is a constant rather than the behaviour.
    live.writeAsStringSync('x' * (CrashLog.maxBytes + 16));

    CrashLog(logPath()).record(StateError('after rotation'), StackTrace.current);

    expect(File(previousPath()).existsSync(), isTrue,
        reason: 'the incident that filled the file is the one most worth reading');
    expect(File(previousPath()).readAsStringSync(), contains('xxxx'));
    expect(live.readAsStringSync(), contains('after rotation'));
    expect(live.lengthSync(), lessThan(CrashLog.maxBytes),
        reason: 'the live file is the new one, not the old one plus more');
  });

  test('an unwritable path does not raise', () {
    // A handler that throws while reporting a crash replaces a useful stack
    // trace with a useless one, so this must not escape.
    expect(
      () => CrashLog('Z:\\definitely\\not\\a\\drive\\crash.log')
          .record(StateError('boom'), StackTrace.current),
      returnsNormally,
    );
  });

  test('an installed handler catches an uncaught framework error', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final CrashLog log = installCrashHandlers(CrashLog(logPath()));

    expect(log, isNotNull, reason: 'the log is returned so a caller keeps one instance');

    // Driven through the real handler rather than by calling `record` directly,
    // because the wiring is what breaks: a handler installed on the wrong object
    // records nothing and looks installed all the same.
    FlutterError.onError!(FlutterErrorDetails(
      exception: StateError('thrown during build'),
      stack: StackTrace.current,
      library: 'win_notes test',
    ));

    expect(File(logPath()).readAsStringSync(), contains('thrown during build'));
  });
}
