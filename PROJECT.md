# NoteWidget

## What it is not

- It is not a notes app with an account. No sign-up, no email, no password, no server, no cloud, and no sync. Everything lives on this one PC and nowhere else.
- It is not Sticky Notes with extra steps. Microsoft Sticky Notes already exists, is free, and is good. What it cannot do is the two things that made this get built: it vanishes when you close it, and it never comes back on its own after a reboot.
- It is not a to-do app. No due dates, no reminders, no recurring tasks, no priorities, no subtasks, no projects.
- It is not a notebook. No folder tree, no tags, no backlinks, no graph view, no formatting toolbar. A note is text, and the text is the note; Markdown is a way of writing that text, not a document format the app owns.
- It is not a knowledge base. Search reaches the notes in this app and stops there. It never looks outside them, never indexes the disk, and never becomes a search-everything launcher.
- It is not a Windows widget in the Android sense. Third-party widgets on the Win+W board do exist, but only for MSIX-packaged apps that declare widget capabilities, which is a different distribution model entirely. What gets built here is an always-on-top overlay window that behaves like a widget. It does not appear on the widgets board.
- It does not bake itself into the wallpaper. Rendering the text onto the desktop background image would let the app exit completely and still leave marks behind, but it would also make every note unclickable and uneditable until the app came back. Notes that stay alive are worth more than notes that survive a true exit.
- It does not touch the wallpaper, the desktop icons, or any Explorer folder. It never rearranges anything the user can see on their desktop.
- It does not annotate the screen. No drawing, no arrows, no highlighting, no screenshot markup, no screen recording.
- It does not watch the clipboard. Text enters a note because the user pasted it there, never in the background and never automatically.
- It does not touch the internet at all. No telemetry, no analytics, no update check, no crash upload. The app has no network code, which also means it has nobody to send data to and nobody to call for help.
- It is not for sharing. No account, no link sharing, no co-editing, no export meant for someone else to open.
- It targets Windows 11 Pro and nothing else. macOS, Linux, Android, and iOS are outside the scope entirely.

## What it is

- It's a desktop notes widget for Windows 11 Pro: notes that stay on the screen and come back by themselves every time the PC boots.
- It fills the one gap between Microsoft Sticky Notes and an Android widget. Sticky Notes is a genuinely good app trapped inside an ordinary window, so it gets covered, gets closed, and never returns on its own. On a phone, notes live on the home screen and survive everything. NoteWidget is that same idea, built for Windows.
- It is a two-surface app. One surface is the widget: a frameless note floating on the desktop, always visible. The other is the editor, which shows up only when the user asks for it. Neither is more real than the other; they are two views of the same notes.
- It is built with Flutter for Windows, because Flutter is already installed on the target machine and it is the language the user works in.

## Getting started

- Install it and run it once. There is no account step, no login screen, no onboarding tour, and nothing that asks for anything before the user has written a word.
- The first launch opens the editor with an empty note already focused, so typing is the very first thing that happens.
- As soon as one note has text in it, the widget appears on the desktop at an edge, framed and draggable. An empty widget is never shown, since there would be nothing to look at.
- The editor and the widget can be closed and reopened in any order, as often as the user likes. Neither one ever holds unsaved work, because there is no save step to miss.
- Launching from the Start menu always opens the editor, since that is what a person clicking an icon means to do. Launched any other way, the app can go straight to the widget instead (see Startup and the widget reappearing).
- Quitting is explicit and lives only in the tray menu. Closing a window never ends the app, and that is the entire point of the thing.

## Local-only, export, exit

- Every note is a plain-text file on this PC. There is no remote copy to fall back on and no second device, so the notes are exactly as durable as the profile folder holding them.
- Notes are written the moment they change, not on a timer and not on quit. Killing the app mid-sentence loses nothing, because there was never a pending write.
- Notes can be exported as plain text for backup, and imported back. The format is deliberately boring, so a backup taken years from now can still be read without this app.
- Exit is always deliberate. Closing the last window leaves the widget running on the desktop; the app only ends when the user chooses Quit from the tray, where it asks first so it can never be lost to a stray click.
- Losing notes is possible in exactly one way, which is deleting the app's data folder by hand, the same as any local app. Nothing in the app itself destroys a note without being asked to.

---

Now each feature with a little more detail.

## Notes

