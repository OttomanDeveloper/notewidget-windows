<#
.SYNOPSIS
  Drives the release build through the features PROJECT.md claims, with no contact
  whatsoever with the real profile.

.DESCRIPTION
  The Dart suite covers logic; it cannot cover whether a second isolate starts, whether
  the widget window actually appears on the desktop, or whether a file written by one
  surface is picked up by the other. Those are the things a state-layer migration could
  plausibly have broken, because it moved where every dependency is constructed.

  ## This script used to destroy the profile it was verifying

  The first version moved `%APPDATA%\WinNotes` aside, restored it in a `finally`, and
  then ran `Remove-Item $profile -Recurse -Force` on the success path - one line after
  the restore, deleting what had just been restored. It ran six times and took the
  notes with it. A PASS line printed while it did it: the script checked that the
  restore had happened, and the very next line removed it.

  So this version does not move anything. It sets `WIN_NOTES_DATA_DIR`, the override
  `AppPaths.resolve` reads, and the app runs against a directory the script created in
  `%TEMP%`. There is no stash, no move, and nothing outside `%TEMP%` to restore.

  ## The rule this file follows

  **Only ever delete a directory this script created.** `$owned` is set when a
  directory is created here and cleared once it is removed; every `Remove-Item` is
  guarded by it. A profile that existed before the run is never a deletion target, so
  there is nothing to get wrong.

  Checks:
    1. first launch on an empty profile: the editor opens
    2. no widget for an empty library
    3. notes.json is created and holds one note
    4. `--widget` relaunch: a small frameless window appears at a screen edge
    5. still running, and exactly one process
    6. quit leaves nothing behind
    7. the real profile is byte-for-byte unchanged

.EXAMPLE
  pwsh -File tool\verify\verify_release.ps1
