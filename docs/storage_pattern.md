# Storage Pattern — One Writer Per File, Atomic Replace, Recovery That Never Destroys

`lib/src/core/atomic_json_file.dart`, `lib/src/data/notes_repository.dart`

Companions: `docs/widget_pattern.md` (what the widget does with the files it
reads) and `docs/testing_pattern.md` (why the bugs in this file shipped).

---

## 1. Architecture Overview

```
lib/src/
  core/
    atomic_json_file.dart        11 file operations   the only safe way to write
    paths.dart                                    %APPDATA% locations
  data/
    note.dart                    the model; completedAt is nullable
    notes_repository.dart         8 file operations   owns notes.json
    settings_repository.dart                        owns settings.json
    widget_state_repository.dart                    owns widget_state.json
    selection_repository.dart      selection.json: neither surface owns it
```

Every surface-shared file goes through `AtomicJsonFile`. There is no second
writer and no second code path, so the guarantees below hold for all of them
rather than for `notes.json` alone.

**The four files and who writes them:**

| File | Writer | Read by |
|---|---|---|
| `notes.json` | editor, or widget when no editor exists | both |
| `settings.json` | whichever surface changed a setting | both |
| `widget_state.json` | widget | both (position, opacity, backdrop) |
| `selection.json` | whichever surface changed focus | both |

---

## 2. Why this file exists

Four shipped bugs live in this seam, and each one is a rule below:

1. **Reads had no retry ladder.** Writes retried because antivirus holds the
   destination; reads did not. The same antivirus that made a write late could
   make a *startup* fail outright. Shipped as "your notes file is corrupt" when
   the file was perfectly intact and locked for 200 ms.
2. **`WidgetController.flush()` drained the wrong files.** It flushed
   `widget_state.json` and `selection.json` but not `notes.json`, so quitting
   within 250 ms of ticking a task silently undid the tick.
3. **No rolling backup.** `notes.json` could be damaged from outside — a
   hand-edit, a syncing tool writing two copies, a dropped sector — and there
   was no route back. The person was told to start fresh.
4. **The plain-text export was written non-atomically from the UI layer**, past
   this file entirely. See §6.

---

## 3. The rules

### 3.0 The data directory is resolved once, and can be redirected

`%APPDATA%\WinNotes`, named once by the native runner and handed to Dart in the
bootstrap payload. `AppPaths.resolve` is the single place that turns it into a path,
and every file — `notes.json`, `settings.json`, `widget_state.json`, `selection.json`
— hangs off the result.

`WIN_NOTES_DATA_DIR` overrides it, and exists for one reason: **tooling must be able to
run this app without touching a real profile.** A verification run against
`%APPDATA%\WinNotes` is not a test, it is a hazard — and the first version of
`tool/verify/verify_release.ps1` was one, because it moved the real profile aside,
restored it, and then deleted it on the next line. The override is the fix that removes
the need to move anything at all.

Two constraints, both load-bearing:

- **Absolute only.** A relative value resolves against the runner's working directory,
  which is not anywhere the caller chose.
- **No `..`.** It walks out of whatever was intended, which is how an override becomes
  the thing it promised not to be.

A blank value is ignored rather than honoured, because an environment variable set to
`""` is a thing that happens and the empty string is a data directory where every read
is a silent miss.

Note the sharp edge this created: `main()` also *creates* the data directory before any
widget exists, and that line originally used the reported path rather than the resolved
one — so the real profile was created anyway on every isolated run. An override that is
honoured for reading and writing but not for setup is worse than no override, because it
looks like isolation. `isolate_guard_test` checks the two names are not confused.

### 3.0a The chosen folder is honoured, or the setting is a lie

`PROJECT.md` §114 promised a storage location in Settings. For a long time it was one,
and it did nothing: the picker saved a path, the dialog displayed it, and every file
went to `%APPDATA%\WinNotes` regardless. Verified on a release build — point the app at
an empty folder, launch, and the folder stays empty.

**A setting that is displayed but not obeyed has no symptom.** The build was clean, the
tests were green, and the app was honest in the one place that read the setting back.
So this is stated as a rule rather than left to review:

- **The configured location reaches `AppPaths`.** `main()` resolves it and applies it;
  computing it and not applying it is the same failure wearing a hat.
