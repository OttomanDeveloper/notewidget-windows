# WinNotes brand assets

Everything here is generated from the SVG masters. Edit the SVGs, then run:

```powershell
pwsh -File tool/brand/generate_assets.ps1
```

Never hand-edit a `.png` or `.ico`; the next run overwrites it.

## The mark

A note card mid-write: two settled lines, one live line, one caret. Deep indigo
plate, off-white card, coral accent.

The coral is the caret and nothing else. It is the only warm colour in the mark,
and it is on the one element that means *being written right now*. Everything
else is cool and recessive so the caret is what the eye finds first.

The indigo plate exists so the off-white card reads as a surface floating above
the desktop rather than as a glyph sitting on a coloured square. It is also
deliberately *not* Fluent blue, which is what every other Windows 11 app uses.

## Files

| File | Purpose |
| --- | --- |
| `winnotes_mark.svg` | Primary mark. 1024 master grid. |
| `winnotes_mark_small.svg` | Small-size mark for 16-32px. |
| `winnotes_tray_light.svg` | Tray icon for a light taskbar. |
| `winnotes_tray_dark.svg` | Tray icon for a dark taskbar. |
| `winnotes_wordmark.svg` | Horizontal lockup, for dark surfaces. |
| `winnotes_wordmark_light.svg` | Horizontal lockup, for light surfaces. |
| `winnotes.ico` | App icon. 256, 128, 64, 48, 32, 24, 16. |
| `winnotes_tray_light.ico` / `_dark.ico` | Tray. 48, 40, 32, 24, 20, 16. |
| `winnotes_mark_*.png` | Raster tiers for docs and in-app use. |
| `winnotes_wordmark_*.png` | Rendered lockups, transparent background. |

The tray `.ico` files are also copied into `windows/runner/resources/` by the
generator, because the shell needs a tray icon before any Dart isolate has
booted.

## Three things that will bite you

**Small sizes are redrawn, not scaled.** `winnotes_mark_small.svg` is a separate
piece of artwork with much heavier strokes and no rotation. Scaling the detailed
master down to 16px turns the pill-shaped bars into noise and the rotation into a
smudge.

**Both wordmarks ship.** The near-white-on-dark lockup has a transparent
background, so "Win" disappears entirely on a white page. The `_light` variant
uses dark ink. Pick by surface.

**Every `.ico` frame is verified.** The generator re-reads each embedded PNG's
IHDR header and compares its real pixel dimensions against the directory entry.
A wrong entry produces a file that looks fine in a viewer and renders as garbage
at exactly one size, usually the tray icon.

## Geometry notes

Both marks are drawn on a 1024 grid with a `rx=224` plate, following Windows 11's
rounded-rectangle proportions. The card is rotated -5° about its centre so it
reads as a physical object being placed on the desktop.

The wordmarks keep text as `<text>` rather than outlining it, so they stay
editable. They are rasterised on Windows with Segoe UI Variable Display, which
every supported Windows 11 build ships. If a lockup ever needs to render
somewhere without that font, convert the two runs to paths first.