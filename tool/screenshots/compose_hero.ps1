<#
.SYNOPSIS
  Builds the README hero image from the captured WinNotes surfaces.

.DESCRIPTION
  Lays the editor and widget captures onto a neutral backdrop. Everything inside
  the two windows is a real PrintWindow capture of the real app running with
  sample notes - the only thing authored here is the background behind them.

  The backdrop uses the app's own brand colours so the image reads as part of
  the project rather than as a random picture of a window.

.EXAMPLE
  pwsh -File tool/screenshots/compose_hero.ps1 `
      -Editor docs/images/editor.png -Widget docs/images/widget.png -OutPath docs/images/hero.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Editor,
    [Parameter(Mandatory)][string]$Widget,
    [string]$OutPath = 'docs/images/hero.png',

    [int]$CanvasW = 1600,
    [int]$CanvasH = 860,

    # Where each capture is placed. Both are drawn at their native pixel size,
    # so nothing in the screenshot is scaled or retouched.
    [int]$EditorX = 72, [int]$EditorY = 120,
    [int]$WidgetX = 1140, [int]$WidgetY = 205
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$editorBmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Editor).Path)
$widgetBmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Widget).Path)
$canvas = [System.Drawing.Bitmap]::new($CanvasW, $CanvasH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

$g = [System.Drawing.Graphics]::FromImage($canvas)
try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    # Backdrop: a deep indigo-to-black field, the app's plate colour pulled right
    # down, with one soft indigo glow and one soft coral glow from the wordmark.
    $g.Clear([System.Drawing.Color]::FromArgb(255, 17, 19, 27))
    $field = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.Rectangle]::new(0, 0, $CanvasW, $CanvasH),
        [System.Drawing.Color]::FromArgb(255, 30, 35, 58),
        [System.Drawing.Color]::FromArgb(255, 13, 14, 20),
        [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
    $g.FillRectangle($field, 0, 0, $CanvasW, $CanvasH)
    $field.Dispose()

    $glows = @(
        @{ x = 300;  y = 700; r = 620; c = @(46, 60, 122) },
        @{ x = 1400; y = 180; r = 520; c = @(70, 34, 40) },
        @{ x = 900;  y = 240; r = 380; c = @(28, 44, 96) }
    )
    foreach ($gl in $glows) {
        $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $path.AddEllipse($gl.x - $gl.r, $gl.y - $gl.r, $gl.r * 2, $gl.r * 2)
        $pg = [System.Drawing.Drawing2D.PathGradientBrush]::new($path)
        $pg.CenterColor = [System.Drawing.Color]::FromArgb($gl.c[0], $gl.c[1], $gl.c[2])
        $pg.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
        $g.FillEllipse($pg, $gl.x - $gl.r, $gl.y - $gl.r, $gl.r * 2, $gl.r * 2)
        $pg.Dispose()
        $path.Dispose()
    }

    # Soft shadow, faked by stacking increasingly large low-alpha rounded rects.
    # A real blur would need a shader; the stacked rings are indistinguishable
    # at this size and cost nothing.
    function Drop([int]$x, [int]$y, [int]$w, [int]$h, [int]$radius) {
        for ($i = 10; $i -ge 1; $i--) {
            $spread = $i * 5
            $alpha = [int](5 + (10 - $i) * 1.6)
            $brush = [System.Drawing.SolidBrush]::new(
                [System.Drawing.Color]::FromArgb($alpha, 0, 0, 0))
            $g.FillRectangle($brush,
                $x - $spread + 6, $y - $spread + 14,
                $w + $spread * 2, $h + $spread * 2)
            $brush.Dispose()
        }
    }

    Drop $EditorX $EditorY $editorBmp.Width $editorBmp.Height 24
    Drop $WidgetX $WidgetY $widgetBmp.Width $widgetBmp.Height 24

    $g.DrawImageUnscaled($editorBmp, $EditorX, $EditorY)
    $g.DrawImageUnscaled($widgetBmp, $WidgetX, $WidgetY)
}
finally {
    $g.Dispose()
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Resolve-Path '.').Path) | Out-Null
$outFull = if ([IO.Path]::IsPathRooted($OutPath)) { $OutPath } else { Join-Path (Get-Location).Path $OutPath }
$canvas.Save($outFull, [System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Dispose()
$editorBmp.Dispose()
$widgetBmp.Dispose()
Write-Host "wrote $outFull"