- **A chosen folder that is not reachable is refused, not created.** `main()` creates
  the data directory, so a well-shaped path to an unplugged drive would be *recreated*
  locally and filled with an empty library — total loss wearing the costume of a
  successful launch. The reachability check therefore must not create the folder it
  asks about, which is the only way it can answer "no".
- **A corrupt or unreadable `settings.json` is "no folder chosen",** never an exception.
  Losing preferences is a nuisance; refusing to start would leave somebody unable to
  reach their notes to fix it. This is deliberately the opposite of §3.7.

Two copies of `settings.json` exist once a folder is chosen, and both are load-bearing:

| Copy | Where | Why |
|---|---|---|
| pointer | always `reportedDirectory` | it is how the next launch finds the chosen folder, and it has to be readable before the answer is known |
| library | `dataDirectory` | it makes the chosen folder self-contained, so it can be moved, backed up or handed over on its own |

When they disagree the chosen folder's own copy wins, because that is what makes a moved
folder keep working.

### 3.0b Changing the folder copies; it never moves

`StorageTransfer` implements it. Three rules, all about not losing notes:

- **Copy, never move.** Nothing is deleted from the source. A person who has seen the
  copy arrive can remove the old one themselves, having checked. An app that deletes it
  has taken the check away.
- **Never overwrite a library that was never read.** A destination already holding
  notes is refused, and the refusal is worded as the app protecting them rather than as
  a failure. An empty `notes.json` is not a library and does not block anything.
- **Flush before copying, and write the pointer last.** A keystroke can still be in the
  debounce window, and a pointer written first would point the next launch at a folder
  the copy never reached.

**A restart is required and the UI says so.** `appPathsProvider` is overridden in
`main()` with a value fixed for the life of the process, so a session keeps writing
where it started. Rebuilding every repository under a running editor to avoid a restart
is not a trade worth making; the honest answer is "restart".

### 3.1 One writer per file, decided by the runner

The two surfaces are separate isolates with separate memory. They never talk
directly; they share files. So "who may write" is not a style question, it is
the only thing preventing lost keystrokes.

The decision is made by asking the **runner**, not by guessing locally:

```dart
if (await _shell.isEditorRunning()) {
  await _shell.requestCreateNote(title: title, body: body);   // editor writes
  return;
}
// no editor: nothing buffered, this surface writes
```

Guessing is wrong in both directions. If the widget assumed it was the writer
while an editor was open, it would overwrite keystrokes the editor still held in
memory for up to 250 ms — the debounce window. If the editor assumed it owned the
file while running headless under autostart, the tick would go nowhere.

`NotesRepository`'s own doc comment says the widget "reads this file and never
writes it". That is true of the widget's *reader*; `WidgetController` writes
through the same repository only in the no-editor branch, and only after asking.

### 3.2 Writes are atomic

The whole document goes to `notes.json.tmp`, is flushed, and is then renamed
over the target. `rename` replaces the destination on Windows, so a reader sees
either the whole old file or the whole new one.

A torn write is what turns a recoverable problem into lost notes, so this is
not an optimisation. A failed replace leaves the temp file **in place** rather
than deleting it, so a partial write can never be mistaken for real data on the
next run.

### 3.3 Writes coalesce, with a ceiling as well as a trailing edge

Typing produces an edit per character. Without a debounce that is one atomic
rewrite per keystroke.

Two timers, and **they deliberately do not reset each other**:

- `_debounceTimer` — 250 ms, slides with every keystroke.
- `_maxTimer` — 1500 ms, set only when nothing is pending.

Resetting the ceiling on each write turns it into a second debounce with a
longer delay, and continuous typing then never writes at all — which is exactly
the scenario the "killed mid-sentence loses nothing" promise is about.

### 3.4 Writes retry on a bounded ladder

`[250, 500, 1000, 2000]` ms. Replacing a file on Windows fails outright whenever
something else holds the destination open, and on a live desktop that is
routinely Search Indexer, antivirus, or a backup tool. It clears in
milliseconds. Retrying turns a lost write into a slightly late one.

Bounded, because a genuinely unwritable destination — full disk, read-only
folder — would otherwise retry for the rest of the session.

On failure the payload goes back: `_pending ??= payload`. The `??=` is
load-bearing. A keystroke may have arrived while the write was in flight, and
that newer value is the one that should win; a plain `=` would discard it.