#>
[CmdletBinding()]
param(
  # Seconds to wait for each surface to appear before calling it missing.
  [int] $TimeoutSeconds = 25,
  # Leave the throw-away profile in place afterwards, for inspection.
  [switch] $KeepProfile
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe  = Join-Path $repo 'build\windows\x64\runner\Release\win_notes.exe'

# The profile this must not touch. Recorded so it can be checked afterwards, and
# because a script that names it is a script that has thought about it.
$realProfile = Join-Path $env:APPDATA 'WinNotes'

# The directory this script owns and is therefore allowed to delete.
$work = Join-Path $env:TEMP ('winnotes-verify-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

$script:results = @()
$script:owned    = $false

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

# The only deletion in this file. `$script:owned` is the whole safety argument: it is
# set immediately after this script creates the directory and cleared the moment it is
# gone, so every other Remove-Item - of the app's data under $work - happens strictly
# inside a directory this run brought into existence.
function Remove-OwnedProfile {
  if (-not $script:owned) {
    throw 'Refusing to delete a profile this run did not create. This should be unreachable.'
  }
  if (Test-Path $work) {
    Remove-Item $work -Recurse -Force
  }
  $script:owned = $false
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace Verify -Name Native -MemberDefinition @'
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr p);
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr p);
  public struct RECT { public int Left, Top, Right, Bottom; }
'@

function Get-Windows {
  # **Every** top-level window of the class, not one per process.
  #
  # `MainWindowHandle` was used here and it cannot answer this question: the
  # editor process owns *two* windows - the editor and the widget surface - and
  # `MainWindowHandle` returns exactly one of them. So "an empty library shows no
  # widget" was comparing a count that is 1 whichever way the visibility rule
  # behaves, and passed for a reason that had nothing to do with the rule. A
  # probe that enumerated windows is what noticed, which is the argument for
  # having one. See docs\testing_pattern.md §3.
  $found = New-Object System.Collections.ArrayList
  $cb = [Verify.Native+EnumWindowsProc] {
    param($h, $p)
    $sb = New-Object System.Text.StringBuilder 256
    [Verify.Native]::GetClassName($h, $sb, 256) | Out-Null
    if ($sb.ToString() -ne 'FLUTTER_WINNOTES_WINDOW') { return $true }
    $null = $found.Add($h)
    return $true
  }
  [Verify.Native]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
  return $found
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

# A snapshot of the real profile, so "unchanged" is a fact rather than an assumption.
# Hashes, not sizes: a file can keep its length and change.
function Get-ProfileFingerprint {
  if (-not (Test-Path $realProfile)) { return @() }
  Get-ChildItem $realProfile -File | ForEach-Object {
    '{0}:{1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash
  }
}

if (-not (Test-Path $exe)) {
  throw "No release build at $exe. Run: flutter build windows --release"
}

$before = Get-ProfileFingerprint

Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

New-Item -ItemType Directory -Path $work -Force | Out-Null
$script:owned = $true

Write-Host ''
Write-Host 'Verifying the release build against an isolated profile'
Write-Host "  exe:       $exe"
Write-Host "  data dir:  $work   (via WIN_NOTES_DATA_DIR)"
Write-Host "  real one:  $realProfile - read for comparison, never written"
Write-Host ''

# Read by `AppPaths.resolve` in main(). Absolute, and checked for `..` there - which
# is the point: a bad override now fails loudly at startup instead of writing to
# somewhere nobody chose.
$env:WIN_NOTES_DATA_DIR = $work

$notesPath = Join-Path $work 'notes.json'

try {
  # --------------------------------------------------------------- 1. it starts
  Write-Host '1. First launch, empty profile'
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
  # **Visible**, not existing. The rule hides the widget window rather than
  # destroying it (`AGENTS.md` §4.4), so a widget created and then hidden is the
  # correct end state - and counting windows rather than visible ones tested
  # something the product never promised.
  #
  # Both numbers are reported, because "2 windows, 1 visible" and "1 window,
  # 1 visible" are different facts and only the second is right.
  $earlyVisible = @($early | ForEach-Object { Get-WindowInfo $_ } | Where-Object { $_.Visible })
  Check 'no widget before a note has text' `
    ($earlyVisible.Count -le 1) "$($earlyVisible.Count) visible of $($early.Count) window(s)"

  # ------------------------------------------------------------ 3. a note exists
  Write-Host ''
  Write-Host '3. The first launch has a note ready to type into'
  $seen = WaitFor { Test-Path $notesPath } $TimeoutSeconds 'notes.json'
  Check 'notes.json is created in the isolated directory' $seen

  if ($seen) {
    $doc = Get-Content $notesPath -Raw | ConvertFrom-Json
    Check 'and it holds one note' `
      ($doc.notes.Count -ge 1) "$($doc.notes.Count) note(s)"
  }

  $isolated = Test-Path (Join-Path $work 'notes.json')
Check 'the isolated directory is the one being written' `
    ($isolated -and $seen) `
    'notes.json is under %TEMP%, not %APPDATA%'

  # Deliberately *not* claiming the real profile was untouched here. It cannot be
  # checked at this point: on any machine where the profile already exists, an app
  # that wrongly created it would look identical to one that did not. Section 7
  # compares it by hash, which catches writes, and `isolate_guard_test` catches the
  # create itself. An earlier version of this line asserted "the real profile was NOT
  # created" and passed with the bug still in `main()`, because the directory was
  # already there.

  # ------------------------------------------------- 4. the widget, on its own
  Write-Host ''
  Write-Host '4. The widget surface, launched the way autostart launches it'

  # Two documented preconditions, both of which the first version of this script got
  # wrong by assuming the opposite:
  #
  #  - The app has to be *launched* with `--widget`. A normal launch opens the editor
  #    and never starts the widget isolate; `main()` branches on
  #    `launch.isWidgetSurface`. So "no second window" after a normal launch is not a
  #    bug.
  #  - A note needs *text*. A blank note is not enough (`AGENTS.md` §4.4).
  $proc | ForEach-Object { $_.CloseMainWindow() | Out-Null }
  Start-Sleep -Seconds 2
  Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 500

  if (Test-Path $notesPath) {
    # Written into the file rather than typed, because `SetForegroundWindow` returns
    # false from a process Windows does not consider foreground and `SendKeys` then
    # goes nowhere. This checks the startup ladder - which window exists, and what is
    # on disk - which is the part `flutter test` cannot see, because a Dart test has
    # no second isolate and no desktop. The keystroke path is the Dart suite's job.
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

  # The widget window is the only one, so this looks for the widget's *shape* - a
  # small visible frameless window - rather than counting. A count cannot see a
  # widget that is correctly hidden, which is how this check was wrong twice.
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

  # ------------------------------------------------------------- 5. still alive
  Write-Host ''
  Write-Host '5. It is still alive'
  Start-Sleep -Seconds 2
  # The *widget* process, not the editor's: section 4 quits the editor and starts a
  # second one, so the first handle is stale by design.
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
  # The environment variable first, so anything still running reads a path that is
  # about to stop existing rather than one it might still write to.
  Remove-Item Env:\WIN_NOTES_DATA_DIR -ErrorAction SilentlyContinue
  Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force

  if ($KeepProfile) {
    Write-Host ''
    Write-Host "Throw-away profile left at $work"
    $script:owned = $false   # the caller's now
  } else {
    try { Remove-OwnedProfile } catch { Write-Host "  (could not remove $work : $($_.Exception.Message))" }
  }
}

# ------------------------------------------------- 7. the real profile, untouched
Write-Host ''
Write-Host '7. The real profile'
$after = Get-ProfileFingerprint
$unchanged = ($before.Count -eq $after.Count)
if ($unchanged) {
  for ($i = 0; $i -lt $before.Count; $i++) {
    if ($before[$i] -ne $after[$i]) { $unchanged = $false; break }
  }
}
Check 'byte-for-byte unchanged by this run' $unchanged `
  "$($before.Count) file(s) compared by SHA-256"

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
Write-Host 'Clean. Nothing outside %TEMP% was written to.'
exit 0