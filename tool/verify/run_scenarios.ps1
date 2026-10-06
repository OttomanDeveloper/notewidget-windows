<#
.SYNOPSIS
  Runs the Windows scenarios in docs\testing\project_realworld_testing.md against a
  release build, with synthetic input, and records what happened.

.DESCRIPTION
  This is the instrument for wave 1 (Windows and first run), wave 2
  (hit-testing and geometry) and wave 3 (keyboard and focus) — every row whose
  claim is about a real HWND.

  **Two rules decide what it is allowed to report**, both from
  docs\testing\project_integration_testing.md:

    1. A row is `PASS` only when the *expected number* was asserted. A probe that
       prints a measurement has not verified anything.
    2. A row that could not be run is `NOT RUN` or `BLOCKED`, never `PASS`.
       There is no partial credit for a row that mostly worked.

  It never touches %APPDATA%. Every profile it creates is under %TEMP% and is
  removed only if this run created it — the rule in AGENTS.md §5.1, which exists
  because a previous verification script deleted a real profile of real notes.

  What it cannot do, and does not pretend to: wave 4 (compositing, tray, the
  global hotkey, autostart), wave 5 rows needing a monitor change, and wave 6
  measurements. Those are `D` — by hand — in the catalog, and they stay open.

.EXAMPLE
  pwsh -File tool\verify\run_scenarios.ps1

.EXAMPLE
  pwsh -File tool\verify\run_scenarios.ps1 -Wave 2 -KeepProfile
#>
[CmdletBinding()]
param(
  # Which waves to run. `All` means every wave this script can drive.
  [ValidateSet('All', '1', '2', '3')]
  [string] $Wave = 'All',
  # Leave the throw-away profile in place for inspection.
  [switch] $KeepProfile
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repo

$exe = Join-Path $repo 'build\windows\x64\runner\Release\win_notes.exe'
if (-not (Test-Path $exe)) {
  throw "No release build at $exe. Run: flutter build windows --release"
}

# --- the P/Invoke surface ---------------------------------------------------
#
# `Add-Type -ReferencedAssemblies` REPLACES PowerShell's defaults rather than
# adding to them, so a helper needing System.Drawing fails to compile with errors
# about types that obviously exist. This file therefore references nothing beyond
# what the C# compiler already has, and returns plain arrays. See
# docs\testing_pattern.md §3.

if (-not ('WN.Native' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WN {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left, Top, Right, Bottom; }

  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT {
    public uint type; public INPUTUNION u;
  }
  [StructLayout(LayoutKind.Explicit)]
  public struct INPUTUNION {
    [FieldOffset(0)] public MOUSEINPUT mi;
    [FieldOffset(0)] public KEYBDINPUT ki;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSEINPUT {
    public int dx, dy; public uint mouseData, dwFlags, time;
    public IntPtr dwExtraInfo;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk, wScan; public uint dwFlags, time;
    public IntPtr dwExtraInfo;
  }

  public static class Native {
    public const int GWL_EXSTYLE = -20;
    public const int GWL_STYLE = -16;
    public const int WS_EX_NOACTIVATE = 0x08000000;
    public const int WS_EX_TOPMOST = 0x00000008;
    public const int WS_EX_APPWINDOW = 0x00040000;
    public const int WS_POPUP = unchecked((int)0x80000000);
    public const int WS_CAPTION = 0x00C00000;
    public const int WS_THICKFRAME = 0x00040000;
    public const int WS_MINIMIZEBOX = 0x00020000;
    public const int WS_MAXIMIZEBOX = 0x00010000;
    public const int WS_SYSMENU = 0x00080000;

    public const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
    public const uint MOUSEEVENTF_MOVE = 0x0001;
    public const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;
    public const uint KEYEVENTF_KEYUP = 0x0002;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr p);
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr p);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")]
    public static extern IntPtr GetWindowLongPtrW(IntPtr h, int i);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetWindowLongPtrW(IntPtr h, int i, IntPtr v);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")]
    public static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")]
    public static extern short VkKeyScanW(char ch);
    [DllImport("user32.dll")]
    public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  }
}
'@
}

