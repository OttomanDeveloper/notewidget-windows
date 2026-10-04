# Widget Pattern — Hit-Testing, Dragging, and Borrowing the Keyboard

`windows/runner/win_notes_window.cpp`, `lib/src/ui/widget/widget_surface.dart`

Companions: `docs/storage_pattern.md` (who may write what this widget reads) and
`docs/testing_pattern.md` (why two bugs here shipped).

---

## 1. Architecture Overview

The widget is a frameless `WS_POPUP` with `WS_EX_LAYERED | WS_EX_NOACTIVATE |
WS_EX_TOOLWINDOW`, layered so DWM can composite acrylic behind it, `NOACTIVATE`
so clicking never steals the caret, and `TOOLWINDOW` so it stays out of the
taskbar and Alt+Tab. It is the only surface with all three.

```
Dart                                         runner
────                                         ──────
onPointerDown  ─┐
onPointerMove   ├─ decide drag vs resize     Widget::HitTest  ── always HTCLIENT
onPointerUp    ─┘                           Window::PostBeginMove
                                            Window::PostBeginResize
                                              └─ SeedLoopAnchor + native move/size loop
widget.setGeometry ────────────────────────► SetWindowPos
```

**Dart decides, the runner performs.** Never the other way round.

---

## 2. Why this document exists

Dragging the widget shipped broken and stayed broken for a while, through two
separate causes that had nothing to do with each other:

1. `HitTest` reported `HTCAPTION` for the body, and Windows never consulted it.
2. Even when it did, `DefWindowProc` refused to start the loop.

Then, once dragging worked, it landed the widget at about **40% of the distance
asked for**, on every drag, on every machine.

Then the composer could not be typed into at all, because of a window style
that had been there from the first commit and had never been questioned.

---

## 3. The rules

### 3.1 The widget is `HTCLIENT` everywhere

```cpp
LRESULT Window::HitTest(POINT screen_pt) const {
  (void)screen_pt;
  return HTCLIENT;
}
```

This is load-bearing, not a simplification. `HTCAPTION` fails for two independent
reasons:

- **The Flutter view covers the client area**, so the system hit-tests the child
  and never asks the frame. Reporting `HTCAPTION` was dead code — the widget
  could not be dragged, and asking the handler directly returned a value that
  never influenced a real click.
- **`DefWindowProc` only starts the move or size loop for a window with
  `WS_CAPTION` or `WS_THICKFRAME`.** This is a borderless `WS_POPUP` with
  neither, so the loop never began even when the hit test said `HTCAPTION`.

And `HTCAPTION` over the body would be actively wrong anyway. The same pixels
have to deliver taps: cards are selectable and a double-click opens the editor.
**Windows hit-tests exactly one target per pixel**, so caption-or-taps is a
choice, and taps are the one worth making.

### 3.2 The drag has to be computed in screen space

Flutter reports pointer positions **relative to the view**. Once the window
starts following the cursor, the window moves *under* the pointer, so the
reported delta shrinks by exactly the amount the window moved. A window asked to
travel 100 px lands about 40 px away — and the error is proportional, so no
constant fudge factor fixes it.

Dart cannot recover the screen-space pointer position; it does not exist there.
So Dart detects the gesture and calls `widget.beginMove`, and the runner reads
`GetCursorPos` itself.

Past the hand-off Dart stays out of the way entirely: `_gesture.handedOff()`
makes every later move a no-op, because Flutter's coordinates are no longer
meaningful.

### 3.3 The anchor travels with the hand-off

```dart
unawaited(widget.controller.beginMove(gesture.anchor));
```

The runner is told only **after** the pointer has already travelled past the
threshold. Seeding the native loop's start cursor from `GetCursorPos` at that
moment discards everything moved in the first hop — the window would jump
backwards by the threshold distance before following.

So `SeedLoopAnchor()` reconstructs the anchor from the window rect plus the
view-relative anchor Dart captured at pointer-down, scaled by the monitor DPI:

```cpp
loop_start_cursor_.x = r.left + lround(pending_anchor_x_ * scale);
```

### 3.4 Scroll-versus-drag is decided by scroll extent, not by notification

```dart
bool _listCanScroll(double dy) {
  if (!_scroll.hasClients) return false;
  final position = _scroll.position;
  const slack = 0.5;
  if (dy < 0) return position.pixels < position.maxScrollExtent - slack;
  if (dy > 0) return position.pixels > position.minScrollExtent + slack;
  return false;
}
```

Deciding "has a scroll started yet" is a race: the first move past the threshold
often arrives before Flutter has delivered `ScrollStartNotification`, and **a
list with nothing left to scroll never delivers one at all** — which is exactly
the case where moving the window is the right answer.