### 3.5 Reads walk a ~2.5 s ladder, and only when they cannot *open* the file

`[40, 80, 160, 320, 640, 1280]` ms. Long enough for a real-time scan, paid for
only when something is genuinely in the way.

Two cases are excluded from the ladder, because retrying them is wrong:

- **Error codes 2 and 3** (not found, path not found) — deleted or moved between
  the `exists()` check and the read. Retrying adds two seconds to a first run.
- **A parse failure.** The file opened and its bytes did not parse, which means
  the content is wrong. Waiting cannot change the content; retrying only delays
  telling someone their file needs attention.

### 3.6 Transient and damaged are different problems with different wording

This is the distinction that decides what the user is told, and it is not
cosmetic:

| | Meaning | What the user is offered |
|---|---|---|
| **Transient** | Could not open. Almost certainly held by a scanner. | "Something is holding your notes file" → Try again |
| **Damaged** | Opened, did not parse. | "Restore the previous version" / "Start fresh instead" |

Saying "your notes file is broken" about a file that is locked for 200 ms is
both alarming and wrong. Offering to start fresh would invite someone to rename
a healthy file.

`transient: true` is set **only after the whole ladder has been walked**, so it
means "still held after retrying", not "held once".

### 3.7 A failed read blocks every write

`AtomicJsonFile.blocked` is set on a failed *read*. While it is non-null every
write is a no-op. This is what stops the app from "recovering" by replacing a
file nobody has read yet — the one failure this project will not risk.

A failed **write** does not set it. The notes are perfectly readable, and
blocking on a transient write failure would be both a lie to the user and a way
to lose the next edit.

### 3.8 Watch the directory, never the file

```dart
_watchSubscription = parent.watch(recursive: false).where((event) =>
    _normalise(event.path) == target).listen(...);
```

`File.watch()` on Windows keeps a handle open on the file itself, which blocks
anyone else from replacing or deleting it: the other isolate's atomic rename
fails, a backup tool fails, and a person trying to back notes up by hand gets an
error. The promise that the notes file can be read and handled without this app
in the way depends on not holding it. A directory watcher takes a shared handle
on the folder, which stops nothing.

Echo suppression is by content, not by bookkeeping: `_scheduleReload` waits
120 ms for the burst of events one logical write produces, then compares the
result to `_lastKnown` and calls back only if it differs.

### 3.9 `notes.json.bak` is written before every atomic replace

One write behind. That costs at most the debounce window of typing — a fraction
of a second — and buys back everything before it.

Because writes are atomic, WinNotes can never produce a file it cannot read. So
corruption is always something external: a hand-edit, a syncing tool writing two
copies at once, a disk that dropped a sector. In every one of those cases the
thing that saves the notes is the last state this app itself put on disk.

Backup failures are swallowed deliberately. A backup that could not be taken is
a reason to lose the safety net, not a reason to lose the edit being written.

### 3.10 Recovery copies; it never re-serialises

```dart
await File(backup).copy(_file.path);   // not saveNow(notes)
```

A normal write would first copy the file it is replacing — the *corrupt* one —
over the backup. Recovering would destroy the only good copy you had. Copying
leaves `notes.json` and `notes.json.bak` both holding the recovered version, so
the net is still there if the file is damaged a second time.

`saveNow` is the fallback when the copy itself is blocked, and losing the
safety net is an acceptable trade for getting the notes back.

### 3.11 Starting fresh renames, never deletes

```
notes.json  ->  notes.json.broken-2026-10-04T12-31-08.123456
```

The file on disk may be recoverable by hand, or by someone better at JSON than
the person staring at the screen. Throwing away the only copy of a damaged file
to make a button feel better would be the opposite of what this project is for.
The timestamp means a second incident cannot overwrite the first one's evidence.

`restoreBackup()` returning null leaves the block in place. A half-applied
recovery that loses the notes it read would be the worst outcome available.

### 3.12 Toggling completion must not bump `updatedAt`

Notes sort by recency (`updatedAt` descending, `id` descending to break ties). So
bumping the timestamp when a task is ticked would shuffle the list every time
someone used the feature it exists for. Finishing is a state change, not an edit.

`completedAt` is a nullable timestamp, **omitted from `toJson` when unset**. Old
files are unchanged by the feature; absent means unfinished.

### 3.13 `loadFrom` is more forgiving than `load`