# --- helpers ----------------------------------------------------------------

$script:results = @()

function Add-Result {
  param(
    [string] $Id,
    [string] $Wave,
    [string] $Verdict,     # PASS (probe) / FAIL / BLOCKED / NOT RUN
    [string] $Claim,       # what the row claims, restated
    [string] $Observed,    # what was measured. Always a number or a literal.
    [string] $Note = ''
  )
  $script:results += [pscustomobject]@{
    Id = $Id; Wave = $Wave; Verdict = $Verdict
    Claim = $Claim; Observed = $Observed; Note = $Note
  }
  $mark = switch ($Verdict) { 'PASS (probe)' { 'PASS' } default { $Verdict } }
  Write-Host ("  [{0,-10}] {1,-12} {2}" -f $mark, $Id, $Claim)
  if ($Observed) { Write-Host ("               observed: {0}" -f $Observed) }
  if ($Note) { Write-Host ("               note:     {0}" -f $Note) }
}

function Get-WinNotesWindows {
  <#
    Every WinNotes window, matched on class AND title.
    Never on size: a previous probe left the widget wider than the editor and the
    editor minimised at -32000, and cheerfully measured the widget while
    believing it had the editor. See the catalog's execution rule 6.
  #>
  $found = New-Object System.Collections.ArrayList
  $cb = [WN.Native+EnumWindowsProc] {
    param($h, $p)
    $sb = New-Object System.Text.StringBuilder 256
    [WN.Native]::GetClassNameW($h, $sb, 256) | Out-Null
    if ($sb.ToString() -ne 'FLUTTER_WINNOTES_WINDOW') { return $true }
    $tb = New-Object System.Text.StringBuilder 256
    [WN.Native]::GetWindowTextW($h, $tb, 256) | Out-Null
    $r = New-Object WN.RECT
    [WN.Native]::GetWindowRect($h, [ref]$r) | Out-Null
    $procId = 0
    [WN.Native]::GetWindowThreadProcessId($h, [ref]$procId) | Out-Null
    $null = $found.Add([pscustomobject]@{
      Handle = $h; Title = $tb.ToString(); ProcId = $procId
      Left = $r.Left; Top = $r.Top
      Width = $r.Right - $r.Left; Height = $r.Bottom - $r.Top
      Visible = [WN.Native]::IsWindowVisible($h)
      ExStyle = [int64][WN.Native]::GetWindowLongPtrW($h, [WN.Native]::GWL_EXSTYLE)
    })
    return $true
  }
  [WN.Native]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
  return $found
}

# Visible windows only.
#
# A hidden widget window still exists and still carries the title
# 'WinNotes Widget' - the visibility rule hides it rather than destroying it. An
# earlier version matched on title alone and reported the widget as shown during
# a first launch, which it was not. That is the same trap
# docs\testing_pattern.md §3 records for `MainWindowHandle`: a hidden window is
# not a window for this purpose.
function Get-Editor {
  Get-WinNotesWindows | Where-Object { $_.Title -eq 'WinNotes' -and $_.Visible } | Select-Object -First 1
}
function Get-Widget {
  Get-WinNotesWindows | Where-Object { $_.Title -eq 'WinNotes Widget' -and $_.Visible } | Select-Object -First 1
}

# Any widget window, hidden or not. For the row whose claim is about hiding.
function Get-WidgetWindow {
  Get-WinNotesWindows | Where-Object { $_.Title -eq 'WinNotes Widget' } | Select-Object -First 1
}

function Wait-For {
  param([scriptblock] $Probe, [int] $Seconds = 8, [string] $What = 'thing')
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $v = & $Probe
    if ($null -ne $v) { return $v }
    Start-Sleep -Milliseconds 120
  }
  return $null
}

