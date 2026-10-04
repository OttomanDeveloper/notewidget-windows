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
across 2 files** (`atomic_json_file.dart` 11, `notes_repository.dart` 8).

`ui/` currently has **8 in 2 files, and all 8 are a known divergence**:

```
lib/src/ui/editor/editor_app.dart:162   await File(path).writeAsString(text);
lib/src/ui/editor/editor_app.dart:172   final file = File(path);
lib/src/ui/editor/editor_app.dart:175   _backup.import(await file.readAsString());
lib/src/ui/editor/editor_view.dart:539  File(error.path).existsSync()
lib/src/ui/editor/editor_view.dart:542  File(error.path).lengthSync()
lib/src/ui/editor/editor_view.dart:543  File(error.path).lastModifiedSync()
```

**Why it matters:** the export at `editor_app.dart:162` is **not atomic**. An
interrupted export leaves a truncated file, and that file is the one someone
reaches for when everything else has gone wrong. The other five are reads and
are merely untidy — a widget stat-ing the filesystem is a smell, not a hazard.

**The rule going forward:** writes go through `AtomicJsonFile`. Reads that need
`existsSync` / `lengthSync` / `lastModifiedSync` belong behind a repository
method, because that is where `blocked` lives and a read in the UI cannot see it.

---

## 7. Frozen identifiers

Changing any of these breaks files already on disk:

- `"format": "winnotes"` — a document without it is refused (§3.13).
- `notes[].id`, `.title`, `.body`, `.createdAt`, `.updatedAt`, `.completedAt`
- `notes[].completedAt` **omitted when unset**, never `null`
- `notes.json.bak`, `notes.json.broken-<stamp>`
- `BackupService.separator` — a 40-dash rule. The importer does **not** match on
  this exact string; it splits on any unindented line of three or more
  `-`, `*` or `_`, which is what lets a body containing a rule survive the round
  trip. Bodies are indented 4 spaces so they can never look like a boundary.

---

## 8. Tests

| Rule | Pinned by |
|---|---|
| Missing file is a first run | `notes_repository_test` → *a missing file is a first run, not an error* |
| Zero-length file is a leftover temp | `notes_repository_test` → *a file with only whitespace is treated as empty* |
| Valid JSON that is not ours is refused | `notes_repository_test` → *valid JSON that is not a WinNotes document is also refused* |
| A failed read blocks every write | `notes_repository_test` → *while blocked, every write is a no-op and the file is untouched* |
| A restore can lift the block | `notes_repository_test` → *a restore can lift the block and write for real* |
| Write retry does not lose the value | `notes_repository_test` → *a write that cannot land neither blocks the file nor loses the value* |
| Debounce coalesces | `notes_repository_test` → *a burst of writes coalesces into one file change* |
| Ceiling is not a second debounce | `notes_repository_test` → *the ceiling fires even while writes keep arriving* |
| Atomicity | `notes_repository_test` → *a concurrent reader never observes a partially written file* |
| No temp left behind | `notes_repository_test` → *no temp file is left behind after a successful write* |
| Sort and its tiebreak | `notes_repository_test` → *most recently edited comes first*, *equal timestamps still produce a stable order* |
| Transient vs damaged | `notes_controller_test` → *a file that cannot be opened is reported as transient, not damaged*, *a file that opens but does not parse is not transient* |
| The ladder is not walked needlessly | `notes_controller_test` → *a read that opens fine is not made to wait on the retry ladder* |
| `.bak` exists | `notes_controller_test` → *each write leaves the previous version behind* |
| Restore works and can report nothing to do | `notes_controller_test` → *the previous version restores the notes*, *restoring reports when there is nothing to restore* |
| Start fresh never deletes | `notes_controller_test` → *starting fresh keeps the unreadable file* |
| A second incident keeps its evidence | `notes_controller_test` → *a second incident does not overwrite the first one* |
| Completion does not reorder | `notes_controller_test` → *finishing a note does not reorder the list* |
| Completion survives undo | `notes_controller_test` → *undo brings a finished note back finished* |
| Lock behaviour | `notes_controller_test` → the `_ExclusiveLock` FFI helper (§4) |
| Backup round trip, dividers in bodies, hand-edited files | `backup_service_test` → all four groups |
| Whitespace-only body normalises to empty | `backup_service_test` → *a whitespace-only body comes back empty, not as blank lines* |

**Not covered here, and deliberately:** `completedAt` reaching the plain-text
backup. It does not, by decision (§4).

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