- A note is a title, a body, and nothing else. No tags, no colour, no pin flag, no folder, no created or edited stamp shown anywhere.
- The title is a separate line from the body because the widget only has room to show one of them, and which one matters changes with how much is written.
- Notes sort by the most recently edited, always, with no sorting options to get wrong.
- Search matches both title and body, and the note list filters as the user types. There is no search history and no saved query.
- A note with an empty body still exists and still counts as a note. Deleting the last character of a body is not the same as deleting the note.
- Deleting a note asks for confirmation, every time, because the widget is a place people forget things exist. There is no Recently Deleted and no trash, but there is a short undo window afterwards.
- Undo is time-boxed at a few seconds and is never persisted. It puts the note back in its original position in the most-recently-edited order, not at the top of the list. Only one deletion is undoable at a time, because holding two would make the undo control ambiguous. A second deletion replaces the first rather than queueing behind it.
- A note deleted while the widget is on screen disappears from it immediately, rather than lingering until a refresh.

## The widget

- The widget is a frameless, transparent window sitting on top of the desktop. It has no title bar, no border, and no taskbar button, so nothing about it looks like a window unless the user is deliberately dragging it.
- The widget shows every note in one scrolling column, not just one. The note that is selected in the editor, or the most recent one if nothing is picked, is the focused card and is rendered large; every other note is a compact card above or below it. This is the answer to the question about mixed note sizes: there is exactly one large card and every other card is small, so sizes never have to be reconciled. Clicking a card focuses it.
- If the widget is too small for the large card to show anything readable, every card renders compact. The decision comes from the window's own size rather than from scroll metrics, which cannot be read while a sliver is being laid out.
- An empty widget is never shown. Once the last note with text is deleted, the widget hides itself rather than leaving a blank card on the desktop.
- It is always visible. That is the whole feature, so it holds its position above ordinary windows rather than getting buried behind whatever is in front of it.
- It never takes focus on its own. Clicking it while typing in another program does not steal the caret away mid-sentence, which is what makes it usable as a permanent fixture.
- The user drags it anywhere, and it stays where it is left, across restarts.
- By default it docks to whichever screen edge is nearest, sitting flush against it with a small margin rather than floating loose in the middle of the display.
- It can be resized from any corner by dragging, down to a size that still shows something useful, and up to most of the screen.
- The widget shows whichever note is selected, or the most recent one if nothing is picked. Switching the visible note never changes position or size.
- Closing the editor hands focus back to the widget rather than leaving a gap on screen where something used to be.

## The editor

- The editor is an ordinary window, with an ordinary title bar, because it is the one surface the user is deliberately looking at.
- It lists notes on one side and shows the selected note on the other. On a small screen the two swap, with the list reachable by going back rather than always on screen.
- Editing is a plain text field with no toolbar and no formatting buttons, because the source has to stay what was typed and a toolbar is the fastest way to stop that being true. Markdown is opt-in per note, and when it is on the editor shows the source and a rendered preview side by side, or one at a time when the window is too narrow for both. It is never on by default, so an existing note does not start rendering differently the day the app updated.
- The list of notes renders each note's Markdown too — the title inline, and the preview as Markdown rather than as its syntax — so a row reads the way the note looks rather than the way it was typed. A row is two lines in a 300px column, so its preview keeps the structure that fits and drops the rest, with the edge faded to say there is more.
- The widget renders the same Markdown, with a deliberate subset: real inline formatting, compressed block structure, and tables flattened to one line per row. A card is glanced at from across a desk; making it attempt a heading tree produces something worse than prose, and the whole point of a shared renderer is that the widget, the list and the preview cannot disagree about what a note says.
- Neither surface can follow a link. The app does not touch the internet at all, and a link drawn as if it could be tapped would be a promise the product does not keep.
- A `- [x]` in a Markdown body draws a box and does nothing when clicked. Finishing a note is per note — the circle, and `Ctrl+D` — while a Markdown task list is per line, and two answers to "is this done" is worse than one that only looks like the other.
- There is no save button. The body is written as it is typed, so leaving the note, closing the window, and quitting all leave the same text behind.
- Exiting the editor is the ✕ in its title bar, which returns to the widget rather than closing the app.
- The editor never appears on its own at boot. Boot brings back the widget, never a full window the user has to dismiss, because the widget is the state worth restoring and the editor is the state worth asking for.
- The editor has a minimum size and cannot be dragged below it. It is free to grow to most of the screen, and it maximises like any ordinary window, but it cannot be shrunk to a sliver and left there — a window too small to show a title, a note and a status bar is not a smaller version of this app, it is a broken one. The floor is 520×360, chosen from the layout rather than rounded off: below 760 the editor shows one pane at a time, and that pane stops fitting much under 400 wide.