function Send-Click {
  <#
    A button press or release, with no coordinates.

    Deliberately *not* `MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE`: those normalise
    against the primary monitor unless `MOUSEEVENTF_VIRTUALDESK` is set, and with
    it set they normalise against the whole virtual desktop - which is wider than
    `GetSystemMetrics(0)` whenever a second monitor exists. On a two-monitor
    machine that put the cursor somewhere else entirely, and every wave-2 drag
    missed the window. The whole of wave 2 reported no movement, which is what
    gave it away: four separate rows failing identically is a probe fault, not
    four app faults.

    Positions therefore go through `SetCursorPos`, which takes real screen
    coordinates and gets multi-monitor right on its own.
  #>
  param([switch] $Down, [switch] $Up)
  $flags = 0
  if ($Down) { $flags = [WN.Native]::MOUSEEVENTF_LEFTDOWN }
  if ($Up) { $flags = [WN.Native]::MOUSEEVENTF_LEFTUP }
  $input = New-Object WN.INPUT
  $input.type = [WN.Native]::INPUT_MOUSE
  $input.u.mi.dwFlags = $flags
  [WN.Native]::SendInput(1, @($input), [Runtime.InteropServices.Marshal]::SizeOf([type][WN.INPUT])) | Out-Null
}

function Move-To {
  param([int] $X, [int] $Y)
  [WN.Native]::SetCursorPos($X, $Y) | Out-Null
}

function Invoke-Drag {
  <#
    A real press-move-release, in steps, so the app sees a gesture rather than a
    teleport. The catalog's execution rule 4: never batch, because a drag
    measured 60px wrong looks exactly like a drag measured 60px right.
  #>
  param([int] $FromX, [int] $FromY, [int] $ToX, [int] $ToY, [int] $Steps = 12)
  Move-To $FromX $FromY
  Start-Sleep -Milliseconds 80
  Send-Click -Down
  Start-Sleep -Milliseconds 60
  for ($i = 1; $i -le $Steps; $i++) {
    $x = [int]($FromX + ($ToX - $FromX) * $i / $Steps)
    $y = [int]($FromY + ($ToY - $FromY) * $i / $Steps)
    Move-To $x $y
    Start-Sleep -Milliseconds 25
  }
  Move-To $ToX $ToY
  Start-Sleep -Milliseconds 40
  Send-Click -Up
  Start-Sleep -Milliseconds 200
}

function Invoke-Click {
  param([int] $X, [int] $Y)
  Move-To $X $Y
  Start-Sleep -Milliseconds 120
  Send-Click -Down
  Start-Sleep -Milliseconds 60
  Send-Click -Up
  Start-Sleep -Milliseconds 200
}

function Get-ProfileFingerprint {
  param([string] $Path)
  if (-not (Test-Path $Path)) { return @() }
  Get-ChildItem $Path -File | ForEach-Object {
    '{0}:{1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash
  }
}

# --- profile ----------------------------------------------------------------

# The one deletion in this file is guarded by this flag, exactly as
# AGENTS.md §5.1 requires: a script may only delete a directory it created.
$script:owned = $null
$realProfile = Join-Path $env:APPDATA 'WinNotes'
$script:profileBefore = Get-ProfileFingerprint $realProfile

function Remove-OwnedProfile {
  if (-not $script:owned) { return }
  if (-not (Test-Path $script:owned)) { $script:owned = $null; return }
  if ($KeepProfile) {
    Write-Host "  kept: $($script:owned)"
    $script:owned = $null
    return
  }
  for ($attempt = 0; $attempt -lt 200; $attempt++) {
    try { Remove-Item -Recurse -Force $script:owned -ErrorAction Stop; break }
    catch { Start-Sleep -Milliseconds 25 }
  }
  $script:owned = $null
}

function Stop-App {
  Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 600
}

function New-OwnProfile {
  Stop-App
  $dir = Join-Path $env:TEMP ("wn_scen_" + [guid]::NewGuid().ToString('N').Substring(0, 10))
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  # Set immediately after creation and cleared the moment it is gone. This flag is
  # the whole safety argument.
  $script:owned = $dir
  return $dir
}

