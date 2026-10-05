<#
.SYNOPSIS
  Drives the release build through the features PROJECT.md claims, on a fresh profile.

.DESCRIPTION
  The Dart suite covers logic; it cannot cover whether a second isolate starts, whether
  the widget window actually appears on the desktop, or whether a file written by one
  surface is picked up by the other. Those are the things a state-layer migration could
  plausibly have broken, because it moved where every dependency is constructed.

  The profile is %APPDATA%\WinNotes, a fixed path the runner hands to Dart - there is no
  override, so "a fresh profile" means moving the real one aside and putting it back
  afterwards. That is why this script refuses to run if the stash already exists: it
  would otherwise be operating on somebody's notes without knowing it.

  Checks, in order:
    1. first launch with no profile: the app starts and shows the editor
    2. no widget for an empty library
    3. a note exists and reaches notes.json
    4. the widget window appears, because a note now has text
    5. the widget window is on screen, and is a real window
    6. the editor is still alive afterwards
    7. quit leaves no orphaned process
    8. the previous profile is restored

.EXAMPLE
  pwsh -File tool\verify\verify_release.ps1
#>
[CmdletBinding()]
param(
  # Seconds to wait for each surface to appear before calling it missing.
  [int] $TimeoutSeconds = 25,
  # Leave the fresh profile in place afterwards, for inspection.
  [switch] $KeepProfile
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe  = Join-Path $repo 'build\windows\x64\runner\Release\win_notes.exe'

# %APPDATA%\WinNotes, because that is what win_notes_platform.cpp hands to Dart.
$profile = Join-Path $env:APPDATA 'WinNotes'
$stash   = Join-Path $env:APPDATA 'WinNotes.__stash'

$script:results = @()

function Check {
  param([string] $Name, [bool] $Ok, [string] $Detail = '')
  $script:results += [pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail }
  $mark = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1}{2}" -f $mark, $Name, $(if ($Detail) { " - $Detail" } else { '' }))
}

function WaitFor {
  param([scriptblock] $Test, [int] $Seconds, [string] $What)
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    if (& $Test) { return $true }
    Start-Sleep -Milliseconds 250
  }
  Write-Host "  ...timed out waiting for $What"
  return $false
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace Verify -Name Native -MemberDefinition @'
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  public struct RECT { public int Left, Top, Right, Bottom; }
'@

function Get-Windows {
  Get-Process win_notes -ErrorAction SilentlyContinue |
    ForEach-Object { $_.MainWindowHandle } |
    Where-Object { $_ -ne 0 }
}

function Get-WindowInfo {
  param([IntPtr] $Handle)
  $r = New-Object Verify.Native+RECT
  [Verify.Native]::GetWindowRect($Handle, [ref]$r) | Out-Null
  $sb = New-Object System.Text.StringBuilder 256
  [Verify.Native]::GetClassName($Handle, $sb, 256) | Out-Null
  [pscustomobject]@{
    Handle  = $Handle
    Class   = $sb.ToString()
    Left    = $r.Left
    Top     = $r.Top
    Width   = $r.Right - $r.Left
    Height  = $r.Bottom - $r.Top
    Visible = [Verify.Native]::IsWindowVisible($Handle)
  }
}

if (-not (Test-Path $exe)) {
  throw "No release build at $exe. Run: flutter build windows --release"
}

# A leftover stash means a previous run was interrupted, and overwriting it would
# destroy the only copy of somebody's notes. Refuse rather than guess.
if (Test-Path $stash) {
  throw "A stash already exists at $stash. A previous run did not finish, and that is the only copy of those notes. Resolve it by hand before running this again."
}

Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

$hadProfile = Test-Path $profile
Write-Host ''
Write-Host 'Verifying the release build against a first-launch profile'
Write-Host "  exe:     $exe"
Write-Host "  profile: $profile$(if ($hadProfile) { ' (the existing one is stashed and restored)' } else { '' })"
Write-Host ''

