# Contributing

WinNotes is a small project and the bar for a change is mostly "does it lose
data". This file is the short version; the code carries the reasoning in
comments where it belongs.

## Getting set up

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)
(stable) and [Visual Studio 2022](https://visualstudio.microsoft.com/downloads/)
with the **Desktop development with C++** workload. The second one is not
optional: the runner is native C++, and `flutter build windows` fails without it.

```
git clone https://github.com/OttomanDeveloper/notewidget-windows.git
cd notewidget-windows
flutter pub get
flutter doctor -v      # Flutter and "Visual Studio - develop Windows apps" both green
```

Run it with `flutter run -d windows`. Both windows appear: the widget on your
desktop and the editor as an ordinary window.

## Before you change anything

```
flutter test           # 113 tests, must be green
flutter analyze
```

CI runs both, plus a real Windows build, on every push and pull request.

## How the project is put together

Two things are worth knowing before you touch anything, because most mistakes
come from violating one of them.

**One writer per file.** Each surface owns its data. The editor writes
`notes.json` and `settings.json`, the widget writes `widget_state.json`, and
either may write `selection.json`. That is the entire concurrency story: there
is no merge logic anywhere, because there is never a moment when two surfaces
write the same file. If your change needs two surfaces to write the same file,
the design is wrong, not the merge code.

**The surfaces never talk directly.** They are separate processes with separate
Dart isolates and they share only files. The widget watches the *directory*
holding `notes.json`, not the file, because a Windows file watcher holds a handle
open that blocks the other isolate's atomic rename.

```
lib/
  main.dart              entry point for both surfaces
  src/
    core/                paths, atomic JSON file with debounce, retry and watch
    data/                note model, repositories, plain-text backup format
    platform/            typed wrapper over the runner's method channel
    state/               notes, settings and widget controllers
    ui/                  editor, widget, settings dialog, shared widgets
windows/runner/          native host: windows, tray, hotkey, autostart, acrylic
installer/               Inno Setup script for the setup.exe
tool/
  brand/                 logo generator
  release/               packaging: builds, verifies, zips, signs nothing
  screenshots/           screenshot capture for the README
```

## Rules that are not stylistic

**Never write a file non-atomically.** Go through `AtomicJsonFile`. A half-written
`notes.json` turns a recoverable problem into lost notes.

**Never let a write failure become a block.** `CorruptDataFile.blocked` exists for
one reason: notes that were never read must not be overwritten. A write that
could not *land* is a busy disk, not unreadable data, and must retry instead.
Conflating the two cost every edit for a whole session once already.

**Test the parts where being wrong loses data.** Atomic writes, concurrent
readers, the corrupt-file refusal, write retry, undo ordering, and the backup
format all have tests, and new behaviour near those needs one too.

**Comment the reasoning, not the statement.** The existing comments explain *why*
a thing is the way it is, usually including what went wrong the first time. A
comment that restates the line below it is noise.

## Pull requests

- Keep one logical change per pull request.
- Add a test that fails without your change. This is the part most likely to be
  asked for in review.
- Say what you verified and how. "Ran the release build and dragged the widget"
  is worth a lot more than "should work".
- Update `CHANGELOG.md` under the version being prepared.

## Releasing

Only a maintainer should cut a release, but it is two commands:

```
# 1. set version: in pubspec.yaml, and rename the CHANGELOG heading to match
git tag v1.2.0
git push origin v1.2.0
```

Pushing the tag triggers `.github/workflows/release.yml`, which checks the tag
against `pubspec.yaml`, runs the tests, builds, launches the staged build to
prove it starts, verifies the ZIP really contains the Flutter engine, compiles the
installer, and publishes both artifacts to the Releases page. If the tag and
`pubspec.yaml` disagree the job fails on purpose.

To produce the same artifacts locally:

```
pwsh -File tool/release/package.ps1
```

They land in `dist/`.

## Licence

MIT. By contributing you agree your work is published under it.