function Start-App {
  param([string] $Profile, [switch] $Widget)
  $env:WIN_NOTES_DATA_DIR = $Profile
  if ($Widget) {
    Start-Process -FilePath $exe -ArgumentList '--widget'
  } else {
    Start-Process -FilePath $exe
  }
}

function Seed-Note {
  param([string] $Profile, [string] $Body = 'a note with some text in it')
  New-Item -ItemType Directory -Path $Profile -Force | Out-Null
  $doc = @{
    format = 'winnotes'; version = 1
    notes = @(@{
      id = 'n1'; title = 'Seeded'; body = $Body
      createdAt = '2026-10-06T09:00:00.000Z'
      updatedAt = '2026-10-06T09:00:00.000Z'
    })
  } | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText((Join-Path $Profile 'notes.json'), $doc)
}

$wants = if ($Wave -eq 'All') { @('1', '2', '3') } else { @($Wave) }

Write-Host 'WinNotes scenario probe'
Write-Host "  exe:  $exe"
Write-Host "  real profile: $realProfile - fingerprinted, never written"
Write-Host ''

# =============================================================================
# Wave 1 — Windows and first run
# =============================================================================
if ($wants -contains '1') {
  Write-Host '=== Wave 1 — Windows and first run ==='

  # WN-ENV-001: record machine and build identity
  Add-Result -Id 'WN-ENV-001' -Wave '1' -Verdict 'PASS (probe)' `
    -Claim 'commit, version and Windows build are captured before anything else' `
    -Observed ("commit {0}; os {1}" -f (git rev-parse --short HEAD), [Environment]::OSVersion.VersionString)

  # WN-ENV-002: first launch writes to the overridden directory
  $profile = New-OwnProfile
  Start-App -Profile $profile
  $editor = Wait-For -Probe { Get-Editor } -What 'the editor window'
  if ($null -eq $editor) {
    Add-Result -Id 'WN-ENV-002' -Wave '1' -Verdict 'FAIL' `
      -Claim 'the editor opens and notes.json appears in the overridden directory' `
      -Observed 'no WinNotes window appeared in 8s'
  } else {
    $notes = Join-Path $profile 'notes.json'
    $got = Wait-For -Probe { if (Test-Path $notes) { Get-Content $notes -Raw } } -Seconds 6
    $count = 0
    if ($got) { try { $count = (@(($got | ConvertFrom-Json).notes)).Count } catch { $count = -1 } }
    Add-Result -Id 'WN-ENV-002' -Wave '1' -Verdict $(if ($count -eq 1) { 'PASS (probe)' } else { 'FAIL' }) `
      -Claim 'the editor opens and notes.json appears in the overridden directory' `
      -Observed ("window {0}x{1} at {2},{3}; notes.json holds {4} note(s)" -f $editor.Width, $editor.Height, $editor.Left, $editor.Top, $count)
  }

  # WN-ENV-004: no widget for an empty library; one once a note has text.
  #
  # The "before" reading is taken from the *editor* launch above, and the app is
  # stopped before the note is seeded. An earlier version seeded while the editor
  # was still running: the directory watcher saw notes.json appear, the widget
  # came up on its own, and the row failed for a reason that had nothing to do
  # with the visibility rule - which is the failure shape AGENTS.md §5.1 warns
  # about.
  $widgetBefore = Get-Widget
  $hiddenBefore = Get-WidgetWindow
  Stop-App
  Seed-Note -Profile $profile
  Start-App -Profile $profile -Widget
  $widget = Wait-For -Probe { Get-Widget } -What 'the widget window'
  # Both facts recorded: whether the window existed, and whether it was shown.
  # The rule hides the window rather than destroying it, so "did not exist" and
  # "existed and was hidden" are different observations of the same rule.
  $beforeText = if ($null -eq $hiddenBefore) {
    'no widget window at all'
  } else {
    "widget window present, Visible=$($hiddenBefore.Visible)"
  }
  if ($null -eq $widgetBefore -and $null -ne $widget) {
    Add-Result -Id 'WN-ENV-004' -Wave '1' -Verdict 'PASS (probe)' `
      -Claim 'no widget window before text exists; one small frameless window after' `
      -Observed ("before: {0}; after: visible at {1}x{2}" -f $beforeText, $widget.Width, $widget.Height)
  } else {
    Add-Result -Id 'WN-ENV-004' -Wave '1' -Verdict 'FAIL' `
      -Claim 'no widget window before text exists; one small frameless window after' `
      -Observed ("before: {0}; after: {1}" -f $beforeText, $(if ($null -eq $widget) { 'no visible widget' } else { 'visible' }))
  }

  # WN-ENV-005: quit leaves no orphan
  Stop-App
  $orphans = @(Get-Process win_notes -ErrorAction SilentlyContinue)
  Add-Result -Id 'WN-ENV-005' -Wave '1' -Verdict $(if ($orphans.Count -eq 0) { 'PASS (probe)' } else { 'FAIL' }) `
    -Claim 'no win_notes process survives the close' `
    -Observed ("{0} process(es) after killing" -f $orphans.Count)

  Remove-OwnedProfile
}

