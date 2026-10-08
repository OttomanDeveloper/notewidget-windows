# Widget Pattern — Hit-Testing, Dragging, and Borrowing the Keyboard

`windows/runner/win_notes_window.cpp`, `lib/features/widget/presentation/screens/widget_surface/widget_surface.dart`

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

### 3.14 One renderer, a budget per surface

`lib/core/widgets/markdown_text/markdown_text.dart` renders Markdown for **every surface
that shows note text**, and what differs between them is only a budget:

| Surface | Density | Body | Budget | Headings |
|---|---|---|---|---|
| Widget card | `widget` | 13px | 2 lines compact, 7 large | flattened |
| Editor list row preview | `widget` + `fontSize` | the row's `bodySmall` | 2 lines | flattened |
| Editor preview pane | `editor` | 14.5px | unbounded | full scale |

The list row is the reason a row is not a smaller widget card: it is 12px
`bodySmall` in a 300px column, not 13px. `fontSize` therefore scales the whole
metric set — ratios kept, pixel values multiplied — rather than overriding one
number and inheriting the wrong gaps.

This is the whole answer to the objection that ended "no Markdown" — *a Markdown
editor would leave the widget still guessing how to render it*. It does not guess
because it is not a different code path with a different implementation. It is
the same walk of the same AST with a smaller budget, which means no two surfaces
can disagree about what a note says, and a change to what counts as supported
lands on all of them at once.

At widget density the renderer compresses rather than omits: code blocks clamp to
three lines and say how many were hidden, and a table becomes one line per row
with its cells still separated by `|`. A grid in a 360 px card is a grid of
unreadable sliders, but flattening it with `textContent` would give
`SurfaceDensityWidgetcompressed`, which is less than the note said — and "never
less than what it says" (§3.15) is the rule the grid loses to.

**One thing is not a density.** The compact card and the large card share
`MarkdownDensity.widget` and differ in budget, so `headingScale` is a parameter
rather than part of the density. A card shows the note's title directly above the
body, so a body opening with `# Release` is repeating itself; at 1.3× that repeat
consumed a third of the compact card's two lines and pushed the content off the
end. The compact card therefore asks for 1.0 — bold, same size, one line, and the
line it costs is a line of content. The large card keeps the real scale, because
it has seven lines and is the surface you actually read a note on.

Density is about the room available, not a belief that headings are unimportant.
Both halves are pinned, because "headings are big everywhere" and "headings are
flat everywhere" are equally wrong.

**A row gets blocks, not just spans.** Rendering the row's preview inline-only
would concatenate a task list's items with no marker at all — `Buy milkPost the
thing` — which is *less* than the note said, the same failure the table flatten
had (§3.15). Two lines at 12px is enough for two items of a list, so the row
renders structure and clamps it.

**"Two lines" means two lines you can read.** `MarkdownText.budgetForLines` adds
the fade band to the requested lines rather than taking it out of them. Sizing the
box at exactly two lines and fading its bottom 55% instead leaves the second line
inside the fade and unreadable, which looks like the renderer lost a line rather
than like a clamp. Verified on a release build at 4× zoom.

The parse is memoised on the source string, 48 entries deep. The widget list
re-renders on every scroll tick and the preview on every keystroke, so parsing
per card per frame is work with no result; the bound is there because an editing
session touches many distinct bodies and a cache that only grows is a leak
wearing a library's clothes.

### 3.15 A rendered note is never less than what it says

Anything the renderer does not recognise degrades to its **text content**. It
does not drop the node and it does not throw. A note must never render as less
than was typed, because a renderer that silently loses content is worse than one
that renders syntax literally — you can see `**`, you cannot see a paragraph
that vanished.

Two specific refusals, both deliberate:

- **Links are styled but not clickable.** `PROJECT.md` says the app does not
  touch the internet at all. A widget with nowhere to send someone has no
  business drawing something that looks tappable, and the href stays in the
  source, so nothing is lost.
- **A `- [x]` draws a box and does nothing when clicked.** Completion is per
  *note* — the circle, and `Ctrl+D` — while a Markdown task list is per *line*,
  and two answers to "is this done" is worse than one that only looks like the
  other.

Raw HTML is text. `encodeHtml: false` keeps `<b>` and `<script>` as the
characters they are, so a note cannot try to be markup.

`<br>` is the one exception, and it is a formatting tag rather than markup:
`a<br>b` is drawn as two lines rather than printing the tag. It is handled in
the **text** arm, not as an element, because `encodeHtml: false` hands the
parser's output back as one text node with the tag inside it — so the `br`
element case in `MarkdownSpans` is unreachable and the split has to happen
where the text is.

**Blankness is not `textContent.isEmpty`.** `MarkdownNodes.isBlank` is the one
predicate, and it treats a node holding an `<img>` as non-blank at any depth.
`alt` is an *attribute*, not a text child, so `textContent` of an image-only
paragraph is empty and calling it blank discarded it. That was a real loss, not
a style choice: a paragraph of nothing but `![chart](x.png)` rendered as
nothing at all. It is the rule above, broken in the one direction the rule
exists to prevent.

**An HTML comment is invisible.** `<!-- ... -->` is markup for the reader and
nothing at all for the author, so it is stripped in `MarkdownSpans` rather than
printed. A paragraph holding only a comment is therefore blank, which is why
`MarkdownNodes.isBlank` strips the same way — otherwise it would leave a gap.

**A footnote `<section>` is flattened, not listed.** The parser wraps footnote
definitions in `<section><ol><li><p>`, and rendering that `<ol>` as a list drew
its number *and* the `<sup>` reference, giving `11.1.` for a single footnote.
The `<ol>` is skipped and its items rendered as blocks.

**Two things the parser offers and `gitHubFlavored` omits are on.**
`_ParseCache._extensions` adds `EmojiSyntax` and `AlertBlockSyntax` to the
parser's own `gitHubFlavored` set. Both are implemented in `package:markdown`
and both are absent from that set, so `:tada:` and `> [!NOTE]` rendered as
literal characters until they were named here. The distinction that matters:
this was never a limitation of the parser, it was a list nobody wrote.
`markdown_test` pins both, including that an **unrecognised** `:alias:` stays
literal rather than becoming a gap.

`> [!NOTE]` and its four siblings become `MarkdownAlert`, a callout whose title
is the parser's own `markdown-alert-title`. A plain `>` is still `MarkdownQuote`;
the two are distinguished by the class the parser puts on the `<div>`, and a
raw `<div>` cannot reach the same branch because `encodeHtml: false` makes it
literal text.

**A list item keeps everything after an inline element.** `MarkdownListItem`
splits an item's children into a leading line and the blocks that follow. The
split must treat `strong`/`em`/`del`/`code`/`a`/`img`/`br`/`sup`/`sub` as
*inline*: the parser gives `- **(core)** is standard Markdown` the children
`[<strong>, Text]`, so a rule that treats every element as a block ends the
leading line at the `**` and drops the sentence after it. That is the worst
failure mode in this file — it is invisible, it is data loss, and it looked
like correct rendering because the visible words happened to be the part that
survived.

**What is still literal, and cannot be anything else.** LaTeX and `==highlight==`
have no syntax in `package:markdown` at all — `ColorSwatchSyntax` is
`#RRGGBB`, not `==` — so supporting them means a different parser or a
hand-rolled one, which is a decision rather than a fix. Mermaid is a fenced
code block and correctly shows its source. Raw HTML stays text per the rule
above.