`load()` refuses anything it did not write. `loadFrom()` — used when *reading a
candidate backup* — skips individual unreadable notes instead of condemning the
file. Refusing the whole backup would throw away notes that are perfectly fine,
which is the opposite of what someone recovering from corruption needs.

### 3.14 `markdown` decides presentation and touches nothing else

`Note.markdown` is a boolean, defaulting to false, **omitted from `toJson` when
false** on the same rule as `completedAt` (§3.12): a file written before the
field existed, and a file of ordinary notes written after it, are byte-identical
to what they were. Absent means plain text. Only a literal `true` in the JSON
turns it on, so a hand-edited `"markdown": "yes"` cannot produce a note the
renderer has never been asked to handle.

The rule that matters is that it is **presentation, not content**. Turning it on
or off must leave `title` and `body` byte-for-byte identical. Rendering derives
a widget tree from the stored source and never writes back; the plain-text
export emits the source verbatim; search matches the source. So someone can
write Markdown, change their mind, and get their asterisks and hashes back
exactly as typed.

That is also what keeps the format what it has always been: a note is a title
and a body in `notes.json`, not a document tree. Nothing is serialised in a form
the app would have to read back differently.

### 3.15 Switching a note into Markdown *does* bump `updatedAt`

The deliberate opposite of §3.12, and the reason the two rules sit next to each
other.

Finishing a task does not reorder the list, because finishing is not an edit.
Switching a note into Markdown **is** an edit: it changes what the note says to
everybody who looks at it, including the widget, so it earns its place at the
top of the recency order like any other change.

Setting the flag to the value it already has must be a no-op on both the
timestamp and the write. Otherwise tapping the switch twice in a row would move
a note to the top of the list for no reason, which is the exact failure §3.12
exists to prevent, reintroduced through a different door.

---

## 4. The traps

- **`dart:io` cannot hold an exclusive lock.** `File.openSync` uses
  `FILE_SHARE_READ | FILE_SHARE_WRITE`, so you cannot reproduce a scanner holding
  the file from Dart. This is why bug 1 shipped: the test suite had no way to
  hold the file. The lock tests call `CreateFileW` through `dart:ffi` and
  allocate the UTF-16 path by hand with `malloc` (`package:ffi` is deliberately
  not a dependency).
- **Do not add a retry around `jsonDecode`.** Covered in §3.5; it converts a
  clear diagnosis into a 2.5-second wait before the same clear diagnosis.
- **`_pending ??= payload`, not `_pending = payload`.** §3.4.
- **Resetting both timers makes the ceiling inert.** §3.3.
- **`Sort` must break ties on `id`.** Two edits in the same millisecond otherwise
  produce an order that shuffles between two writes of the same content.
- **Completion is not in the plain-text backup, on purpose.** That file has to
  stay readable in Notepad years from now. There is no plain-text spelling of
  "struck through" that is not a formatting convention, and inventing one would
  make the backup a worse backup.

---

## 5. Adding work

- **A new shared file** → wrap it in `AtomicJsonFile`. Do not add a second
  writer path. If both surfaces can change it, ask the runner which one owns it
  (§3.1) and route through `ShellChannel` if it is not obvious.
- **A new recoverable artefact** → the `.bak` rule is per-file and costs one
  `copy` before the rename. Extend it there, not at the call site.
- **A new read failure** → decide transient vs damaged *at the point of the
  throw*, and set `transient` only once the ladder is exhausted.
- **A new recovery route** → it must not destroy the input. Copy or rename;
  never `saveNow` over something you have not read.

---

## 6. Layer isolation

`dart:io` file operations belong to `core/` and `data/`. Today: **19 operations
across 2 files** (`atomic_json_file.dart` 11, `notes_repository.dart` 8), and
**zero** anywhere else.

This was not true. `ui/` held 8 operations across 2 files, and the one that
mattered was the export:

```
lib/src/ui/editor/editor_app.dart:162   await File(path).writeAsString(text);
```

**Not atomic.** An interrupted export leaves a truncated file, and that file is
the one someone reaches for when everything else has gone wrong. It is now
`BackupService.exportTo`, which goes through `AtomicJsonFile.writeTextAtomically`
— the same temp-and-rename the notes file uses — and the other five reads are
behind `BackupService.readFrom` and `NotesRepository.describeFile`.