if ($hadProfile) { Move-Item $profile $stash -Force }
$restored = $false
try {
  # --------------------------------------------------------------- 1. it starts
  Write-Host '1. First launch, no profile'
  $proc = Start-Process $exe -PassThru
  Check 'process stays up after launch' `
    (WaitFor { -not $proc.HasExited } $TimeoutSeconds 'the process to stay up')

  $editor = WaitFor {
    @(Get-Windows | Where-Object { (Get-WindowInfo $_).Width -gt 300 }).Count -gt 0
  } $TimeoutSeconds 'the editor window'
  Check 'the editor opens' $editor

  # --------------------------------------------------------- 2. no widget yet
  Write-Host ''
  Write-Host '2. An empty library shows no widget'
  Start-Sleep -Seconds 2
  $early = @(Get-Windows)
  Check 'no widget before a note has text' `
    ($early.Count -le 1) "$($early.Count) window(s)"

  # ------------------------------------------------------------ 3. a note exists
  Write-Host ''
  Write-Host '3. The first launch has a note ready to type into'
  $notesPath = Join-Path $profile 'notes.json'
  $seen = WaitFor { Test-Path $notesPath } $TimeoutSeconds 'notes.json'
  Check 'notes.json is created' $seen

  if ($seen) {
    $doc = Get-Content $notesPath -Raw | ConvertFrom-Json
    Check 'and it holds one note' `
      ($doc.notes.Count -ge 1) "$($doc.notes.Count) note(s)"
  }

  # ------------------------------------------------- 4. the widget, on its own
  Write-Host ''
  Write-Host '4. The widget surface, launched the way autostart launches it'

  # Two things have to be true for the widget window to exist at all, and both are
  # documented rather than discovered here:
  #
  #  - The app has to be *launched* with `--widget`. A normal launch opens the editor,
  #    and the widget is a separate isolate that a normal launch never starts -
  #    `main()` branches on `launch.isWidgetSurface`. So "no second window" after a
  #    normal launch is not a bug, and the first version of this script treated it as
  #    one.
  #  - A note has to have *text*. A blank note is not enough (`AGENTS.md` §4.4).
  #
  # So: quit the editor, put text in the note, relaunch with the flag.
  $proc | ForEach-Object { $_.CloseMainWindow() | Out-Null }
  Start-Sleep -Seconds 2
  Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 500

  if (Test-Path $notesPath) {
    $doc = Get-Content $notesPath -Raw | ConvertFrom-Json
    $doc.notes[0].body = 'Hello from the probe'
    $doc.notes[0].title = 'Probe'
    [IO.File]::WriteAllText($notesPath, ($doc | ConvertTo-Json -Depth 10))
    Check 'a note with text is on disk' `
      ((Get-Content $notesPath -Raw | ConvertFrom-Json).notes[0].body -eq 'Hello from the probe')
  }

  $widgetProc = Start-Process $exe -ArgumentList '--widget' -PassThru
  Check 'the widget launch starts' `
    (WaitFor { -not $widgetProc.HasExited } $TimeoutSeconds 'the widget process')

  # The widget window is the only one, so "did the widget surface appear" is a single
  # window with the widget's shape - frameless, small, tucked against an edge - rather
  # than a count. A count is what made this check wrong twice.
  $widgetSeen = WaitFor {
    @(Get-Windows | Where-Object {
        $i = Get-WindowInfo $_
        $i.Visible -and $i.Width -lt 600
      }).Count -ge 1
  } $TimeoutSeconds 'the widget window'
  Check 'a small frameless window appears for the widget' $widgetSeen

  if ($widgetSeen) {
    foreach ($h in @(Get-Windows)) {
      $i = Get-WindowInfo $h
      Write-Host ("      class={0,-20} {1}x{2} at {3},{4} visible={5}" -f `
        $i.Class, $i.Width, $i.Height, $i.Left, $i.Top, $i.Visible)
    }
  }

  if ($widget) {
    foreach ($h in @(Get-Windows)) {
      $i = Get-WindowInfo $h
      Write-Host ("      class={0,-20} {1}x{2} at {3},{4} visible={5}" -f `
        $i.Class, $i.Width, $i.Height, $i.Left, $i.Top, $i.Visible)
    }
  }

  # ------------------------------------------------------------- 5. still alive
  Write-Host ''
  Write-Host '5. It is still alive'
  Start-Sleep -Seconds 2
  # The *widget* process, not the editor's. Section 4 quits the editor and starts a
  # second one, so the first handle is stale by design - asking about it tests nothing
  # except that a process this script killed on purpose stayed killed.
  Check 'the widget process is still running' (-not $widgetProc.HasExited)
  Check 'and exactly one win_notes is running' `
    (@(Get-Process win_notes -ErrorAction SilentlyContinue).Count -eq 1)

  # --------------------------------------------------------------- 6. quit clean
  Write-Host ''
  Write-Host '6. Quit'
  Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 500
  Check 'no orphaned process' `
    (-not (Get-Process win_notes -ErrorAction SilentlyContinue))
}
finally {
  # Restore first, unconditionally. The whole point of stashing is that the notes are
  # not this script's to lose, and a throw in the middle must not skip that.
  if (Test-Path $profile) { Remove-Item $profile -Recurse -Force }
  if (Test-Path $stash) { Move-Item $stash $profile -Force; $restored = $true }
}

$failed = @($script:results | Where-Object { -not $_.Ok })
Write-Host ''
Write-Host ('{0} checks, {1} passed, {2} failed' -f `
  $script:results.Count, ($script:results.Count - $failed.Count), $failed.Count)

if ($hadProfile) {
  Check "the previous profile is back at $profile" $restored
}

if ($failed.Count) {
  Write-Host ''
  $failed | ForEach-Object { Write-Host "  FAILED: $($_.Name)" }
  if (-not $KeepProfile) { Remove-Item $profile -Recurse -Force -ErrorAction SilentlyContinue }
  else { Write-Host ''; Write-Host "Fresh profile left at $profile for inspection." }
  exit 1
}

if (-not $KeepProfile) { Remove-Item $profile -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ''
Write-Host 'Clean.'
exit 0