### 3.15a A table too wide for the pane scrolls, it is not squeezed

`MarkdownTable` was a `Row` of `Expanded` cells, which divides the pane evenly
between the columns. That is right for a three-column table and unusable for a
twelve-column one: at 400px each cell got 23px, so `+91 98765 43210` broke into a
vertical stack of digits and one cell measured **418px tall**. The table rendered
2.5x taller than the pane and nothing overflowed, so every content assertion
passed while the table was unreadable — the failure §3.15 is about, arrived at
without losing a character.

Two rules, and the threshold between them is `MarkdownTable.minCellWidth`:

- **Fits** (`columns * minCellWidth <= available`): the old grid. Columns share
  the pane, wrap, and fill it. Unchanged for every table that already worked.
- **Does not fit**: each cell takes its natural width and the table scrolls
  sideways. Cells are `ConstrainedBox(minWidth:)`, never `Expanded`, because
  `Expanded` needs a bounded width and a scroll view hands its child an unbounded
  one.

`LayoutBuilder`, not `MediaQuery.sizeOf`: in a side-by-side editor the preview is
half the window, and the screen width would promise room the table does not have.

Two consequences worth naming. The header rule is a `DecoratedBox` border rather
than a `Divider`, because a `Divider` is unbounded inside a scroll view and
cannot lay out — and a border hugs the table instead of stretching past it. And
`IntrinsicWidth` is the textbook answer here and is banned by
`flutter_rules_guard_test`; the rulebook's own wording is narrower ("in long
lists") than the guard, which is worth knowing before choosing a workaround.

### 3.16 A rendered body is clamped by height, not by line count

`maxLines` bounds the lines inside one `Text`. It says nothing about how many
blocks a note has, so a note of twenty one-line paragraphs sailed straight past
a `maxLines: 2` and overflowed the card by 365 pixels.

The clamp is a height, with the content laid out unbounded inside an
`OverflowBox` and the parent's edge clipping it. A `ConstrainedBox` alone does
not work: the `Column` still reports the overflow even though the paint is
clipped.

The cut is **faded**, not hard-edged. It cannot be made to land on a line
boundary — block gaps and a heading's own padding do not sit on the line grid —
and a half-visible line behind a sharp edge reads as a rendering fault rather
than as "there is more". Content shorter than the box ends above the fade and is
untouched, because the child is top-aligned.

### 3.17 The widget gets out of the editor's way

Always-on-top is **absolute**. A window with `WS_EX_TOPMOST` is above every other
window, full stop, so there is no Z-order position meaning "above other
applications but below the editor". While the widget carries that flag it
simply covers the editor, and no amount of raising the editor will help.

So the widget **leaves the topmost band for as long as the editor is the
foreground window**, and comes back to it the moment the editor stops being
foreground — the user clicking the editor, switching to another application, or
closing it. That is a yield rather than a downgrade of the setting: with the
editor closed, the widget floats exactly as configured, which is the premise the
whole product rests on.

**Both halves are required, and the second one is not guessable.** Measured on a
release build rather than read out of the documentation:

| Action | editor z | widget z | result |
|---|---|---|---|
| widget topmost (before this rule) | 5 | 0 | widget covers the editor |
| `HWND_NOTOPMOST` alone | 5 | **2** | still above the editor — *worse*: covers it **and** buries it |
| `HWND_NOTOPMOST` + `HWND_TOP` on the editor | **2** | 3 | correct |

`HWND_NOTOPMOST` does not send the widget to the bottom, despite what the
documentation's wording suggests; it drops the widget to the top of the
*ordinary* band, which is still above an ordinary editor. So the editor has to be
brought forward at the same moment, or the fix trades one bug for a worse one.