Direction matters and is easy to get backwards. Dragging **up** pushes the
offset *up*, towards the end of the list. Getting that backwards hands every
upward drag to the window, which is the direction people most often use to
scroll.

Half a pixel of slack, so a list already at its end does not go on claiming the
gesture over a rounding error.

### 3.5 The grab band is 14 logical px, and resizing is never locked

`_grabBand = (14 / scale).clamp(8.0, 24.0)` — divided by the monitor scale so
the band is the same physical width on a 4K display as on a 1080p one.

`_edgeUnder` maps the pointer to one of nine edges. **Resizing ignores the
position lock entirely.** The lock is about position; a corner drag is a
deliberate act, not an accidental one, and locking it would be surprising in the
other direction.

### 3.6 The position lock is off by default and explains itself

A locked widget that silently ignores a drag is indistinguishable from a broken
one. So after someone *actually tries* to drag a locked widget, a hint appears
for 2.6 s that names where to change it — "locked" alone leaves the next
question unanswered.

The timer is a cancellable `Timer`, not `Future.delayed`: a pending delay
outlives `dispose` and fails a widget test outright.

### 3.7 `WS_EX_NOACTIVATE` is borrowed for exactly as long as composing needs it

The widget is `NOACTIVATE` so clicking it never pulls the caret out of whatever
you are typing into. **That is also, and not incidentally, why it could never
contain a text field.**

```cpp
if (active) {
  compose_previous_focus_ = GetForegroundWindow();
  ex &= ~WS_EX_NOACTIVATE;
  SetWindowLongPtrW(window_, GWL_EXSTYLE, ex);
  SetWindowPos(...);           // an ex-style is not live until told to recalc
  SetForegroundWindow(window_);
  return;
}
ex |= WS_EX_NOACTIVATE;
...
if (previous && IsWindow(previous) && GetForegroundWindow() == window_) {
  SetForegroundWindow(previous);   // only if it is still ours
}
```

Three details are load-bearing:

1. **The previous foreground window is remembered**, not "whatever is foreground
   when we close". An always-on-top widget that takes the caret and never gives
   it back is the most irritating thing a desktop widget can do — and the person
   who just typed a note is usually in the middle of something else.
2. **Focus is handed back only if the widget still has it.** If the user
   alt-tabbed somewhere deliberate, yanking them back would be worse than leaving
   them where they chose to be.
3. **`WM_MOUSEACTIVATE` has to stop refusing activation too.** It returns
   `MA_NOACTIVATE` as belt-and-braces with the ex-style, which would otherwise
   block activation at the exact moment the widget is meant to be a text field.
   Same bug, one layer down, and much harder to see.

Nothing here is permanent, because nothing permanent would be acceptable: a
widget that could hold the caret would be unusable, and one that could never take
it could not be typed into.

### 3.8 Move and resize are off while the composer is open

`_onPointerDown` returns early when `_composing`. The grab band runs along the
very bottom of the widget, which is exactly where the field sits — so without
this a click near the field's edge resizes the window instead of placing the
caret.

### 3.9 One slot that changes, faint rather than absent

The add-a-note affordance is a circle in the bottom-right that becomes a field
in the same spot. Not a button that reveals a panel elsewhere: what you click is
what appears where you clicked, so there is nothing to hunt for.

It sits at **0.28 opacity until you hover**. A control that only exists on hover
is one half the people who could use it will never find; an always-visible field
costs 36 px of a 420 px window and reads as something the widget wants from you.
That trade is the requirement, made explicit rather than accidental.

**`SizedBox` goes outside `Material`.** A `Material` with a clip shape expands to
fill whatever constraints it is given, so the circle silently became the full
width of the widget and swallowed taps meant for the cards above it.

Both controls are **keyed** (`addNoteButtonKey`, `addNoteFieldKey`). The
`Semantics` label and the `Tooltip` both answer to "Add a note", so a
label-based finder is ambiguous about which box it means — and the ambiguity is
invisible until the tap misses.

### 3.10 One line of typing becomes a title

First line → title, rest → body. That is the shape the widget already displays
(a line, then a preview), so a note jotted on the desktop looks like one written
in the editor.

It lands at the top of the list, being the most recent thing in it, but it does
**not** steal the editor's selection. You are looking at the widget; moving the
editor's cursor out from under you is the worse surprise.

### 3.11 The big card prefers unfinished notes; the display is otherwise fixed

```dart
final roomy = constraints.maxHeight >= 240 && constraints.maxWidth >= 200;
final renderLarge = focused && roomy;
```

