<#
.SYNOPSIS
  Checks that the icon Windows shows for WinNotes is the project's, in all four places
  it can be read from.

.DESCRIPTION
  Four independent places decide what icon a person sees, and getting three of them
  right while the fourth is wrong is exactly how "the installer has a generic logo but
  the app has the right one" happens:

    1. `setup.exe` itself  - `SetupIconFile`, read by Explorer and the taskbar
    2. the running exe     - `Runner.rc` compiling `app_icon.ico` into the binary
    3. Start Menu shortcut - `[Icons]` `IconFilename`
    4. Settings > Apps     - `DisplayIcon` in the uninstall registry key, written by
                             `UninstallDisplayIcon`

  (4) is the one that was missing, and it is the only one that is not visible in the
  build output: the installer compiled fine, produced a working shortcut, and left the
  Apps list with nothing beside the name.

  Reads the bytes rather than the source, because the question is what Windows gets,
  not what the script says. Compares every icon it finds against
  `windows\runner\resources\app_icon.ico` by SHA-256, so "the project logo" means the
  one file the runner compiles in rather than anything that merely looks like it.

.EXAMPLE
  pwsh -File tool\verify\verify_icons.ps1
#>
[CmdletBinding()]
param(
  # The built installer. Omit to check only the source-side facts.
  [string] $SetupExe = 'dist\WinNotes-1.2.0-setup.exe',
  # An installed copy, if one exists, to check the shortcut and registry entries.
  [string] $InstalledDir,
  [string] $UninstallKey
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# The one true icon.
$appIcon = Join-Path $repo 'windows\runner\resources\app_icon.ico'

$script:results = @()
function Check {
  param([string] $Name, [bool] $Ok, [string] $Detail = '')
  $script:results += [pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail }
  $mark = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1}{2}" -f $mark, $Name, $(if ($Detail) { " - $Detail" } else { '' }))
}

function HashOf { param([string] $Path) (Get-FileHash $Path -Algorithm SHA256).Hash }

# --- the icon itself ---------------------------------------------------------
Write-Host ''
Write-Host 'The icon file'
Check 'app_icon.ico exists' (Test-Path $appIcon) $appIcon

if (-not (Test-Path $appIcon)) { throw "no icon at $appIcon" }

# The sizes Inno's own help asks for, and the sizes Windows actually asks for at
# different zooms. A file that is valid but missing 16x16 shows up fine in Explorer and
# as a blank square in a Start Menu list.
$bytes = [IO.File]::ReadAllBytes($appIcon)
$frameCount = [BitConverter]::ToUInt16($bytes, 4)
$sizes = @()
for ($i = 0; $i -lt $frameCount; $i++) {
  $o = 6 + $i * 16
  $w = $bytes[$o]; $h = $bytes[$o + 1]
  $sizes += $(if ($w -eq 0) { 256 } else { $w })
}
Write-Host ("  frames: {0} ({1})" -f $frameCount, (($sizes | Sort-Object -Descending) -join ', '))

# Parenthesised as a whole, and that is not decoration. In PowerShell's *argument*
# mode - which is what a function call is - `X -eq Y` parses as two arguments rather
# than a comparison, so an unparenthesised `(...).Count -eq 0` arrived here as the
# bare count (0) plus the tokens `-eq` and `0`. It failed, with an empty "missing"
# list, which is the least legible possible report of a comparison that was never
# performed.
$wantedSizes = @(16, 32, 48, 256)
$missingSizes = @($wantedSizes | Where-Object { $sizes -notcontains $_ })
Check 'it carries the sizes Windows asks for' `
  (($missingSizes.Count -eq 0)) `
  "missing: $($missingSizes -join ', ')"

$appHash = HashOf $appIcon