Also load-bearing: the editor is never given `WS_EX_TOPMOST` at creation
(`StyleForRole`), and `SetAlwaysOnTop` stays widget-only, so the preference
cannot reach the editor by a back door. `Host::ApplyWidgetTopmost` computes the
effective value as `always_on_top_ && !editor_foreground_` and is the only place
that applies it.

**Verified by driving a release build**, because the whole failure is silent: a
topmost widget over an editor looks like a widget over an editor, and there is
nothing to crash. `docs/testing_pattern.md` §2 puts that in tier C, and
`widget_guard_test` covers the part that can be in CI — that the editor is never
topmost, that the setting cannot reach it, that activation is observed, and that
`ApplyWidgetTopmost` raises the editor as well as demoting the widget.

### 3.18 The editor has a minimum size

`WM_GETMINMAXINFO`, setting `ptMinTrackSize` to `520 × 360` logical pixels.
The editor could previously be dragged by a corner down to a few pixels and left
there — a window too small to hold a title, a note and a status bar is not a
smaller version of this app, it is a broken one.

The floor is derived from the layout rather than picked to look tidy.
`EditorView` collapses to one pane at a time below 760 logical px, and that pane
carries the title row, the body and the status bar alone; the status bar — "Saved
to this PC" beside a Delete button — stops fitting much under 400. 520 leaves the
narrow layout genuinely usable rather than technically reachable.

**Editor only.** The widget is `WS_POPUP` and is resized by the drag loop in
`PostBeginResize`, which already clamps against `kMinWidgetW`/`kMaxWidgetW`. A
frameless window does not go through the window manager's track-size path, so a
minimum here would do nothing for it — a second source of truth that reads like
the first.

Three things about the handler that are easy to get wrong and impossible to see:

- **`ptMinTrackSize` is in physical pixels**, so the value is scaled with
  `ScaleForWindow`. A literal `520` is a 520 px floor at 100% and a 347
  *logical* px floor at 150% — so the displays people actually use are the ones
  that get the wrong answer, and nothing looks wrong.
- **`ptMinSize` is the wrong field.** It also caps programmatic sizing, so Dart
  asking for a particular size would be silently ignored.
- **`ptMaxPosition` and `ptMaxSize` are left alone.** `ptMaxPosition` governs how
  far the window may be dragged off-screen, which `ClampToReachableScreen`
  already owns; writing it here is a second, conflicting answer to the same
  question.

**Verified by driving a release build**: dragging the corner past the top-left of
the screen stops at exactly 520×360, each edge clamps independently, and maximise
and restore are unaffected. `docs/testing_pattern.md` §2 puts that in tier C;
`widget_guard_test` covers the four source-level facts that can be in CI.

### 3.19 Widgets do not hold state; they render it

The composition rules live here rather than in `docs/provider_pattern.md` because
they are about widgets. The state rules live there because they are not.

**`setState` is not called anywhere in `lib/`.** Not for shared state, not for
local state, no excuse accepted (`AGENTS.md` §0.7). There were 24 call sites; all
24 are gone and the countdown is deleted rather than kept at zero. The two
replacements:

| The state is | Replacement | What it was |
|---|---|---|
| shared, outlives the widget | a provider | `_busy`, `_ready`, `_settingsOpen`, `_showListOnNarrow`, `_narrowShowsPreview` |
| genuinely ephemeral | `ValueNotifier` **+ a listener** | `_hovering`, `_lockedHint`, `_composing`, `_pending`, `_thumbOpacity` |

The bold on *listener* is the part that is not obvious. A `ValueNotifier` holds a
value and does not rebuild; `setState` did both. Four of these were written without
one during the 2026-10-05 migration and silently did nothing — see
`docs/provider_pattern.md` §3.4 for each. `no_set_state_test` fails on a file that
declares a `ValueNotifier` and contains no listener at all.

The line between the two rows is **lifetime, not importance**. `_hovering` is not
unimportant, but it is true for one frame and nothing else will ever ask. `_busy`
is true for the length of an await, and a button six rows away has to know.

`widget_surface.dart:49` already does this for thumb opacity, so the pattern is in
the tree rather than being imported from somewhere else.

A `State` is not deleted. It stays as the disposal shell for a
`TextEditingController`, a `ScrollController`, a `FocusNode`. What it must not do
is hold a bool a provider could hold — that is `setState` with extra steps, and
the budget is what makes the difference visible rather than a matter of taste.

**No widget below a `ProviderScope` receives a dependency by parameter.** 23
constructor parameters do this by hand today, 13 of them in `settings_dialog.dart`.
A `value` may still cross — an `int index`, a `String path`, a `void Function()`
callback. A controller may not. The rule is about where state comes from, not about
which package is installed, which is why it has teeth before Riverpod is in
`pubspec.yaml`.

**A provider is per-isolate.** `main()` runs in both, so a scope belongs inside
each root — see `docs/isolate_pattern.md` §3.2 for why putting it above the branch
is the trap.

### 3.20 The Markdown switch is labelled, and names what it gets you

The per-note Markdown switch used to be an 18 px circle. It sat in the title row
beside `CompletionToggle`, which is also a circle, and **two bare circles in one
row read as two checkboxes** — which is what it was taken for. The only way to
find out what it did was to hover for a tooltip.

So it is now a pill that says `Preview`: the word names what turning it on gets
you, which is the only reason anyone turns it on. A preview is the thing the user
wants; "Markdown" is the mechanism, and a person who does not know the word
cannot act on it.

Two constraints shaped it, and both are in other documents:

