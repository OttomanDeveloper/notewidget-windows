# Reporting an issue

Bug reports are welcome and genuinely useful here. This project has no telemetry
and no crash reporting, so a report is the only way I find out something is
broken — and the more precisely it is written, the sooner it gets fixed.

## Before you report

A few things that change what happens next:

- **Check the [open issues](https://github.com/OttomanDeveloper/notewidget-windows/issues).**
  It may already be known, and someone may have a workaround for it.
- **Try the latest release.** If you are on a build from a fork or from source,
  the problem may already be fixed.
- **Try it with a fresh profile.** Close WinNotes, rename
  `%APPDATA%\WinNotes` to `WinNotes.old`, and launch again. This tells us
  whether it is a data problem or a code problem, and it is the single most
  useful thing you can do before filing. Rename the folder back afterwards if
  the fresh one behaves — your notes are in there.

## Open an issue

Use the **Report a bug** link at the top of the
[issues page](https://github.com/OttomanDeveloper/notewidget-windows/issues/new).
The form asks for the things that matter:

### What to include

**What you did, and what you expected instead.** "Typing in the editor did
nothing" is far easier to act on than "it is broken".

**The version.** The form asks for it. It is the version in Settings → About, or
in the file properties of `win_notes.exe`. Without it a report cannot be matched
to a build.

**Your Windows version.** Windows 11 Pro is the target, but the widget leans on
Windows behaviours that differ between 1809, 21H2 and 24H2.

**Whether it involves notes.json.** If the widget showed the "these notes could
not be read" screen, say so — that is a specific and serious failure mode and it
should be reported every time.

### How to include your notes file

`%APPDATA%\WinNotes\notes.json` is plain JSON and safe to paste into an issue
**after you have removed anything you would not want published**. It is the
single most useful thing in a bug report, because it reproduces the exact state
the app was in.

If it will not read, `settings.json` and `widget_state.json` are equally
readable and often just as telling.

Never paste anything you did not mean to publish. This project has no account
system and no server, so an issue is public the moment you press submit.

### What not to include

- Screenshots of the whole desktop. They usually contain other people's window
  titles. Crop to the widget or the editor.
- Anything from a path that names a customer or a machine.

## What happens next

There is no service-level promise, and pretending otherwise would be dishonest.
What is true:

- Real bugs get looked at and usually get fixed.
- If something is not going to be fixed, the issue is usually closed with a
  reason rather than left to rot.
- Feature requests are welcome as issues, labelled as such.

## Security problems

Do **not** open a public issue for a vulnerability. Use
[GitHub's private vulnerability reporting](https://github.com/OttomanDeveloper/notewidget-windows/security/advisories/new)
instead, so a fix can be prepared before it becomes public.

## Contributing a fix

See [CONTRIBUTING.md](CONTRIBUTING.md). In short:

```
git clone https://github.com/OttomanDeveloper/notewidget-windows.git
cd notewidget-windows
flutter pub get
flutter test          # must be green before you start
```

Then fix it, add a test that fails without your change, and open a pull request.
CI runs the analyzer, the tests and a real Windows build on every push.