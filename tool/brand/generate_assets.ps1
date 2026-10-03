<#
.SYNOPSIS
  Rasterises the WinNotes SVG masters into the PNG and .ico files the app,
  the installer and the docs need.

.DESCRIPTION
  Chrome headless does the SVG rasterising because it is the only renderer on
  this machine that implements the SVG filter features the master art uses
  (feDropShadow, gradient on a clip path). A hand-rolled encoder packs the
  .ico files rather than shelling out to ImageMagick, which is not installed.

  Each .ico is assembled from its own source SVG per size. That is deliberate:
  winnotes_mark_small.svg is a separately drawn, much heavier mark, because
  the full-detail master turns to mush below 32px. Mixing one raster into
  every size is the usual shortcut and it looks wrong in the tray.

.EXAMPLE
  pwsh -File tool/brand/generate_assets.ps1
#>
[CmdletBinding()]
param(
  [string]$ChromeExe = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BrandDir   = Join-Path $RepoRoot 'assets\brand'
$RunnerRes  = Join-Path $RepoRoot 'windows\runner\resources'
$BuildDir   = Join-Path $RepoRoot 'build\brand'

if (-not (Test-Path $ChromeExe)) {
  throw "Chrome not found at $ChromeExe. Pass -ChromeExe <path>."
}
if (-not (Test-Path $BrandDir)) { throw "Brand source directory missing: $BrandDir" }

foreach ($d in @($BuildDir, $RunnerRes)) {
  if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# --- Chrome rasteriser -------------------------------------------------------

$script:ChromeProfile = Join-Path $env:TEMP 'winnotes-brand-chrome'
$script:RenderCount   = 0

function Invoke-SvgRender {
  <#
    Renders one SVG at one pixel size and returns the PNG path.

    The SVG master is copied with its width/height swapped for the target
    size. The viewBox is left alone, so all the master geometry scales
    proportionally and nothing in the artwork needs to know about this script.
  #>
  param(
    [Parameter(Mandatory)][string]$SvgPath,
    [Parameter(Mandatory)][int]$Size
  )

  $renderDir = Join-Path $BuildDir ("render_{0}x{0}" -f $Size)
  if (-not (Test-Path $renderDir)) { New-Item -ItemType Directory -Path $renderDir -Force | Out-Null }

  $svgText = Get-Content -LiteralPath $SvgPath -Raw

  # Rewrite ONLY the root <svg> element's width/height.
  #
  # This is done by locating the opening tag by index rather than with a regex
  # replace-and-count. Regex.Replace has both a (input, pattern, replacement,
  # int count) and a (input, pattern, replacement, RegexOptions) overload; an
  # integer literal binds to both from PowerShell, and the wrong one wins.
  # That silently rewrote every width/height pair in the document, which turns
  # every pill-shaped bar in the masters into a square.
  $openStart = $svgText.IndexOf('<svg')
  if ($openStart -lt 0) { throw "No <svg> root in $SvgPath" }
  $openEnd = $svgText.IndexOf('>', $openStart)
  if ($openEnd -lt 0) { throw "Unterminated <svg> root in $SvgPath" }

  $openTag = $svgText.Substring($openStart, $openEnd - $openStart + 1)
  $openTag = [regex]::Replace($openTag, '\swidth="[^"]*"', " width=`"$Size`"")
  $openTag = [regex]::Replace($openTag, '\sheight="[^"]*"', " height=`"$Size`"")
  if ($openTag -notmatch '\swidth=' -or $openTag -notmatch '\sheight=') {
    throw "Root <svg> in $SvgPath has no width/height to substitute."
  }
  $svgText = $openTag + $svgText.Substring($openEnd + 1)

  $stem      = [IO.Path]::GetFileNameWithoutExtension($SvgPath)
  $stagedSvg = Join-Path $renderDir "$stem.svg"
  $outPng    = Join-Path $renderDir "$stem.png"
  Set-Content -LiteralPath $stagedSvg -Value $svgText -Encoding utf8NoBOM
  if (Test-Path $outPng) { Remove-Item -LiteralPath $outPng -Force }

  $profile = Join-Path $script:ChromeProfile ("p{0}" -f $script:RenderCount)
  $script:RenderCount++

  Invoke-ChromeScreenshot -PngPath $outPng -ProfileDir $profile -Width $Size -Height $Size `
    -Target ('file:///' + ($stagedSvg -replace '\\', '/'))

  if (-not (Test-Path $outPng)) {
    throw "Chrome failed to render ${SvgPath} at ${Size}px."
  }
  $outPng
}

function Invoke-ChromeScreenshot {
  <#
    Runs headless Chrome once and waits for the PNG to land on disk.

    Chrome's own stdout/stderr are redirected to files: left attached it
    interleaves "N bytes written to file" lines and process tables into the
    build log, which makes a genuine failure very hard to spot.
  #>
  param(
    [Parameter(Mandatory)][string]$PngPath,
    [Parameter(Mandatory)][string]$ProfileDir,
    [Parameter(Mandatory)][int]$Width,
    [Parameter(Mandatory)][int]$Height,
    [Parameter(Mandatory)][string]$Target   # file:// URL of the SVG to render
  )

  $logDir = Join-Path $BuildDir 'chrome-logs'
  if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
  $errLog = Join-Path $logDir ("chrome_{0}.log" -f $script:RenderCount)

  $args = @(
    '--headless=new'
    '--disable-gpu'
    '--no-sandbox'
    '--no-first-run'
    '--no-default-browser-check'
    '--disable-extensions'
    '--disable-lcd-text'                 # greyscale AA; keeps edges crisp at 16px
    '--force-device-scale-factor=1'
    '--hide-scrollbars'
    '--default-background-color=00000000'  # transparent, so the plate keeps rounded corners
    "--user-data-dir=$ProfileDir"
    "--screenshot=$PngPath"
    "--window-size=$Width,$Height"
    $Target
  )

  Start-Process -FilePath $ChromeExe -ArgumentList $args -Wait -NoNewWindow `
    -RedirectStandardOutput $errLog -RedirectStandardError "$errLog.err"
}

function New-IcoFromPngs {
  <#
    Packs rendered PNGs into a Vista-style .ico.

    Entries are PNG-compressed, which Windows 11 reads natively. BMP (DIB)
    entries exist only for pre-Vista compatibility and would triple the file
    size to support operating systems this app does not target.

    -Frames is an ordered list of @{ Size = n; Png = path }. Size must be
    supplied per frame: deriving it from the array length silently writes a
    valid-looking .ico full of nonsense entries, because nothing about the
    PNG bytes encodes which resolution they were rendered at.
  #>
  param(
    [Parameter(Mandatory)][string]$OutPath,
    [Parameter(Mandatory)][System.Collections.IList]$Frames
  )

  $entries = @()
  $offset  = 6 + (16 * $Frames.Count)   # header + one dir entry per image
  foreach ($frame in $Frames) {
    $bytes = [IO.File]::ReadAllBytes($frame.Png)
    # Validate the requested size, not the encoded byte: 256 encodes as 0.
    if ($frame.Size -lt 1 -or $frame.Size -gt 256) {
      throw "Illegal icon size $($frame.Size) for $OutPath"
    }
    $dim   = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
    $entries += [pscustomobject]@{
      Width    = $dim
      Height   = $dim
      Planes   = [uint16]1
      BitCount = [uint16]32
      Bytes    = $bytes
      Offset   = $offset
    }
    $offset += $bytes.Length
  }

  $ms = [IO.MemoryStream]::new()
  $bw = [IO.BinaryWriter]::new($ms)
  try {
    $bw.Write([uint16]0)                 # reserved
    $bw.Write([uint16]1)                 # type 1 = icon
    $bw.Write([uint16]$entries.Count)
    foreach ($e in $entries) {
      $bw.Write([byte]$e.Width)
      $bw.Write([byte]$e.Height)
      $bw.Write([byte]0)                # palette size; 0 = truecolour
      $bw.Write([byte]0)                # reserved
      $bw.Write($e.Planes)
      $bw.Write($e.BitCount)
      $bw.Write([uint32]$e.Bytes.Length)
      $bw.Write([uint32]$e.Offset)
    }
    foreach ($e in $entries) { $bw.Write($e.Bytes) }
    $bw.Flush()
    [IO.File]::WriteAllBytes($OutPath, $ms.ToArray())
  }
  finally {
    $bw.Dispose(); $ms.Dispose()
  }
  $OutPath
}

function Test-IcoFrames {
  <#
    Verifies every .ico frame by re-reading the PNG IHDR at the declared
    offset and comparing its real pixel dimensions against the directory
    entry. A malformed entry is easy to write and invisible until Windows
    picks the wrong tray size, so this check is not optional.
  #>
  param([Parameter(Mandatory)][string]$Path)

  $b   = [IO.File]::ReadAllBytes($Path)
  $n   = [BitConverter]::ToUInt16($b, 4)
  $bad = @()
  for ($i = 0; $i -lt $n; $i++) {
    $o    = 6 + (16 * $i)
    $dw   = [int]$b[$o]; if ($dw -eq 0) { $dw = 256 }
    $dh   = [int]$b[$o + 1]; if ($dh -eq 0) { $dh = 256 }
    $len  = [BitConverter]::ToUInt32($b, $o + 8)
    $off  = [BitConverter]::ToUInt32($b, $o + 12)

    # PNG signature (0-7), IHDR length (8-11), "IHDR" (12-15), then w and h.
    if ($off + 24 -gt $b.Length) { $bad += "frame $i : offset $off past EOF"; continue }
    $sig = ($b[$off..($off + 7)] | ForEach-Object { $_.ToString('X2') }) -join ''
    if ($sig -ne '89504E470D0A1A0A') { $bad += "frame $i : not a PNG at offset $off"; continue }

    # PNG is big-endian. BitConverter is little-endian on x86, so decoding the
    # IHDR width with it turns 256 into 65536 and reports a healthy ico as
    # corrupt. Shifting by hand keeps the check honest.
    $pw = ([int]$b[$off + 16] -shl 24) -bor ([int]$b[$off + 17] -shl 16) -bor
          ([int]$b[$off + 18] -shl 8)  -bor  [int]$b[$off + 19]
    $ph = ([int]$b[$off + 20] -shl 24) -bor ([int]$b[$off + 21] -shl 16) -bor
          ([int]$b[$off + 22] -shl 8)  -bor  [int]$b[$off + 23]

    if ($pw -ne $dw -or $ph -ne $dh) {
      $bad += "frame $i : dir says ${dw}x${dh} but payload is ${pw}x${ph}"
    }
    if ($off + $len -gt $b.Length) { $bad += "frame $i : declared length overruns file" }
  }
  if ($bad.Count) { throw "Malformed .ico $Path`n  " + ($bad -join "`n  ") }
  Write-Host ("  verified {0}: {1} frames" -f [IO.Path]::GetFileName($Path), $n)
}

# --- What gets produced ------------------------------------------------------

$full = Join-Path $BrandDir 'winnotes_mark.svg'
$small = Join-Path $BrandDir 'winnotes_mark_small.svg'
$trayLight = Join-Path $BrandDir 'winnotes_tray_light.svg'
$trayDark  = Join-Path $BrandDir 'winnotes_tray_dark.svg'
$wordmark  = Join-Path $BrandDir 'winnotes_wordmark.svg'
$wordmarkLight = Join-Path $BrandDir 'winnotes_wordmark_light.svg'
foreach ($f in @($full, $small, $trayLight, $trayDark, $wordmark, $wordmarkLight)) {
  if (-not (Test-Path $f)) { throw "Missing SVG master: $f" }
}

Write-Host 'Rendering mark raster tiers...'
# Documentation / in-app PNG tiers. 16 and 32 come from the small master.
$pngOut = @{}
foreach ($tier in @(
    @{ size = 1024; src = $full  },
    @{ size = 512;  src = $full  },
    @{ size = 256;  src = $full  },
    @{ size = 128;  src = $full  },
    @{ size = 64;   src = $small },
    @{ size = 32;   src = $small },
    @{ size = 16;   src = $small })) {
  $rendered = Invoke-SvgRender -SvgPath $tier.src -Size $tier.size
  $dest = Join-Path $BrandDir ("winnotes_mark_{0}.png" -f $tier.size)
  Copy-Item -LiteralPath $rendered -Destination $dest -Force
  $pngOut[$tier.size] = $dest
  Write-Host ("  mark {0,4}px  (from {1})" -f $tier.size, [IO.Path]::GetFileName($tier.src))
}

Write-Host 'Rendering wordmark...'
# Two lockups, because a transparent-background PNG of the near-white-on-dark
# variant disappears on a white page, which is where READMEs live.
$lockups = @(
  @{ svg = $wordmark;       tag = 'winnotes_wordmark'        },
  @{ svg = $wordmarkLight;  tag = 'winnotes_wordmark_light'  }
)
$wordmarkSizes = @(@{ w = 1600; h = 480 }, @{ w = 800; h = 240 })
foreach ($lockup in $lockups) {
  foreach ($w in $wordmarkSizes) {
    $svgText = Get-Content -LiteralPath $lockup.svg -Raw
    $openStart = $svgText.IndexOf('<svg')
    $openEnd   = $svgText.IndexOf('>', $openStart)
    $openTag   = $svgText.Substring($openStart, $openEnd - $openStart + 1)
    $openTag   = [regex]::Replace($openTag, '\swidth="[^"]*"',  " width=`"$($w.w)`"")
    $openTag   = [regex]::Replace($openTag, '\sheight="[^"]*"', " height=`"$($w.h)`"")
    $svgText   = $openTag + $svgText.Substring($openEnd + 1)

    $renderDir = Join-Path $BuildDir ("render_{0}_{1}x{2}" -f $lockup.tag, $w.w, $w.h)
    if (-not (Test-Path $renderDir)) { New-Item -ItemType Directory -Path $renderDir -Force | Out-Null }
    $staged = Join-Path $renderDir 'lockup.svg'
    $outPng = Join-Path $renderDir 'lockup.png'
    Set-Content -LiteralPath $staged -Value $svgText -Encoding utf8NoBOM
    if (Test-Path $outPng) { Remove-Item -LiteralPath $outPng -Force }

    Invoke-ChromeScreenshot -PngPath $outPng -ProfileDir $script:ChromeProfile `
      -Width $w.w -Height $w.h -Target ('file:///' + ($staged -replace '\\', '/'))
    if (-not (Test-Path $outPng)) { throw "Wordmark render failed for $($lockup.tag) at $($w.w)x$($w.h)." }

    Copy-Item -LiteralPath $outPng -Destination (Join-Path $BrandDir ("{0}_{1}x{2}.png" -f $lockup.tag, $w.w, $w.h)) -Force
    Write-Host ("  {0} {1}x{2}" -f $lockup.tag, $w.w, $w.h)
  }
}

Write-Host 'Building .ico files...'

function New-FrameSet {
  <# Renders each requested size and pairs it with its size for the encoder. #>
  param([string]$SvgPath, [int[]]$Sizes)
  foreach ($s in $Sizes) {
    [pscustomobject]@{ Size = $s; Png = (Invoke-SvgRender -SvgPath $SvgPath -Size $s) }
  }
}

# App / taskbar icon: full detail from 48px up, heavy master below that.
$appSizes = @(256, 128, 64, 48, 32, 24, 16)
$appIco = Join-Path $BrandDir 'winnotes.ico'
# The low tiers are drawn from the small master, so the frame list is the
# concatenation of two renders rather than one loop over the size list.
$appFrames = @(New-FrameSet -SvgPath $full -Sizes @(256, 128, 64, 48)) +
             @(New-FrameSet -SvgPath $small -Sizes @(32, 24, 16))
New-IcoFromPngs -OutPath $appIco -Frames $appFrames | Out-Null
Copy-Item -LiteralPath $appIco -Destination (Join-Path $RunnerRes 'app_icon.ico') -Force
Test-IcoFrames -Path $appIco
Write-Host ("  winnotes.ico  sizes: {0}" -f ($appSizes -join ', '))

# Tray icons: monochrome-first silhouettes, one per taskbar theme.
$traySizes = @(48, 40, 32, 24, 20, 16)
foreach ($pair in @(@{ n = 'light'; s = $trayLight }, @{ n = 'dark'; s = $trayDark })) {
  $ico = Join-Path $BrandDir ("winnotes_tray_{0}.ico" -f $pair.n)
  New-IcoFromPngs -OutPath $ico -Frames (New-FrameSet -SvgPath $pair.s -Sizes $traySizes) | Out-Null
  Test-IcoFrames -Path $ico
  # Also staged next to the exe: the shell tray has to exist before any Dart
  # isolate has booted, and the runner loads these by path to swap between
  # light and dark taskbars at runtime.
  Copy-Item -LiteralPath $ico -Destination (Join-Path $RunnerRes ("winnotes_tray_{0}.ico" -f $pair.n)) -Force
  Write-Host ("  winnotes_tray_{0}.ico  sizes: {1}" -f $pair.n, ($traySizes -join ', '))
}

if (Test-Path $script:ChromeProfile) {
  Remove-Item -LiteralPath $script:ChromeProfile -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Brand assets up to date:'
Get-ChildItem -LiteralPath $BrandDir -File |
  Sort-Object Name |
  Select-Object Name, @{ n = 'KB'; e = { [math]::Round($_.Length / 1KB, 1) } } |
  Format-Table -AutoSize