- **No formatting toolbar.** `PROJECT.md` §76 rules one out, because a toolbar is
  the fastest way to stop the source being what was typed. This is one existing
  per-note switch, made legible. Nothing was added.
- **The word does not change with the state.** Fill, border and icon carry it, so
  toggling does not shunt the title sideways as the label grows and shrinks. That
  is a test, not a preference.

**The narrow-layout button is now `Show preview`, not `Preview`.** It is a
different question — show the preview *or* the source, in a pane too narrow for
both — and at 380 px wide both controls are on screen at once. Two controls
answering to one word is one question too many.

### 3.21 The editor's two panes are sized separately, and 0 means "as designed"

The source and the rendered preview are different things — one is what you typed,
monospace, the other is what it means — so they take a size each
(`editorFontSize`, `previewFontSize`). One shared number suits neither.

**A stored 0 is not a size; it means "as designed".** `TextSizes` resolves it, and
resolves it in exactly one place, because "as designed" has two answers for the
source alone: 13.5px monospace in a Markdown note, the theme's `bodyLarge` in a
plain one. A `settings.json` that never mentions the setting therefore needs no
key to keep working — the same reason `accentPalette` is omitted when empty.

Out-of-range values are clamped to 11–24 on load, not trusted: a hand-edited file
should not be able to render a note invisible or fill a pane.

**Ctrl+wheel writes through to the setting**, so the gesture and the slider cannot
disagree and the size survives a restart. The base for a step is the size *on
screen*, not the stored 0, so the first notch starts from what is visible.

The Settings slider is positioned at the resolved size, not the stored one. A
slider parked at the wrong value is worse than none: with nothing chosen it would
sit at the monospace size while a plain note rendered larger, and dragging right
would *shrink* that note.

**Open: the gesture is not yet verified.** The wiring is in `MarkdownBody` — one
`Listener` over both panes, choosing the pane by the pointer's x when wide and by
the flag when narrow. One thing was settled by measurement rather than assumed: an
ancestor `Listener` *does* receive the wheel, even over a `TextField` and over a
scrollable, so nothing downstream is eating the signal. But a widget test driving
Ctrl+wheel through that pane records no step, and the cause is not yet known. The
rules with tests are the stored-value rules below; this one is open.

### 3.22 A saved widget position is restored by telling the runner, not by reading it

`widget_state.json` holds the dragged position, and the widget came back in the
runner's default top-right corner every single boot. The file was never corrupt
and the save was never wrong - measured on the real profile, saved `1086,366`,
window at `1548,12`, and `widget.getBounds` answering correctly throughout.

The cause was one-directional. `_saveGeometry` wrote the position faithfully,
coalesced at 250 ms and all. Nothing ever sent it *back*: the runner places the
window itself in `CreateShellWindow`, and `build` read that placement back
through `widget.getBounds` and copied it over the saved `left`/`top`. The runner
answered truthfully about a position nobody had asked it to change.

**So the fix is to push, not to pull.** If saved `left`/`top` exist,
`widget.setGeometry` sends them before anything reads bounds back; only a first
run - null on both - asks where the runner put the window, because then it is the
only position there is. The method was already in the registry and already handled
in C++, so nothing was one-sided; the Dart side simply never called it.

**No read-back after the move, deliberately.** `widget.setGeometry` is
`PostSetBounds`, which queues onto the platform thread's message pump, so the
`result->Success()` it returns reports having *queued* the message, not having
moved the window. A `widget.getBounds` issued immediately after can be served
before the queued `kWmSetBounds` has run, and hands back the very default the call
was meant to replace - the same bug, one hop earlier. State takes the numbers that
were asked for instead.

**The runner clamps the restore, because a saved monitor may be gone.** A drag is
clamped by `EndLoop` when the pointer comes up; a programmatic move had no
equivalent, so `SetBounds` now calls `ClampToReachableScreen` itself. Without it,
unplugging the monitor a widget was last on and rebooting would restore a position
no monitor can show, leaving the widget unreachable rather than merely misplaced.

The clamp means state can hold a `left`/`top` the window did not settle on. That
costs at most a stale drag anchor; the next drag writes the truth. Size is sent as
saved but is irrelevant - `SetBounds` enforces `kMinWidgetWidth`/`kMinWidgetHeight`
itself, and the widget's dimensions belong to the runner.

### 3.23 The boot-time `Show()` is a default, not an instruction

`Window::Create` defers the boot-time `Show()` to `SetNextFrameCallback`, so the
window is never shown before the engine can paint. The deferral is correct and
stays. What was wrong is that the callback showed the window *unconditionally*.

On a first launch the widget surface builds, decides `visible: false` for an empty
library, and the runner hides the window - all **before** that callback runs. The
callback then showed it anyway. `AGENTS.md` §5.1, open for weeks.

**The whole bug is three lines of trace.** Instrumenting `Show()` and `Hide()` and
launching a release build produced, in order: `Hide(role=0)`, `Show(role=0)`,
`Show(role=1)`. Dart sent the right value every time; the runner hid the window and
then un-hid it.

**A default must not override a decision somebody already made.**
`hidden_before_first_frame_` records that `Hide()` ran, and the callback skips its
`Show()`. It is a member of its own rather than a reuse of `visible_`, because
`visible_` also starts `false` and so cannot tell "never decided" from "decided,
and the answer was hidden" - a mistake made and reverted during the fix.

**No Dart test could have found it.** What is observable from outside is the
window, which is why `WN-ENV-004` is the row and `flutter test` is not.

### 3.24 The split and the drawer are session state, not settings

Two controls that change how the editor looks: a draggable divider between
source and preview, and a note list that collapses to an edge handle. Both are
**session state and nothing else**, and that is a decision rather than an
omission.

