<#
.SYNOPSIS
  Captures the two WinNotes surfaces from a live run.

.DESCRIPTION
  Uses PrintWindow rather than a screen grab. PrintWindow asks DWM to render one
  window's own pixels into a bitmap, so nothing behind it can leak in: no desktop
  icons, no other windows, no wallpaper, and no other person's personal
  shortcuts. It also means this script never touches the desktop - it does not
  change the wallpaper, move your taskbar, minimise anything, or restart
  Explorer.

  The only thing it does change is running WinNotes: it stops any existing
  instance, launches the build you point it at, and parks the two windows.

.EXAMPLE
  pwsh -File tool/screenshots/capture.ps1 `
      -ExePath build/windows/x64/runner/Release/win_notes.exe `
      -OutDir  docs/images
#>
[CmdletBinding()]
param(
    [string]$ExePath = 'build/windows/x64/runner/Release/win_notes.exe',
    [string]$OutDir = 'docs/images',
    [switch]$KeepRunning,

    # Window sizes for the shot. The widget's real size is whatever the user last
    # left it at, which is often taller than its content, so it is sized to fit.
    [int]$EditorW = 1000, [int]$EditorH = 660,
    [int]$WidgetW = 380, [int]$WidgetH = 340
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    Add-Type -AssemblyName System.Drawing
    if (-not ('WN.Win' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'WN.cs') }
    if (-not ('WN.Print' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'WN.Print.cs') }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $exe = (Resolve-Path $ExePath).Path

    Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2

    Start-Process -FilePath $exe
    Write-Host 'launched; waiting for both windows'
    $editor = [IntPtr]::Zero
    $widget = [IntPtr]::Zero
    for ($i = 0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 1
        $editor = [WN.Win]::FindWindowW('FLUTTER_WINNOTES_WINDOW', 'WinNotes')
        $widget = [WN.Win]::FindWindowW('FLUTTER_WINNOTES_WINDOW', 'WinNotes Widget')
        if ($editor -ne [IntPtr]::Zero -and $widget -ne [IntPtr]::Zero) { break }
    }
    if ($editor -eq [IntPtr]::Zero -or $widget -eq [IntPtr]::Zero) {
        throw 'the editor or the widget window never appeared'
    }

    # PrintWindow renders whatever DWM currently holds for the window. Flutter
    # composites lazily, so a window that exists but has not yet drawn a frame
    # comes back solid black. Give both windows a first frame, and put each one
    # in front before its capture, so what is captured is what is on screen.
    Write-Host 'waiting for the first frames'
    Start-Sleep -Seconds 8
    [WN.Win]::Place($editor, 60, 40, $EditorW, $EditorH)
    [WN.Win]::Place($widget, 1400, 300, $WidgetW, $WidgetH)
    Start-Sleep -Seconds 3

    # Rejects a capture that is a single flat colour. Without this the script
    # happily writes a black PNG and the failure only shows up in the README.
    function Test-Detail([System.Drawing.Bitmap]$bmp) {
        $min = 255; $max = 0
        for ($y = 4; $y -lt $bmp.Height - 4; $y += 7) {
            for ($x = 4; $x -lt $bmp.Width - 4; $x += 7) {
                $v = $bmp.GetPixel($x, $y)
                $l = [int](0.299 * $v.R + 0.587 * $v.G + 0.114 * $v.B)
                if ($l -lt $min) { $min = $l }
                if ($l -gt $max) { $max = $l }
            }
        }
        return $max - $min
    }

    function Capture([IntPtr]$h, [string]$path) {
        $r = [WN.Win]::Rect($h)
        $w = $r.R - $r.L
        $ht = $r.B - $r.T
        $bmp = [System.Drawing.Bitmap]::new($w, $ht, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $dc = $g.GetHdc()
        $ok = [WN.Print]::PrintWindow($h, $dc, [WN.Print]::PW_RENDERFULLCONTENT)
        $g.ReleaseHdc($dc)
        $g.Dispose()
        if (-not $ok) { $bmp.Dispose(); throw "PrintWindow failed for $path" }

        $detail = Test-Detail $bmp
        if ($detail -lt 12) {
            $bmp.Dispose()
            throw "capture of $path is blank (luma range $detail). The window had not rendered a frame."
        }

        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host ("  {0}  {1}x{2}  luma range {3}" -f [IO.Path]::GetFileName($path), $w, $ht, $detail)
        $bmp.Dispose()
    }

    Write-Host 'capturing'
    [WN.Win]::Raise($editor)
    Start-Sleep -Seconds 3
    Capture $editor (Join-Path $OutDir 'editor.png')

    [WN.Win]::Raise($widget)
    Start-Sleep -Seconds 3
    Capture $widget (Join-Path $OutDir 'widget.png')

    if (-not $KeepRunning) {
        Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force
    }
    Write-Host "wrote editor.png and widget.png to $OutDir"
}
finally {
    Pop-Location
}