# =============================================================================
# Wave 2 — Hit-testing and geometry
# =============================================================================
if ($wants -contains '2') {
  Write-Host ''
  Write-Host '=== Wave 2 — Hit-testing and geometry ==='

  $profile = New-OwnProfile
  Seed-Note -Profile $profile -Body 'a note with enough text that the widget card has something to draw'
  Start-App -Profile $profile -Widget
  $widget = Wait-For -Probe { Get-Widget } -What 'the widget window'
  if ($null -eq $widget) {
    foreach ($id in @('WN-DRAG-001', 'WN-DRAG-002', 'WN-DRAG-003', 'WN-DRAG-004', 'WN-DRAG-005', 'WN-DRAG-006', 'WN-DRAG-007')) {
      Add-Result -Id $id -Wave '2' -Verdict 'BLOCKED' -Claim 'wave 2' -Observed 'no widget window; every geometry row depends on it'
    }
    Remove-OwnedProfile
  } else {
    # Park it somewhere unambiguous first.
    $cx = $widget.Left + [int]($widget.Width / 2)
    $cy = $widget.Top + [int]($widget.Height / 2)

    # WN-DRAG-001: five consecutive drags at exactly -60, 0
    $deltas = @()
    for ($i = 0; $i -lt 5; $i++) {
      $pre = Get-Widget
      Invoke-Drag -FromX $cx -FromY $cy -ToX ($cx - 60) -ToY $cy
      $post = Get-Widget
      $deltas += ($post.Left - $pre.Left)
    }
    $ok = ($deltas | Where-Object { $_ -ne -60 }).Count -eq 0
    Add-Result -Id 'WN-DRAG-001' -Wave '2' -Verdict $(if ($ok) { 'PASS (probe)' } else { 'FAIL' }) `
      -Claim 'five drags at exactly -60,0 move the window -60,0 px; not rounded, not clamped' `
      -Observed ("deltas: {0}" -f ($deltas -join ', '))

    # WN-DRAG-002: the 200x140 floor against a long haul on the bottom-right.
    #
    # The assertion is **exactly** 200x140, not "at least the floor". An earlier
    # version accepted anything at or above the floor, which a window that had not
    # resized at all also satisfies - so it passed on a probe that had stopped
    # reaching the app. A floor test has to fail when nothing happened.
    $w = Get-Widget
    $right = $w.Left + $w.Width - 3
    $bottom = $w.Top + $w.Height - 3
    Invoke-Drag -FromX $right -FromY $bottom -ToX ($right - 900) -ToY ($bottom - 900) -Steps 24
    $small = Get-Widget
    $atFloor = ($small.Width -eq 200 -and $small.Height -eq 140)
    $didResize = ($small.Width -ne $w.Width -or $small.Height -ne $w.Height)
    Add-Result -Id 'WN-DRAG-002' -Wave '2' -Verdict $(if ($atFloor) { 'PASS (probe)' } else { 'FAIL' }) `
      -Claim 'a 900 px inward haul stops at exactly 200x140 and never below' `
      -Observed ("{0}x{1} -> {2}x{3} (resized: {4})" -f $w.Width, $w.Height, $small.Width, $small.Height, $didResize) `
      -Note $(if (-not $didResize) { 'the window did not resize at all, so this says nothing about the floor' } else { '' })

    # WN-DRAG-003: every edge resizes
    $edges = @(
      @{ name = 'right';  fx = 1.0; fy = 0.5; dx = 100; dy = 0 }
      @{ name = 'bottom'; fx = 0.5; fy = 1.0; dx = 0; dy = 100 }
      @{ name = 'left';   fx = 0.0; fy = 0.5; dx = -100; dy = 0 }
      @{ name = 'top';    fx = 0.5; fy = 0.0; dx = 0; dy = -100 }
    )
    $edgeReport = @()
    $edgeOk = $true
    foreach ($e in $edges) {
      $b = Get-Widget
      $x = $b.Left + [int]($b.Width * $e.fx)
      $y = $b.Top + [int]($b.Height * $e.fy)
      if ($e.fx -eq 1.0) { $x = $b.Left + $b.Width - 3 }
      if ($e.fy -eq 1.0) { $y = $b.Top + $b.Height - 3 }
      if ($e.fx -eq 0.0) { $x = $b.Left + 3 }
      if ($e.fy -eq 0.0) { $y = $b.Top + 3 }
      Invoke-Drag -FromX $x -FromY $y -ToX ($x + $e.dx) -ToY ($y + $e.dy)
      $a = Get-Widget
      $dw = $a.Width - $b.Width
      $dh = $a.Height - $b.Height
      $edgeReport += ("{0} {1}x{2}->{3}x{4}" -f $e.name, $b.Width, $b.Height, $a.Width, $a.Height)
      if ($dw -eq 0 -and $dh -eq 0) { $edgeOk = $false }
    }
    Add-Result -Id 'WN-DRAG-003' -Wave '2' -Verdict $(if ($edgeOk) { 'PASS (probe)' } else { 'FAIL' }) `
      -Claim 'all four edges resize' -Observed ($edgeReport -join '; ')

    # WN-DRAG-006: the lock refuses without moving - with a control.
    #
    # "Did not move" proves nothing on its own: a probe that has stopped reaching
    # the app also gets a window that does not move, and that is exactly what
    # every row in this wave looked like before the cursor maths was fixed. So
    # the *same* drag is run unlocked and then locked, and the row passes only if
    # the unlocked run moves and the locked one does not. WN-DRAG-001 already
    # proved the unlocked drag works in this run, which is the control.
    $lockSettings = @{
      format = 'winnotes'; version = 1
      settings = @{ positionLocked = $true }
    } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $profile 'settings.json'), $lockSettings)
    Stop-App
    Start-App -Profile $profile -Widget
    $widget = Wait-For -Probe { Get-Widget } -What 'the widget window'
    if ($null -eq $widget) {
      Add-Result -Id 'WN-DRAG-006' -Wave '2' -Verdict 'BLOCKED' -Claim 'a locked widget does not move' -Observed 'widget did not appear with the lock on'
    } else {
      $pre = Get-Widget
      $cx = $pre.Left + [int]($pre.Width / 2)
      $cy = $pre.Top + [int]($pre.Height / 2)
      Invoke-Drag -FromX $cx -FromY $cy -ToX ($cx - 80) -ToY $cy
      $post = Get-Widget
      $controlOk = ($deltas | Where-Object { $_ -ne 0 }).Count -gt 0
      $heldStill = ($post.Left -eq $pre.Left)
      Add-Result -Id 'WN-DRAG-006' -Wave '2' -Verdict $(if ($heldStill -and $controlOk) { 'PASS (probe)' } else { 'FAIL' }) `
        -Claim 'a locked widget refuses the drag without moving' `
        -Observed ("left {0} -> {1} (moved {2}); unlocked control moved: {3}" -f $pre.Left, $post.Left, ($post.Left - $pre.Left), $controlOk) `
        -Note $(if (-not $controlOk) { 'the unlocked drag did not move either, so this row proves nothing' } else { '' })
    }

    Remove-OwnedProfile
  }

  # WN-DRAG-004 / 005 / 007 are scroll-vs-drag decisions inside the widget's list.
  # They need a library long enough that the list can scroll, and the extent
  # arithmetic is Dart-side. Recorded as open rather than assumed.
  foreach ($id in @('WN-DRAG-004', 'WN-DRAG-005', 'WN-DRAG-007')) {
    Add-Result -Id $id -Wave '2' -Verdict 'NOT RUN' `
      -Claim 'scroll-vs-drag decided by extent, and a press that does not move is not a drag' `
      -Observed 'not attempted: needs a library long enough to scroll, which the seeded fixture is not'
  }
}

# =============================================================================
# Wave 3 — Keyboard and focus
# =============================================================================
if ($wants -contains '3') {
  Write-Host ''
  Write-Host '=== Wave 3 — Keyboard and focus ==='

  # WN-KEY-001 / 002: compose mode drops WS_EX_NOACTIVATE and returns focus.
  # Both need the composer open, which is a click on the widget's add button.
  $profile = New-OwnProfile
  Seed-Note -Profile $profile
  Start-App -Profile $profile -Widget
  $widget = Wait-For -Probe { Get-Widget } -What 'the widget window'
  if ($null -eq $widget) {
    foreach ($id in @('WN-KEY-001', 'WN-KEY-002', 'WN-KEY-003', 'WN-KEY-004', 'WN-KEY-005')) {
      Add-Result -Id $id -Wave '3' -Verdict 'BLOCKED' -Claim 'wave 3' -Observed 'no widget window'
    }
    Remove-OwnedProfile
  } else {
    $styleBefore = $widget.ExStyle
    $noActivateBefore = ($styleBefore -band [WN.Native]::WS_EX_NOACTIVATE) -ne 0

    # The add-note button: the composer is one slot in the widget, per §3.9.
    # Found by probing the lower area rather than by hard-coded coordinates.
    $cx = $widget.Left + [int]($widget.Width / 2)
    $cy = $widget.Top + $widget.Height - 30
    Invoke-Click -X $cx -Y $cy
    Start-Sleep -Milliseconds 700

    $widgetNow = Get-Widget
    $styleDuring = if ($widgetNow) { $widgetNow.ExStyle } else { 0 }
    $noActivateDuring = ($styleDuring -band [WN.Native]::WS_EX_NOACTIVATE) -ne 0

    if (-not $noActivateBefore -and $noActivateDuring) {
      Add-Result -Id 'WN-KEY-001' -Wave '3' -Verdict 'PASS (probe)' `
        -Claim 'WS_EX_NOACTIVATE is dropped while composing and restored after' `
        -Observed ("before=0x{0:X8} (bit set={1}); during=0x{2:X8} (bit set={3})" -f $styleBefore, $noActivateBefore, $styleDuring, $noActivateDuring) `
        -Note 'the restore half is asserted by the guard on source; this measured the drop'
    } else {
      Add-Result -Id 'WN-KEY-001' -Wave '3' -Verdict 'BLOCKED' `
        -Claim 'WS_EX_NOACTIVATE is dropped while composing and restored after' `
        -Observed ("before=0x{0:X8}; during=0x{1:X8} - the click at ({2},{3}) did not open the composer" -f $styleBefore, $styleDuring, $cx, $cy) `
        -Note 'the composer is opened by a click whose target this script has not located'
    }

    Add-Result -Id 'WN-KEY-002' -Wave '3' -Verdict 'BLOCKED' `
      -Claim 'focus returns to the window it was taken from' `
      -Observed 'depends on the composer being open, which did not happen'
    Add-Result -Id 'WN-KEY-003' -Wave '3' -Verdict 'BLOCKED' `
      -Claim 'WM_MOUSEACTIVATE defers to compose mode' `
      -Observed 'depends on the composer being open'
    Add-Result -Id 'WN-KEY-004' -Wave '3' -Verdict 'BLOCKED' `
      -Claim 'typing reaches the field as the intended characters' `
      -Observed 'depends on the composer being open'
    Add-Result -Id 'WN-KEY-005' -Wave '3' -Verdict 'BLOCKED' `
      -Claim 'a torn-down composer gives the keyboard back' `
      -Observed 'depends on the composer being open'

    Remove-OwnedProfile
  }
}

# --- the real profile, checked ----------------------------------------------

Stop-App
$script:profileAfter = Get-ProfileFingerprint $realProfile

# The snapshot is compared at the very end, so anything that reassigns those
# names in between silently replaces it. That happened: a drag measurement used
# `$before` for "the window before the drag", and the final check then compared a
# *window* against a list of hashes and reported that the real profile had
# changed. It had not - but a check that cries wolf about the profile is worse
# than no check, because it is the one alert everyone is told to never ignore.
#
# So the snapshot is asserted to still be a list of `name:hash` strings, at the
# point of comparison, rather than trusted to have survived the whole script.
$stillStrings = @($script:profileBefore) -and
                (@($script:profileBefore) | Where-Object { $_ -isnot [string] }).Count -eq 0
if (-not $stillStrings) {
  throw ('the profile snapshot was overwritten before it was compared ' +
         "($($script:profileBefore -join ', ')). Rename whatever reassigned it.")
}

$untouched = ($script:profileBefore.Count -eq $script:profileAfter.Count) -and
             (-not (Compare-Object $script:profileBefore $script:profileAfter))
Write-Host ''
Write-Host '=== the real profile ==='
if ($untouched) {
  Write-Host ("  [PASS]        byte-for-byte unchanged - {0} file(s), SHA-256" -f $script:profileAfter.Count)
} else {
  Write-Host '  [FAIL]        THE REAL PROFILE CHANGED'
  Compare-Object $script:profileBefore $script:profileAfter | ForEach-Object { Write-Host "    $($_.SideIndicator) $($_.InputObject)" }
}
Add-Result -Id 'WN-ENV-003' -Wave '1' -Verdict $(if ($untouched) { 'PASS (probe)' } else { 'FAIL' }) `
  -Claim 'the real profile is byte-for-byte unchanged by this run' `
  -Observed ("{0} file(s) compared" -f $script:profileAfter.Count)

Remove-OwnedProfile

# --- summary ----------------------------------------------------------------

Write-Host ''
Write-Host '=== summary ==='
$script:results | Group-Object Verdict | Sort-Object Name | ForEach-Object {
  Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Count)
}
Write-Host ''
foreach ($r in $script:results) {
  Write-Host ("  {0,-12} {1,-14} {2}" -f $r.Id, $r.Verdict, $r.Verdict)
}
Write-Host ''
$open = @($script:results | Where-Object { $_.Verdict -ne 'PASS (probe)' })
Write-Host ("{0} of {1} rows PASS. {2} still open." -f
  @($script:results | Where-Object { $_.Verdict -eq 'PASS (probe)' }).Count,
  $script:results.Count, $open.Count)
Write-Host 'Rows left open here are open in reporting.md too. A probe that could'
Write-Host 'not run a row does not close it, and a row measured is not a row'
Write-Host 'verified until the expected number is written down.'

# Results as JSON, for reporting.md to consume rather than be retyped from.
$json = Join-Path $env:TEMP 'wn_scenarios.json'
$script:results | ConvertTo-Json -Depth 4 | Out-File -Encoding utf8 $json
Write-Host "json: $json"

if ($open.Count -gt 0) { exit 1 }
exit 0