They answer "what am I doing right now". A font size is a preference and lives
in `settings.json` (§3.21); a split position set while writing a long note is
the state of that session, and it should not survive it any more than a scroll
position does. So `editorLayoutProvider` holds them, and a provider container
lives exactly as long as the session — the right lifetime already existed.

**It is a separate provider from `settingsProvider`, deliberately.** Folding it
in would mean a drag wrote the settings file, so every frame of a drag would
queue a debounced settings write, and a palette change would rebuild the layout.

**Both measurements are bounded, and the bounds come from the window.**
`PROJECT.md` §87 gives the editor a 520px floor for the same reason: a pane
dragged to nothing is a broken window, not a small one. The source keeps 20–80%
of the body, and the list 200–420px, so the editor always has somewhere to be.

**A drag reports a delta, never a position.** Turning a pointer position into a
pane size needs the parent's left edge, and a `LayoutBuilder` cannot read it
during `build` — its `RenderBox` has no size yet, and `localToGlobal` asserts.
A delta needs no coordinates and survives the pane rebuilding mid-drag.

**Double-click resets**, because it is the one gesture that needs no
instructions, and it moves only the divider: it does not also open the list,
which is a different decision about a different thing.

**The collapsed list leaves a handle, never nothing.** The list is hidden *to
write*, so at that moment the user is looking at the editor and not at the app
bar. A 16px strip with a list icon is both the way back and the reason the
window does not look broken.

---

## 4. The traps

- **Do not write the minimum unscaled.** `ptMinTrackSize` is physical pixels
  (§3.18).

- **Do not give the editor `WS_EX_TOPMOST`.** It is the one window the user is
  deliberately looking at, and adding the flag looks like it would fix "the app
  stays on top" when the app never did (§3.17).
- **Do not demote the widget without raising the editor.** The widget lands above
  the editor anyway, and takes the editor's place in front of it (§3.17).
- **Do not make task-list boxes interactive.** They look like the completion
  circle and they are not it (§3.15).
- **Do not clamp a rendered body with `maxLines`** (§3.16).
- **Do not give the widget its own Markdown path.** Two implementations is one
  too many, and the disagreement between them is invisible until someone
  notices the widget and the editor showing different notes (§3.14).

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

### 3.25 The preview is one laid-out document, and that is deliberate