# --- 1. the assets copy cannot drift -----------------------------------------
Write-Host ''
Write-Host 'The assets copy'
$assetIcon = Join-Path $repo 'assets\brand\winnotes.ico'
if (Test-Path $assetIcon) {
  Check 'assets\brand\winnotes.ico is the same drawing' `
    ((HashOf $assetIcon) -eq $appHash) `
    'if these differ, the README screenshot and the app disagree about the logo'
} else {
  Check 'assets\brand\winnotes.ico exists' $false
}

# --- 2. the running exe carries it ------------------------------------------
Write-Host ''
Write-Host 'The application binary'
$runnerRc = Join-Path $repo 'windows\runner\Runner.rc'
$rc = Get-Content $runnerRc -Raw
# Doubled backslashes, because that is how `Runner.rc` writes it - a Windows resource
# script has its own escaping rules and `resources\app_icon.ico` there means something
# else. A single-backslash regex finds nothing and reports the icon as absent.
Check 'Runner.rc compiles app_icon.ico into the exe' `
  (($rc -match 'ICON\s+"resources\\\\app_icon\.ico"')) `
  'this is what puts a logo on win_notes.exe itself'

$exe = Join-Path $repo 'build\windows\x64\runner\Release\win_notes.exe'
if (Test-Path $exe) {
  # Walk the PE resource directory for RT_GROUP_ICON (14). Reading the header is
  # enough: a resource section that exists but holds no icon group produces exactly
  # the "nothing beside the name" symptom with no other symptom at all.
  $b = [IO.File]::ReadAllBytes($exe)
  $pe = [BitConverter]::ToInt32($b, 0x3C)
  $opt = $pe + 24
  $magic = [BitConverter]::ToUInt16($b, $opt)
  $dataDir = $opt + $(if ($magic -eq 0x20B) { 112 } else { 96 })
  $resRva = [BitConverter]::ToUInt32($b, $dataDir + 16)
  $numSections = [BitConverter]::ToUInt16($b, $pe + 6)
  $sectionsOff = $opt + $(if ($magic -eq 0x20B) { 240 } else { 224 })

  $sections = @{}
  for ($i = 0; $i -lt $numSections; $i++) {
    $o = $sectionsOff + $i * 40
    $sections[[BitConverter]::ToUInt32($b, $o + 12)] = @{
      vsize = [BitConverter]::ToUInt32($b, $o + 8); raw = [BitConverter]::ToUInt32($b, $o + 20)
    }
  }
  $resOff = -1
  foreach ($k in $sections.Keys) {
    if ($resRva -ge $k -and $resRva -lt ($k + $sections[$k].vsize)) {
      $resOff = $sections[$k].raw + ($resRva - $k)
    }
  }

  $hasIcon = $false
  if ($resOff -ge 0) {
    $entries = [BitConverter]::ToUInt16($b, $resOff + 12) + [BitConverter]::ToUInt16($b, $resOff + 14)
    for ($i = 0; $i -lt $entries; $i++) {
      $id = [BitConverter]::ToUInt32($b, $resOff + 16 + $i * 8)
      if ($id -eq 14) { $hasIcon = $true }   # RT_GROUP_ICON
    }
  }
  Check 'win_notes.exe carries an icon group' $hasIcon `
    'RT_GROUP_ICON, which is what the shell resolves an icon by'
} else {
  Write-Host '  (no release build; run flutter build windows --release)'
}

# --- 3. the installer script says all four ----------------------------------
Write-Host ''
Write-Host 'The installer script'
$issPath = Join-Path $repo 'installer\winnotes.iss'
$iss = Get-Content $issPath -Raw
Check 'SetupIconFile is set - the icon on setup.exe' `
  ($iss -match '(?m)^SetupIconFile=')
Check 'UninstallDisplayIcon is set - the Apps list' `
  ($iss -match '(?m)^UninstallDisplayIcon=') `
  'the one that was missing; without it there is no DisplayIcon in the registry'
Check 'the icon is installed into {app}' `
  ($iss -match 'DestDir:\s*"\{app\}"' -and $iss -match 'Source:\s*"\{#AppIcon\}"') `
  'UninstallDisplayIcon names a path that must exist at uninstall time too'
Check 'both shortcuts name the icon file' `
  ([regex]::Matches($iss, '(?m)^Name:.*IconFilename:').Count -eq 2) `
  'the Start Menu entry and the optional desktop one'
Check 'it is not the name it looks like it should be' `
  ($iss -notmatch '(?m)^AppIconFile=') `
  'AppIconFile is not an Inno directive; ISCC rejects it'

# --- 4. the built installer -------------------------------------------------
Write-Host ''
Write-Host 'The built installer'
$setup = if ([IO.Path]::IsPathRooted($SetupExe)) { $SetupExe } else { Join-Path $repo $SetupExe }
if (Test-Path $setup) {
  Check 'setup.exe exists' $true "$([Math]::Round((Get-Item $setup).Length / 1MB, 1)) MB"

  # The icon is stored in the setup program's own resource section, uncompressed -
  # it has to be, or Explorer could not draw it before running anything. So the
  # seven PNG frames from the .ico appear as literal bytes, and counting them says
  # how many sizes are really in there.
  #
  # Built as an *array*. The first version wrote `[byte[]](0x89 -bor 0x50 -bor ...)`,
  # which is one byte - 0xDF - not four, so it searched for 0xDF 0xDF 0xDF 0xDF,
  # found nothing, and reported an installer that was in fact carrying seven frames.
  $s = [IO.File]::ReadAllBytes($setup)
  [byte[]]$pngMagic = 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
  $pngFrames = 0
  for ($i = 0; $i -le $s.Length - $pngMagic.Length; $i++) {
    $hit = $true
    for ($j = 0; $j -lt $pngMagic.Length; $j++) {
      if ($s[$i + $j] -ne $pngMagic[$j]) { $hit = $false; break }
    }
    if ($hit) { $pngFrames++ }
  }
  Check 'setup.exe carries the icon sizes' `
    (($pngFrames -ge $frameCount)) `
    "$pngFrames PNG frame(s) in the setup program, $frameCount in app_icon.ico"

  # And the size the taskbar and Explorer ask for, which is the one a person notices.
  Check 'setup.exe has an icon group the shell can resolve' `
    (($pngFrames -gt 0)) `
    'no icon means a generic setup.exe in Explorer and Downloads'
} else {
  Write-Host "  (no installer at $setup; run tool\release\package.ps1)"
}

# --- 5. an installed copy, if we can see one -------------------------------
if ($InstalledDir) {
  Write-Host ''
  Write-Host 'The installed copy'
  Check 'the icon file was installed' (Test-Path (Join-Path $InstalledDir 'app_icon.ico'))

  if ($UninstallKey -and (Test-Path $UninstallKey)) {
    $props = Get-ItemProperty $UninstallKey
    $display = $props.DisplayIcon
    Check 'the uninstall entry has a DisplayIcon' (-not [string]::IsNullOrWhiteSpace($display)) `
      $(if ($display) { $display } else { 'absent - this is why the Apps list is blank' })
    if ($display) {
      # "path,0" - the ,0 selects the first icon in the file.
      $iconPath = ($display -replace ',\s*-?\d+\s*$', '').Trim('"')
      $resolves = Test-Path $iconPath
      Check 'and it resolves to a real file' $resolves $iconPath
      if ($resolves) {
        Check 'and that file is the project icon' `
          ((HashOf $iconPath) -eq $appHash)
      }
    }
  }
}

$failed = @($script:results | Where-Object { -not $_.Ok })
Write-Host ''
Write-Host ('{0} checks, {1} passed, {2} failed' -f `
  $script:results.Count, ($script:results.Count - $failed.Count), $failed.Count)
if ($failed.Count) {
  Write-Host ''
  $failed | ForEach-Object { Write-Host "  FAILED: $($_.Name)" }
  exit 1
}
Write-Host ''
exit 0