## Startup and the widget reappearing

- The widget comes back by itself after every restart, which is the single behaviour the app exists to provide.
- This is done with one entry under the per-user Run key in the registry, so it needs no administrator rights and does not run for other accounts on the same machine.
- That entry also shows up in Task Manager under Startup, where the user can disable it the same way they would any other app, without editing the registry by hand.
- The startup entry launches the app with a widget flag, and the app reads it by starting straight into the widget. Without that flag, every boot would open the full editor instead, which is not what anyone wants at 9am.
- The autostart entry points at the installed copy in the user's local programs folder, not at wherever the project happened to be built from, so moving or deleting the source tree never breaks the widget coming back.
- If the autostart entry points at a file that is no longer there, the app simply does not run, and nothing else breaks. A missing entry is a silent no-op rather than an error the user has to clear.
- Turning autostart off is a toggle inside the app, and turning it off removes the registry entry rather than leaving it disabled somewhere.

## Quit, tray, and hotkeys

- The tray icon is the app's real home, since the widget has no chrome of its own and the editor is not always open.
- The tray menu carries the three things worth reaching for: show or hide the widget, open the editor, and quit.
- Quit is the only path that ends the app, and it asks for confirmation.
- A global hotkey, Ctrl+Alt+N by default, opens the editor from any application, including full-screen ones. It is registered once at startup, and if another app has already claimed that combination, the app notices rather than silently doing nothing.
- The hotkey is changeable inside Settings, and reverting to the default is a single action rather than typing the combination in by hand.
- The widget can be hidden and brought back from the tray without quitting, for when the user wants the screen clear.

## Position and monitors

- The widget remembers which monitor it was left on and returns there after every restart, rather than jumping to whatever Windows considers primary.
- Moving a monitor, or unplugging the one holding the widget, puts it back on the nearest remaining screen instead of leaving it off-screen where it can never be clicked again.
- A monitor arrangement change is handled the same way, so the widget survives docking and undocking a laptop without becoming unreachable.
- The widget never covers itself with another instance. Launching the app when it is already running raises the existing widget rather than stacking a second copy on top.

## Settings

- Settings covers appearance, startup, hotkey, and the storage location, in four flat groups with no nesting.
- Appearance covers theme and the widget's own opacity, since a widget that is too solid sits on top of the work rather than beside it.
- Startup holds the autostart toggle and a short delay, so the widget can wait for the desktop to settle before appearing instead of racing the login animation.
- The delay applies to autostart only. Launching the app by hand always shows the widget immediately.
- Settings is reachable from the tray menu as well as the editor, because the editor might not be open at the moment a setting is wanted.

## Storage

- Notes are kept as one JSON file in the user's application data folder, rather than a database. The whole point is that a person can find the file, read it, back it up, or delete it without this app in the way.
- The file is written as a whole rather than appended to, so a half-finished write can never leave the notes in a broken state.
- Writes are debounced by a fraction of a second, so holding down a key does not hammer the disk once per character, while a note still survives being killed a moment after typing stops.
- If the file is unreadable or not valid JSON, the app refuses to start rather than replacing it with an empty one. Overwriting notes that were never read is the one failure it will not risk, and it says so rather than showing an empty list.
- That unreadable file is also offered as an import target later, so a backup can be restored by hand without the app having to parse it first.

## Theme

- Theme follows Windows, with Light, Dark, and System available in the app itself for the case where they disagree.
- The default choice is System, so the widget matches whatever Windows is already doing.
- Acrylic is used as the backdrop behind the widget, so it picks up the wallpaper and taskbar the way native Windows 11 surfaces do, instead of sitting there as a flat grey rectangle.
- Where Windows cannot provide it, the widget falls back to a plain translucent surface rather than failing to draw.
- Reduced motion is respected when Windows reports it, so nothing slides or fades for a user who has asked Windows not to animate anything.

---

## Later

Ideas not yet built. Once one is built, it moves into the section that owns it.