A note long enough to feel slow - the 1012-line `docs/verification/
`markdown_demo_all_features.md` - was measured at ~261 ms to build and ~20 ms per
scroll frame, growing with the document.

**The first fix was wrong, and the measurements say so.** Rendering blocks lazily
(`ListView.builder` over `MarkdownBlockList.slotsOf`) made a keystroke about 7x
cheaper: 261 ms became 67 ms. It also **broke the preview**. A lazy list of
unknown-height children has no extent to represent, so the scrollbar could not
hold a position: measured on the demo, `maxScrollExtent` swung between 2,278px
and 608,271px across twenty scrolls - a drift of **585,563px** - while a non-lazy
list sat at 24,997px and never moved.

| | extent drift while scrolling | cost per jump |
|---|---|---|
| lazy `ListView.builder` | **585,563 px** | 9-19 ms |
| **one `SingleChildScrollView`** | **0 px** | 14-21 ms |

The frame cost was the same either way, so laziness bought nothing for scrolling
and cost the scrollbar outright. **It was reverted.**

So the preview keeps the whole document in the tree, which is what makes the
extent exact. The cost is a ~261 ms rebuild whenever the 250 ms debounce fires
while typing - not while scrolling, which is why the editor scrolls smoothly and
the lag is a typing-time cost rather than a scrolling one.

**What is left on the table, and why it was not taken.** A lazy list *can* have a
stable extent if every block's height is measured and supplied up front through
`itemExtentBuilder`. That is a real implementation - a render object reporting
each child's size into a cache - and it would give both. It was not done here
because the honest summary is that the visible defect was fixed immediately and
the remaining gain is speculative.

`test/scale_test.dart` pins the invariant that matters: **the scroll extent does
not change while scrolling**, plus that the end of the note is reachable and the
rendered blocks are correct. Structural, not a wall-clock budget - the extent is
the thing that broke and the thing a user notices.
### 3.26 A skin is the shape of a card, and a skin has no colour in it

The shape of a card was hardcoded: `borderRadius: 10` in two places, padding of
16/14 large and 12/8 small, an accent left-bar for the open card, a 2px gap in the
widget and a 1px divider in the editor. A **skin** owns all four.

**A skin carries no colour, and that is the rule worth stating.** The first
version gave a skin a plate, an accent and a source font. Skin and Colour then
did the same job in two controls, which is exactly what was reported: "there is
no difference between the colours and the skin". Colour belongs to
`WinNotesPalette` alone. `skin_test` demands every skin leave the whole
`ColorScheme` identical.

Four things, none of them a colour:

| | |
|---|---|
| `cornerRadius` | 0 square, 10 the built-in, 18 soft |
| `density` | multiplier on a row's padding; 1.0 is what the app always used |
| `focus` | `bar`, `outline`, `fill`, `none` - how the open note is picked out |
| `separator` | `gap` (the widget today), `hairline` (the editor today), `none` |

Four rules, each from a way this could break:

1. **No skin is no skin, never the first one.** `skinById(')` and an unknown id
   are both null, and null means the built-in look. A setting added later must
   not change what an install looks like (§0.5). **No skin in the list is the
   built-in look either** - a chip that repaints nothing is worse than none.
2. **It crosses as a value, like `note` does.** The widget surface draws under a
   bare `ThemeData` for its own colour, so a `ThemeExtension` would have worked
   in the editor and silently vanished in the widget.
3. **The bar cannot be a `Border`.** A `Border` with one coloured side cannot
   carry a `borderRadius`; Flutter rejects non-uniform colours on a rounded
   border. A `bar` skin draws its edge as a child over a **uniform** border.
4. **`separatorBuilder` must use its own `context`** - it is built lazily, so
   capturing the pane's reaches a deactivated ancestor.

### 3.27 A rebuild that changes nothing the preview draws must re-render nothing

**The report:** *"if I use the demo markdown and try to add something in there,
the editor and preview both lag to display new changes."*

Measured on the 1012-line demo (`docs/verification/markdown_demo_all_features.md`,
20 909 chars), one keystroke costs **64-169 ms**. It is not the text field:
a `TextField` handling a keystroke over the same document is **3 ms**, and a
`SourceField` rebuilt with an unchanged controller is **6-10 ms**.

The cost was `PreviewPane`, and the reason is worth writing down because it does
not look like a bug:

* The pane's content sits behind a `ValueListenableBuilder` on the **debounced**
  source, which reads like it renders only when the text changes.
* **`build` runs on every parent rebuild whether the listenable fired or not.**
  The listenable gates *when* the builder is called; it does not gate *whether a
  rebuild happens*.
* `NoteEditorPane` watches the whole notes state, so every `updateNote` rebuilds
  the pane. That meant ~500 blocks re-split and re-rendered **per keystroke**, for
  text that had not changed - 46-63 ms of the 64-169.

**The rule.** Hand back the *identical* composed widget when nothing that the
pane draws has changed. Flutter's `updateChild` skips a subtree whose widget is
the same instance, so identity is the mechanism, not an optimisation trick. The
inputs the cache keys on are exactly the ones that draw: the debounced source,
the font size, `note.isCompleted`, and the theme instance. A cache keyed on less
is a pane that silently ignores a real change, which is worse than the lag.

Measured after: a parent rebuild with an unchanged source is **3-6 ms**, and one
keystroke through the real pane is **15-44 ms** - from ~5 frames to under 3.

**Two things that are not bugs, and were mistaken for them while measuring this:**

1. **The preview does not follow `note.body`.** It follows the debounced source,
   by design (§3.25's density budgets assume it). Changing the note alone must
   therefore render nothing; `preview_rebuild_test` pins that too.
2. **`AnimatedTheme` hands out the old theme at frame zero of its lerp.** A test
   that pumps once after a palette change and asserts on identity is asserting
   nothing. Pump past the duration.

**What was tried and rejected, so it is not tried again blind.** The report that
"the widget changes appear faster than the markdown preview" is the one that
locates this: the card has a height budget (2 compact, 7 large lines) and the
preview has none, so the card is fast because it is *short*, not because it is
cheap. That ruled out the storage path too — the note reaches the card quickly,
so the write, the repository and the provider are all fine.

Reusing unchanged blocks was built and measured: hand back the previous widget
for every block that ends inside a byte-identical source prefix.

| | whole document differs | one character at the end |
|---|---|---|
| before | 92–151 ms | 78–144 ms |
| after reuse | 92–151 ms | 66–85 ms |

A quarter of the problem, for a cache with a real staleness surface — a
positional heuristic plus a `]:` gate for link reference definitions, which are
consumed at parse time and so change a link's target with no text change
anywhere. So it was reverted. The remaining ~66 ms is the **whole-document parse,
block split and layout**, not building block widgets, which is why per-block
reuse could never have been the answer. Any real fix has to stop the preview
processing the whole note, which changes what the preview shows and is the
owner's call (`AGENTS.md` §0.2), not a rendering tweak.

A first-paint measurement on a **release** build, for comparison with the
widget-test numbers above:

```
frame 5:  build 141ms   raster  22ms   total 169ms
frame 6:  build 229ms   raster  21ms   total 397ms
```

Those came from `lib/core/utils/frame_log.dart`, which records frame timings when
`WIN_NOTES_FRAME_LOG` names a file and costs nothing otherwise. It exists because
a widget test builds a tree under a fake clock and a temp directory: it cannot
see a stall that lives in real file IO or the platform text-input path.

## 7. Tests

Every numbered rule in §3 appears here, with how it is actually pinned. Three
kinds, and the distinction matters: a **test** fails when the behaviour changes,
a **guard** in `test/architecture/` fails when the *code* stops looking like the
rule, and **manual** means a release build driven with `WN.Probe.cs`, which is
not in CI (`docs/testing_pattern.md` §2).

| § | Rule | Pinned by |
|---|---|---|
| 3.1 | `HTCLIENT` everywhere | **guard** `widget_guard_test` → *the runner never answers HTCAPTION*; `widget_integration_test` → *a drag is handed to the runner with its anchor* |
| 3.2 | Drag computed in screen space | **manual** — the decision is `widget_integration_test` → *a drag is handed to the runner with its anchor*; the arithmetic is verified by probe: 5 drags at exactly −60,0 |
| 3.3 | Anchor travels with the hand-off | `widget_integration_test` → *a drag is handed to the runner with its anchor* (asserts the exact anchor); **guard** `widget_guard_test` → *both move and resize seed the loop from the pending anchor*, *the loop cursor comes from the anchor, not from the live cursor*, *the anchor is consumed, so a stale one cannot be reused* |
| 3.4 | Scroll decided by extent | `widget_integration_test` → *a scroll wins over a drag while there is more list to read*, *at the top of the list, dragging down moves the widget* |
| 3.5 | Grab band; resizing never locked | `widget_integration_test` → *grabbing an edge hands a resize to the runner, with the edge*, *a locked widget is not handed to the runner* |
| 3.6 | The lock explains itself | `widget_integration_test` → *a refused drag explains itself instead of doing nothing*, *an unlocked widget does not nag about dragging* |
| 3.7 | Keyboard borrowed and returned | **guard** `widget_guard_test` → *the runner restores WS_EX_NOACTIVATE when compose mode ends*, *focus goes back to the window it was taken from*, *WM_MOUSEACTIVATE defers to compose mode*; **manual** — `GWL_EXSTYLE` and `GetForegroundWindow` before/during/after |
| 3.8 | No move or resize while composing | `widget_integration_test` → *the widget cannot be dragged while composing* |
| 3.9 | One slot, faint, keyed | `widget_integration_test` → *the field is not there until you ask for it* |
| 3.10 | One line becomes a title | `widget_integration_test` → *a jotted line becomes a note, routed to the editor* |
| 3.11 | Big card prefers unfinished | `notes_controller_test` → *the big card skips finished notes so it is never a struck-through task*, *with everything finished the big card falls back to the most recent*, *an explicit selection still wins over the unfinished preference* |
| 3.11 | "No text yet" only when empty | `widget_surface_test` → *says so when a note has nothing in it at all*, *says nothing about the body when there is a title* |
| 3.11 | Card sizing and previews | `widget_surface_test` → *is larger than a compact card*, *renders every card compact*, *shows a preview even with no body*, *collapses line breaks so previews stay one paragraph*, *falls back to a placeholder when untitled* |
| 3.12 | Hides when nothing has text | `widget_integration_test` → *no note with text means the widget is not shown*, *one note with text is enough to show it* |
| 3.13 | Sizes clamped in the runner | **manual** - a 900 px haul against the 200×140 floor |
| 3.14 | One renderer, a budget per surface | `markdown_test` → *widget density is smaller than editor density*, *only the compact card flattens a heading*, *an explicit heading scale is honoured exactly*, *editor density still gives a heading its size*, *a heading is larger than the body*, *an h6 is still not smaller than the body*, *a code block is clamped and says how much was hidden*, *a table is real in the editor and readable text in a card*, *a wide pane shows the source and the preview together*, *a narrow pane still offers a switch, not a drag*, *the budget scales with the surface type size* |
| 3.15 | Never less than it says | `markdown_test` → *unrecognised content degrades to text, never to nothing*, *raw HTML is text, not markup*, *links are styled but cannot be tapped*, *a task list draws a box and keeps the words beside it*, *a task marker is not a control*, *an image becomes its alt text, never a fetch*, *malformed syntax does not throw*, *an empty source renders nothing rather than throwing*, *a paragraph holding only an image is not blank*, *an image inside a list item is not blank*, *a br tag breaks the line rather than printing itself*, *a footnote reads once, not numbered twice*, *a list item keeps the text after an inline element*, *a list item keeps the text after a link or code run*, *an HTML comment is invisible*, *a paragraph holding only a comment renders nothing*, *an emoji shortcode becomes the character*, *an alias the table does not have stays literal*, *an alert draws its type as the callout title*, *a plain quote is still a quote, not an alert* |
| 3.15a | A wide table scrolls rather than being squeezed | `markdown_test` → *a table too wide for the pane scrolls sideways*, *a narrow table still fills the pane instead of scrolling*, *a wide table does not stack a cell into a column of characters* |
| 3.16 | Clamped by height | `markdown_test` → *a compact card still clamps to its line budget* |
| 3.17 | The widget yields to the editor | **guard** `widget_guard_test` → *nothing puts the widget above the editor*, *the scanner finds the code it is looking for in the first place*, *the guard bites: an editor with WS_EX_TOPMOST is rejected*, *the guard bites: demoting without raising the editor is rejected*, *the guard bites: an un-guarded SetAlwaysOnTop is rejected*, *the guard bites: no WM_ACTIVATE is rejected*, *the guard bites: a host with no activation handler is rejected*; **manual** - click the editor, then another app, on a release build: the widget's `WS_EX_TOPMOST` clears and returns |
| 3.18 | The editor has a minimum size | **guard** `widget_guard_test` → *the floor is enforced*, *the floor is a named constant, scaled for DPI*, *the guard bites: no WM_GETMINMAXINFO at all is rejected*, *the guard bites: ptMinSize instead of ptMinTrackSize is rejected*, *the guard bites: an unscaled floor is rejected*, *the guard bites: claiming ptMaxPosition is rejected*; **manual** - drag the editor's corner and each edge past zero on a release build: stops at exactly 520×360, and maximise is untouched |
| - | Markdown on a card | `markdown_test` → *a plain note is untouched by any of this*, *a markdown note renders rather than showing its source*, *a markdown title honours inline formatting*, *a finished markdown card is struck through* |
| - | Markdown in a list row | `markdown_test` → *a plain row still shows its source*, *a markdown row renders its preview rather than its source*, *a markdown row keeps list structure in its preview*, *a markdown row renders its title inline*, *a markdown row stays inside the row height*, *a markdown row is no taller than a plain one*, *a title honours the line count it is given* |
| — | Completion from the widget | `widget_integration_test` → *with an editor open, the widget asks rather than writes*, *a finished card draws a line through its text* |
| — | Completion does not reorder | `notes_controller_test` → *finishing a note does not reorder the list* |
| — | `ui/` reaches the runner one way | **guard** `layer_test` → *only platform/ constructs a MethodChannel* |
| 3.19 | Widgets render state, they do not hold it | **guard** `no_set_state_test` * lib/ has no setState calls at all*, *the scanner still finds them, or the rule above is vacuous*, *the two replacements are the only two*, *every ValueNotifier is listened to, or nothing rebuilds*; **guard** `provider_guard_test` * no widget holds shared state by constructor parameter*, *the scanner still matches the names it claims to*, *a value is not a dependency*, *a load result is not an injected dependency*, *callbacks are allowed, and are what the roots pass* |
| 3.20 | The Markdown switch is labelled, and says what it gets you | `markdown_test` → *the switch says what turning it on gets you*, *the switch keeps the same width in both states*, *a narrow pane still offers a switch, not a drag* |
| 3.21 | Editor and preview are sized separately; 0 means as designed, and a wheel burst is one change | `font_step_test` *pending deltas sum rather than overwrite*, *the settle sits between one frame and one rebuild*, *a burst cannot run past the slider range*; `settings_test` → *an unset font size is zero, and a file without one still reads back*, *an unset font size is left out of the file entirely*, *both font sizes round trip, separately*, *a hand-edited font size is bounded to what the slider offers*, *the font sizes participate in equality* |
| 3.22 | A saved position is pushed to the runner, not read back from it | **guard** `widget_guard_test` *SetBounds clamps to a reachable screen*, *the guard bites: a SetBounds without the clamp is rejected*, *Dart pushes the saved position rather than reading the default back*, *the method is declared on both sides, not just the registry*; `widget_integration_test` *a position written by one launch is the next launch's position*, *the saved position wins over whatever the runner reports*; **manual** - drag the widget, close the app, launch it again on a release build: it comes back where it was left |
| 3.23 | The boot-time Show is a default | **guard** `widget_guard_test` *the boot-time Show is skipped when the window was already hidden*, *a real hide records that it happened*, *the flag is a distinct member, not reused from visible_*, *the guard bites: an unguarded boot-time Show is rejected*; **probe** `WN-ENV-004` - no widget window before text exists; one small frameless window after |
| 3.24 | The split and the drawer are session state | `editor_layout_test` *it starts even, which is what two Expandeds gave before*, *a drag past either end is clamped, not obeyed*, *neither pane can be dragged out of recognition*, *the list width is bounded too*, *setting the same value twice does not produce a new state*, *it toggles*, *reset puts both measurements back without un-collapsing*, *a drag reports a position and double-click resets*, *its hit area is wider than the line it draws*, *the cursor says it can be dragged*, *a null reset does not throw on double-click*; `markdown_test` *a wide pane shows the source and the preview together*, *dragging the divider widens the source and narrows the preview*, *the divider cannot be dragged past either end*, *double-clicking the divider puts it back to even*; `editor_navigation_test` *it opens wide, and the bar button closes it*, *the edge handle opens it again*, *the handle has a hit area, not just an icon*, *the list divider resizes the list*, *collapsing is session state, not a stored preference*; **probe** `WN-EDIT-001..005` |
| 3.25 | The preview is one laid-out document | `scale_test` *the scroll extent does not change while scrolling*, *scrolling reaches the end of a note far longer than the pane*, *the last paragraph of the demo note is reachable*, *the first blocks of a long note are rendered, not skipped*, *the demo note renders as blocks, not as one blob*, *an empty note says so rather than showing nothing*; `preview_pane_test` *scrolling the preview does not throw*, *the scrollbar and the scroll view share one controller* |

| 3.26 | A skin is the shape of a card, never a colour | `skin_test` *the skin model exposes no colour field*, *a skin does not change the theme*, *every skin in the list has an id that resolves back to it*, *ids are unique, because settings.json stores one*, *empty and null mean no skin, not the first skin*, *an unknown id is null rather than the first skin*, *the built-in look is rounded 10, roomy, an accent bar, gaps*, *the editor separates with a hairline where the widget uses a gap*, *a file written before skins existed resolves to no skin*, *no skin is the built-in look, and no skin in the list is*, *corners differ across the skins*, *density tightens and loosens the built-in padding*, *focus markers differ across the skins*, *separators differ across the skins*, *a chosen skin round trips through the file*, *it is omitted when empty, for the same reason as the palette*, *the palette and the skin are separate keys and can disagree*, *it participates in equality, so no-change writes are skipped*; `skin_picker_test` *every skin is offered, and None comes first*, *tapping a chip reports that skin*, *the first chip clears the skin rather than picking the first one*, *the chosen chip is the one marked selected*, *the label under the row names the choice*, *the chips draw shape, and different skins draw different shapes*, *a chip draws a separator when its skin asks for one*; `skin_applied_test` *the card corners come from the skin*, *the card padding comes from the skin*, *the focus marker is the skin and not always a bar*, *the row corners come from the skin*, *the row padding comes from the skin* |
| 3.27 | A rebuild that changes nothing the preview draws must re-render nothing | `preview_rebuild_test` *the same source hands back the identical widget*, *a changed source does re-render*, *editing the note alone changes nothing the pane draws*, *the font size*, *the completion state*, *the theme* |
**§3.13 is the honest gap**, and it is a narrow one: the clamp arithmetic is in
the runner, its failure mode is a widget too small to read rather than a crash,
and a Dart test could only assert the absence of a bug. Everything else in §3 is
either a test or a guard.

The distinction that matters throughout: a **test** fails when the *behaviour*
changes, a **guard** fails when the *code* stops looking like the rule. §3.1 is
the one that most needs the guard — with `HTCAPTION` back in the body the widget
cannot be dragged and cards cannot be tapped, and nothing throws.

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