**Enforced:** `test/architecture/layer_test.dart` fails on any `dart:io`
operation in `ui/`, `state/` or `platform/`. The guard has no allowlist, on
purpose: if a write genuinely cannot go through `data/`, the fix is to edit the
scanner, where the diff shows it, rather than to grow a list somewhere quiet.

**The rule:** writes go through `AtomicJsonFile`. Reads that need
`existsSync` / `lengthSync` / `lastModifiedSync` belong behind a repository
method, because that is where `blocked` lives and a read in the UI cannot see it.

---

## 7. Frozen identifiers

Changing any of these breaks files already on disk:

- `"format": "winnotes"` — a document without it is refused (§3.13).
- `notes[].id`, `.title`, `.body`, `.createdAt`, `.updatedAt`, `.completedAt`
- `notes[].completedAt` **omitted when unset**, never `null`
- `notes.json.bak`, `notes.json.broken-<stamp>`
- `settings.json` `accentPalette` — **omitted when unset**, and resolved at the
  edge by `paletteById`, which treats an unrecognised name as the default rather
  than as an error. The **palette ids themselves are frozen too**
  (`lib/src/ui/palette.dart`): they are in people's `settings.json`, so
  renaming one silently resets anyone who chose it. Add palettes, do not
  rename.
- The default palette is index **zero**, not a named constant, because a
  `settings.json` written before the setting existed resolves to it. Reordering
  the list changes what an existing install sees.
- `BackupService.separator` — a 40-dash rule. The importer does **not** match on
  this exact string; it splits on any unindented line of three or more
  `-`, `*` or `_`, which is what lets a body containing a rule survive the round
  trip. Bodies are indented 4 spaces so they can never look like a boundary.

---

## 8. Tests

Every numbered rule in §3 appears here. A rule with no row is a comment, and
`test/architecture/docs_test.dart` fails the build if that happens or if a
cited test stops existing.