- **Multiple widgets at once:** more than one note pinned to the desktop, each with its own position and size, for people who keep separate lists for separate purposes. The window handling already supports this; the missing part is deciding which note belongs to which widget.
- **Desktop layer mode:** using SetParent against the desktop window so the widget sits behind every application but above the wallpaper, permanently visible without ever covering work. Roughly twenty lines of interop, held back because it interacts with Explorer in ways that need testing across builds rather than an assumption.
- **Search from the widget itself:** opening the editor from the hotkey with the cursor already in the search box, for a note that needs finding without opening the editor first.
- **Note pinning:** protecting a note from the most-recently-edited ordering, so a standing note stays where it is in the list while other notes move around it.
- **Export as Markdown** with the title as a heading, for people who want their notes to end up somewhere else eventually. Less interesting than it was: a note already written in Markdown exports as Markdown by being plain text, so this is now only worth building for the heading and a wrapper.
- **Per-note widget text size and colour,** so a note meant to be read from across a desk can be much larger than one meant to be read while typing.

## Decisions Pending

- **Encryption at rest:** not included. Notes sit in the user's own profile folder, which Windows already protects with the account password, so a second encryption layer would add a key to store, back up, and lose. The cost is that anyone who can read the profile folder can read the notes in plain text. If notes are expected to hold genuinely sensitive material, this becomes the first thing to build and it should be built properly rather than bolted on.
- **Deleting a note with no undo:** included above as confirmation and nothing more. A widget is somewhere people leave things without thinking, so some notes will be deleted by accident. A Recently Deleted list would fight the plainness the app is built around, but the alternative is genuinely unrecoverable, so it is worth deciding on purpose rather than by default.
- **One widget showing one note, or all of them:** resolved in favour of showing all of them, with one focused card rendered large and the rest compact. Showing every note means the widget is useful without opening the editor at all, which is the whole premise; the cost is that the widget cannot be shrunk to nothing, because a list of notes needs somewhere to put them. The mixed-size problem is solved by there being exactly one large card, so there is never a case where two notes compete for different sizes.
- **Plain text only, or Markdown with a preview:** reversed by the owner on 2026-10-04, and Markdown is now in. It was originally resolved as plain text only, on the reasoning that "a Markdown editor would leave the widget still guessing how to render it" — and that reasoning was right about the problem and wrong about the size of the answer. The widget does not have to guess if it is given a renderer with a stated budget: inline formatting is rendered honestly, block structure is compressed, tables become their text. The objection was answered by making the widget's rendering a deliberate subset rather than by refusing the feature, which is why the same renderer serves both surfaces and they cannot drift apart. Two things changed in the product to allow it. The decision is now per note rather than global, because a to-do list and a formatted note sitting side by side in one library is the normal case and neither should be forced to be the other. And one dependency was admitted — a CommonMark parser — because parsing to a standard is not the thing worth hand-writing; the presentation is, and that stayed in this repo.
- **Deleting a note with no undo:** resolved as confirmation plus a short undo window rather than either extreme. No trash, because a Recently Deleted list would fight the plainness the app is built around, but also no permanent unrecoverability, because a widget is exactly where people leave things without thinking.
- **Desktop layer versus always on top:** always on top is included, because a note the user cannot see is not a note. The desktop layer is listed under Later. A middle option, staying above other windows but below full-screen apps, may well turn out to be the better default, and it has not been tested against how Windows handles full-screen games.
- **Single instance behaviour:** included above as raising the existing widget. Launching a second copy with its own notes was considered and rejected, since two apps writing the same file would eventually lose one set of changes, and a second widget showing stale notes would be worse than no second widget.
- **Whether the widget should remember a per-monitor position or a single position:** per-monitor is included, since a widget that returns to the same screen after a reboot is the behaviour that makes it feel like a fixture. A single saved position across all monitors is simpler and less surprising when monitors come and go. Worth confirming which one people actually want before it hardens.

## Built

The design above is implemented. `README.md` covers how to run it and where the files live; `CHANGELOG.md` lists what shipped.

Two structural decisions were made while building that the notes above do not spell out, because they are consequences rather than choices:

- **Each surface is its own Flutter isolate, and they share state through files.** One writer per file: the editor writes `notes.json` and `settings.json`, the widget writes `widget_state.json`, and `selection.json` is the only one either side touches. This removes the need for any cross-isolate merge logic, which is where multi-window Flutter apps usually get complicated, and it means the widget cannot ever disagree with the editor about a note.
- **The native layer owns every Windows-specific behaviour directly, with no third-party packages.** Frameless layered windows, the acrylic backdrop, the tray icon, the global hotkey, the registry entry and single-instance handling are all written against Win32 in `windows/runner/`, rather than assembled from window-management plugins. The cost is more code in the runner; the benefit is that behaviours like "a hotkey collision is reported rather than silently ignored" are verifiable by reading the code instead of by trusting a dependency.