One note gets the large treatment, everything else gets a compact one-liner.
`focusedNote` prefers the most recent **unfinished** note, so the big card is
never a struck-through task; an explicit selection still wins; when everything is
finished it falls back to the most recent.

**"No text yet" is reserved for a note with nothing in it at all.** A note with a
title and no body has its content on the line above, so claiming otherwise is
wrong — and it is the shape every note added from the composer takes.

### 3.12 The widget hides when nothing has text

`_widgetVisible = hasAnyNoteWithText`. A widget showing an empty list is noise on
a desktop; the editor is one hotkey away.

**Known consequence:** with zero notes-with-text there is no widget, and therefore
no way to add the first note from the widget. Deliberate, and it interacts with
the unrooted first-launch bug in `AGENTS.md` §4.

### 3.13 Sizes are clamped in the runner

`200 × 140` logical minimum, `4000 × 4000` maximum, applied to the result of
every geometry change so a resize gesture cannot produce a window too small to
read or to find.

---

## 4. The traps

- **Do not reintroduce `HTCAPTION`.** It fails twice (§3.1) and it would break
  card taps even if it worked.
- **Do not compute a drag in Dart.** 40% of the distance, every time (§3.2).
- **Do not seed the native loop from `GetCursorPos`.** Discards the first hop
  (§3.3).
- **Do not decide scroll-versus-drag on `ScrollStartNotification`.** It is a
  race, and the important case never sends one (§3.4).
- **Do not invert the scroll direction test.** Upward drags are the common case
  and they are the ones that break.
- **Do not put `WS_EX_NOACTIVATE` back permanently.** It would mean no text field,
  ever.
- **Do not remember "current foreground" instead of "previous foreground"** when
  handing focus back.
- **Do not let `Material` size the add-note circle.**
- **`Forwarding raw keystrokes to a `TextField` on a `NOACTIVATE` window cannot
  work.** Do not try to solve it in the runner; borrow the keyboard (§3.7).

---

## 5. Adding work

- **A new gesture** → decide it in Dart from the pointer the widget already
  receives; perform it in the runner from `GetCursorPos`. Pass the *anchor*.
- **A new window style that affects activation** → check `WM_MOUSEACTIVATE` in
  the same change. There are two guards and they have to agree.
- **A new edge or corner** → `kWmBeginResize`'s edge constants, plus
  `_edgeUnder`, plus the runner's clamp.
- **A new floating control** → key it, put `SizedBox` outside `Material`, and
  check whether it lands in the grab band.

---

## 6. Layer isolation

`ui/` reaches the runner **only** through `ShellChannel`; no file in `ui/` or
`state/` constructs a `MethodChannel`. Verified mechanically — see
`AGENTS.md` §5.

---

## 7. Tests

| Rule | Pinned by |
|---|---|
| The composer is absent until asked for | `widget_integration_test` → *the field is not there until you ask for it* |
| Borrowing and returning the keyboard | `widget_integration_test` → *opening it asks the runner for the keyboard, closing gives it back* |
| Routing the write | `widget_integration_test` → *a jotted line becomes a note, routed to the editor*, *with no editor, the widget writes the note itself* |
| Empty input makes no note | `widget_integration_test` → *saving nothing just closes it* |
| No drag while composing | `widget_integration_test` → *the widget cannot be dragged while composing* |
| Completion from the widget | `widget_integration_test` → the *marking a task finished from the widget* group |
| Big card skips finished notes | `notes_controller_test` → *the big card skips finished notes*, *with everything finished the big card falls back*, *an explicit selection still wins* |
| Completion does not reorder | `notes_controller_test` → *finishing a note does not reorder the list* |
| "No text yet" only when empty | `widget_surface_test` → *says so when a note has nothing in it at all*, *says nothing about the body when there is a title* |
| Card sizing at small sizes | `widget_surface_test` → *a widget too small for a large card* |
| Compact card previews | `widget_surface_test` → *a compact card* |

**Not covered, and cannot be on this host:** §3.1, §3.2, §3.3 and §3.7 are all
Win32 behaviour. See `docs/testing_pattern.md` §2 for what was verified instead
and how.

---

## 8. Guarantees

1. Every pixel of the widget is a click target for the widget's own content.
2. A drag moves the widget exactly as far as the cursor went, on any monitor
   scale, with no jump at the hand-off.
3. Scrolling works while there is more to read; dragging works once there is not.
4. Dragging a locked widget does nothing *and says why*.
5. The widget never takes the keyboard except while composing, and gives it back
   to the window it took it from.
6. Nothing in the bottom 14 px resizes the window while you are typing in it.
7. One card is large and readable; the rest are scannable.
8. The big card is never a struck-through task.