| § | Rule | Pinned by |
|---|---|---|
| 3.0 | The data directory is resolved once, and can be redirected | `app_paths_test` *an absolute path wins over the reported one*, *the real profile is not named anywhere in the result*, *a relative path is refused*, *a path with .. is refused*, *an empty override is ignored rather than resolving to nowhere*; **guard** `isolate_guard_test` *main() never touches the reported directory when an override is set* |
| 3.0a | The chosen folder is honoured, or the setting is a lie | **guard** `storage_location_guard_test` *the data directory comes from the resolver, not from the runner*, *and it is applied to the paths, not just computed*, *the reported directory is still what settings.json is read from*, *the resolver asks whether the folder is reachable*, *and the reachability check never creates the folder it is asked about*, *main() creates the directory it resolved, which is the only creator*, *the bootstrap reader never throws*; `storage_location_test` *a pointer names the folder, and files go there*, *a chosen folder that has gone is not silently replaced by an empty one*, *the chosen folder's own settings.json wins when the two disagree*, *a corrupt settings file is treated as no choice at all* |
| 3.0b | Changing the folder copies; it never moves | **guard** `storage_location_guard_test` *the transfer code contains no delete of a source file*, *a destination that already has notes is refused*, *the source is flushed before anything is copied*, *the pointer is written last*; `storage_location_test` *every file arrives, and the original is left alone*, *the destination settings.json names the destination*, *a destination that already has notes is refused, and nothing is touched*, *the same folder is reported rather than copied onto itself* |
| 3.1 | One writer per file, decided by the runner | **guard** `storage_guard_test` * only the two notifiers write notes.json*, *every widget-side write asks the runner first*, *the editor notifier is the writer and does not ask itself*; `widget_integration_test` * a jotted line becomes a note, routed to the editor*, *with no editor, the widget writes the note itself* |
| 3.2 | Writes are atomic | `notes_repository_test` → *a concurrent reader never observes a partially written file*, *no temp file is left behind after a successful write*, *writes replace the file rather than appending to it* |
| 3.2 | …and the export too | **guard** `storage_guard_test` → *exportTo goes through the atomic writer*, *the backup is taken before the replace, not after*, *the export does not write the destination directly*; `backup_service_test` → *the file appears whole, not in pieces*, *nothing is left half-written beside the target* |
| 3.3 | Debounce plus ceiling | `notes_repository_test` → *a burst of writes coalesces into one file change*, *the ceiling fires even while writes keep arriving*, *a continuous burst still reaches disk before the process dies* |
| 3.4 | Write retry ladder | `notes_repository_test` → *a write that cannot land neither blocks the file nor loses the value* |
| 3.5 | Read ladder, and what not to retry | `notes_controller_test` → *a read that opens fine is not made to wait on the retry ladder* |
| 3.6 | Transient vs damaged | `notes_controller_test` → *a file that cannot be opened is reported as transient, not damaged*, *a file that opens but does not parse is not transient* |
| 3.7 | A failed read blocks writes | `notes_repository_test` → *while blocked, every write is a no-op and the file is untouched*, *a restore can lift the block and write for real* |
| 3.8 | Watch the directory | **guard** `storage_guard_test` → *the subscription is on the parent directory*, *nothing watches the file itself*, *the events are filtered down to the one file* |
| 3.9 | `.bak` before every replace | `notes_controller_test` → *each write leaves the previous version behind*; `notes_repository_test` → *the backup holds the PREVIOUS content, not the new one* |
| 3.10 | Recovery copies | `notes_controller_test` → *the previous version restores the notes*, *restoring reports when there is nothing to restore* |
| 3.11 | Start fresh renames | `notes_controller_test` → *starting fresh keeps the unreadable file*, *a second incident does not overwrite the first one*, *starting fresh writes a valid file, so it does not refuse again* |
| 3.12 | Completion does not reorder | `notes_controller_test` → *finishing a note does not reorder the list*, *undo brings a finished note back finished* |
| 3.13 | `loadFrom` is forgiving | `notes_repository_test` → *loadFrom keeps the notes it can read when one entry is broken*, *loadFrom returns empty rather than claiming damage on a non-backup* |
| 3.14 | `markdown` is presentation only | `markdown_test` → *is omitted from the file when off, so old notes stay untouched*, *absent means off*, *only a literal true turns it on*, *copy carries it, because undo restores a note wholesale*, *the body is never rewritten by turning it on or off*, *the source keeps the syntax while it is being typed* |
| 3.15 | …but switching it on does reorder | `markdown_test` → *turning it on bumps updatedAt, unlike finishing a task*, *setting it to what it already is does nothing*, *turning it on changes the note and persists*, *a note that is not there is ignored* |
| — | A missing file is a first run | `notes_repository_test` → *a missing file is a first run, not an error*, *a file with only whitespace is treated as empty* |
| — | Format tag enforced | `notes_repository_test` → *valid JSON that is not a WinNotes document is also refused*, *a notes entry that is not a list is refused*, *a note entry that is not an object is refused*, *a note missing its id is refused rather than skipped* |
| — | Sort and its tiebreak | `notes_repository_test` → *most recently edited comes first*, *equal timestamps still produce a stable order* |
| — | Backup format | `backup_service_test` → all five groups |
| — | Whitespace-only body normalises | `backup_service_test` → *a whitespace-only body comes back empty, not as blank lines* |
| — | Lock behaviour | `notes_controller_test` → the `_ExclusiveLock` FFI helper (§4) |
| — | `dart:io` confined to `core/`+`data/` | **guard** `layer_test` → *no file operation appears in ui/, state/ or platform/* |
| — | `accentPalette` omitted when unset | `palette_test` → *omitted from the file entirely when never chosen* |
| — | Unknown palette id is kept, not rewritten | `palette_test` → *an unknown value in the file is kept, not silently rewritten* |

**Not covered, and deliberately:** `completedAt` reaching the plain-text backup.
It does not, by decision (§4).

**Not covered, and honestly:** editing a note from the editor and watching the
*widget* react to it goes through the directory watcher and a debounce, so it is
not asserted directly. The reload path itself is covered in `notes_controller_test`.

---

## 9. Guarantees

1. A kill at any moment leaves either the previous whole file or the next whole
   file. Never half of either.
2. Typing continuously still reaches disk within 1.5 s.
3. A file held by a scanner for up to ~2.5 s is read normally, and is never
   described to the user as damaged.
4. A file that *is* damaged is never overwritten by the app, and never deleted.
5. There is always a last-known-good copy one write behind, unless the backup
   itself could not be taken.
6. Recovering from that copy does not consume it.
7. A tick does not reorder the list.
8. The notes file can be copied, backed up, or read by another tool while the
   app is running.