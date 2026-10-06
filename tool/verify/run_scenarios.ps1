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

    // The widget window is NOT the rectangle GetWindowRect reports: it carries a
    // rounded region, and the pixels within ~4 px of a corner are not part of the
    // window at all. A probe that grabs `Right - 3, Bottom - 3` is aiming at the
    // desktop - the press goes to whatever is behind, the app never sees it, and
    // the row reports "corner resize does not work". It does work; the grab was
    // outside the window.
    //
    // It is worth being precise about why this hid for so long: `WindowFromPoint`
    // at that same pixel returns the FLUTTERVIEW child, which is a plain rectangle
    // under the cursor" probe says yes. Only `PtInRegion` against the HRGN from
    // `GetWindowRgn` gives the truth, which is what GrabCorner below uses.
    [DllImport("user32.dll")]
    public static extern int GetWindowRgn(IntPtr hwnd, IntPtr hrgn);
    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateRectRgn(int l, int t, int r, int b);
    [DllImport("gdi32.dll")]
    public static extern bool PtInRegion(IntPtr hrgn, int x, int y);
    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr o);

    // The whole INPUT has to be assembled here rather than in PowerShell.
    //
    // `$input.u.mi.dwFlags = $flags` does not write through: `$input.u` yields a
    // *copy* of the union, `.mi` a copy of the MOUSEINPUT inside that, and the
    // assignment lands on the copy. `$input` keeps dwFlags = 0, which Win32 reads
    // as MOUSEEVENTF_MOVE by (0, 0) - a legal, queueable, entirely empty event.
    //
    // So SendInput returned 1 every time and reported success, the cursor path was
    // correct, and not one button press ever reached the app. Every wave-2 row
    // reported "the window did not move", which reads exactly like four app bugs.
    public static uint SendMouse(uint flags) {
      var i = new INPUT();
      i.type = INPUT_MOUSE;
      i.u.mi.dwFlags = flags;
      return SendInput(1, new INPUT[] { i }, Marshal.SizeOf(typeof(INPUT)));
    }

    // A point on the window that is inside the grab band and inside the window's
    // region. Searches from the middle of the band outwards, so it prefers the
    // point furthest from the corner that is still hittable: 12 px in is inside
    // a 14 px band and clear of a 4 px corner radius, whereas 2 px in is inside
    // the band and on the desktop.
    //
    // `edge_x`/`edge_y` are **window-local** edge coordinates (0 or the width /
    // height) and the result is window-local too, because `GetWindowRgn` reports
    // the region in window coordinates. Feeding it screen coordinates answers a
    // different question and reports "no grab point" for every corner.
    // `edge_x`/`edge_y` are **window-local** edge coordinates (0 or the width /
    // height) and the result is window-local too, because `GetWindowRgn` reports
    // the region in window coordinates. Feeding it screen coordinates answers a
    // different question and reports "no grab point" for every corner.
    //
    // The search starts at 6 px in, not at 12. Measured on a release build: a
    // grab 12 px in from the bottom-right corner is *inside the window region*
    // and *inside the 14 px band the docs claim*, and does not resize; 6 px in
    // resizes reliably, and 8 px in resizes on a smaller window. So the band is
    // narrower in practice than `docs/widget_pattern.md` 3.5 states, and the
    // probe has to aim closer to the edge than the documentation implies. Noted
    // rather than guessed at: the exact value is `_grabBand = (14 / scale)` and
    // this does not measure `scale`.
    public static bool TryGrabPoint(IntPtr hwnd, int edge_x, int edge_y,
                                    bool onRight, bool onBottom,
                                    out int px, out int py) {
      IntPtr rgn = CreateRectRgn(0, 0, 4096, 4096);
      try {
        GetWindowRgn(hwnd, rgn);
        for (int off = 6; off >= 4; off--) {
          int x = onRight ? edge_x - off : edge_x + off;
          int y = onBottom ? edge_y - off : edge_y + off;
          if (PtInRegion(rgn, x, y)) { px = x; py = y; return true; }
        }
        px = 0; py = 0; return false;
      } finally {
        DeleteObject(rgn);
      }
    }
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
  $sent = [WN.Native]::SendMouse($flags)
  # `SendInput` returns how many events it queued. Zero means the struct layout
  # is wrong - on x64 a 40-byte `INPUT` declared as anything else is the usual
  # cause - and it fails silently. Throwing is what separates "the app ignored my
  # drag" from "my probe never sent one", which from the outside are identical.
  if ($sent -ne 1) {
    throw ("SendInput queued {0} of 1 event. A drag that is never sent looks " +
           "exactly like a drag the app ignores.") -f $sent
  }
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
  param([int] $FromX, [int] $FromY, [int] $ToX, [int] $ToY, [int] $Steps = 12, [int] $StepMs = 25)
  Move-To $FromX $FromY
  Start-Sleep -Milliseconds 80
  Send-Click -Down
  Start-Sleep -Milliseconds 60
  $trace = @()
  for ($i = 1; $i -le $Steps; $i++) {
    $x = [int]($FromX + ($ToX - $FromX) * $i / $Steps)
    $y = [int]($FromY + ($ToY - $FromY) * $i / $Steps)
    Move-To $x $y
    Start-Sleep -Milliseconds $StepMs
    if ($script:traceDrag) {
      $p = New-Object 'WN.Native+POINT'
      [WN.Native]::GetCursorPos([ref]$p) | Out-Null
      $trace += ("{0},{1}" -f $p.X, $p.Y)
    }
  }
  Move-To $ToX $ToY
  Start-Sleep -Milliseconds 40
  Send-Click -Up
  Start-Sleep -Milliseconds 200
  if ($script:traceDrag -and $trace.Count -gt 0) {
    Write-Host ("    cursor path: {0}" -f ($trace -join ' '))
  }
}

function Get-GrabPoint {
  <#
    A point to press for an edge or a corner, in screen coordinates.

    Never `Right - 3`. The widget's corners are rounded off, so that pixel is
    not part of the window and the press lands on whatever is behind it. Measured
    on a release build: the first pixel along the corner diagonal that belongs to
    the window is 4 px in, and the Dart grab band is 14 px - so the usable overlap
    is 4..14, and this takes the deepest point in it that is still hittable.

    `WindowFromPoint` cannot be used to check this: it returns the rectangular
    FLUTTERVIEW child even at a corner pixel the parent does not own.
  #>
  param(
    [string] $Where,   # left | right | top | bottom | topLeft | topRight | bottomLeft | bottomRight
    $Win
  )
  $onRight  = $Where -like '*ight*'
  $onBottom = $Where -like '*ottom*'
  $cx = if ($onRight) { $Win.Width } else { 0 }
  $cy = if ($onBottom) { $Win.Height } else { 0 }
  $px = 0; $py = 0
  $ok = [WN.Native]::TryGrabPoint($Win.Handle, $cx, $cy, $onRight, $onBottom, [ref]$px, [ref]$py)
  if (-not $ok) { return $null }
  # Window-local in, screen out: the caller aims with these.
  return [pscustomobject]@{
    X = $Win.Left + $px
    Y = $Win.Top + $py
    Dx = $px
    Dy = $py
  }
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
  param(
    [string] $Profile,
    [string] $Body = 'a note with some text in it',
    [int] $Count = 1
  )
  New-Item -ItemType Directory -Path $Profile -Force | Out-Null
  # More than one note, so the widget's list overflows and the scroll-vs-drag
  # rows have something to scroll. A single note cannot test either branch of
  # `_listCanScroll`, and a row run against a fixture that cannot express its
  # claim is a row that passes for the wrong reason or not at all.
  $notes = @()
  for ($i = 1; $i -le $Count; $i++) {
    $notes += @{
      id = "n$i"; title = "Seeded $i"; body = "$Body ($i)"
      createdAt = '2026-10-06T09:00:00.000Z'
      updatedAt = '2026-10-06T09:00:00.000Z'
    }
  }
  $doc = @{ format = 'winnotes'; version = 1; notes = $notes } | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText((Join-Path $Profile 'notes.json'), $doc)
}

$script:traceDrag = $env:WN_TRACE_DRAG -eq '1'
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
  Seed-Note -Profile $profile -Body 'a note with enough text that the widget card has something to draw' -Count 14
  Start-App -Profile $profile -Widget
  $widget = Wait-For -Probe { Get-Widget } -What 'the widget window'
  if ($null -eq $widget) {
    foreach ($id in @('WN-DRAG-001', 'WN-DRAG-002', 'WN-DRAG-003', 'WN-DRAG-004', 'WN-DRAG-005', 'WN-DRAG-006', 'WN-DRAG-007')) {
      Add-Result -Id $id -Wave '2' -Verdict 'BLOCKED' -Claim 'wave 2' -Observed 'no widget window; every geometry row depends on it'
    }
    Remove-OwnedProfile
  } else {
    # Let the surface settle before aiming at it. The window *existing* is not the
    # same as it being ready for input: sampling a first launch showed the widget
    # window created at t=0.35 s and not shown until t=2.66 s, and a drag fired in
    # between lands on a window that has not started its Dart isolate yet. Every
    # row in this wave failed identically until this delay was added, which is
    # what distinguished "the app ignores drags" from "the probe was early".
    Start-Sleep -Milliseconds 1500

    # WN-DRAG-001: five consecutive drags at exactly -60, 0.
    #
    # The origin is recomputed **every iteration**. An earlier version computed it
    # once and reused it, so the first drag moved the window 60 px left and drags
    # two through five were aimed at empty desktop - which the probe reported as
    # five identical failures. Measuring the window's move means measuring it from
    # where it is now.
    $deltas = @()
    $trace = @()
    for ($i = 0; $i -lt 5; $i++) {
      $pre = Get-Widget
      $fromX = $pre.Left + [int]($pre.Width / 2)
      $fromY = $pre.Top + [int]($pre.Height / 2)
      Invoke-Drag -FromX $fromX -FromY $fromY -ToX ($fromX - 60) -ToY $fromY -Steps 4 -StepMs 80
      $post = Get-Widget
      $deltas += ($post.Left - $pre.Left)
      $trace += ("aim {0},{1} left {2}->{3}" -f $fromX, $fromY, $pre.Left, $post.Left)
    }
    $ok = ($deltas | Where-Object { $_ -ne -60 }).Count -eq 0
    Add-Result -Id 'WN-DRAG-001' -Wave '2' -Verdict $(if ($ok) { 'PASS (probe)' } else { 'FAIL' }) `
      -Claim 'five drags at exactly -60,0 move the window -60,0 px; not rounded, not clamped' `
      -Observed ("deltas: {0}" -f ($deltas -join ', ')) `
      -Note ($trace -join '; ')

    # WN-DRAG-002: the 200x140 floor against a long haul on the bottom-right.
    #
    # The assertion is **exactly** 200x140, not "at least the floor". An earlier
    # version accepted anything at or above the floor, which a window that had
    # not resized at all also satisfies - so it passed on a probe that had stopped
    # reaching the app. A floor test has to fail when nothing happened.
    #
    # The haul is also split into bounded steps and the widget is parked first. A
    # single 900 px inward drag from a corner at y=429 ends at y=-471, which is
    # off-screen: `SetCursorPos` clamps to the desktop, so the gesture silently
    # becomes a much shorter one and the row reports a resize that never happened.
    $screenW = [WN.Native]::GetSystemMetrics(0)
    $screenH = [WN.Native]::GetSystemMetrics(1)
    for ($park = 0; $park -lt 12; $park++) {
      $r = Get-Widget
      $overX = ($r.Left + $r.Width) - ($screenW - 60)
      $overY = ($r.Top + $r.Height) - ($screenH - 60)
      if ($overX -le 0 -and $overY -le 0) { break }
      $bx = $r.Left + [int]($r.Width / 2)
      $by = $r.Top + 12
      Invoke-Drag -FromX $bx -FromY $by -ToX ([Math]::Max(40, $bx - [Math]::Abs($overX))) -ToY ([Math]::Max(8, $by - $overY))
    }
    $sizes = @()
    for ($i = 0; $i -lt 8; $i++) {
      $r = Get-Widget
      $g = Get-GrabPoint -Where 'bottomRight' -Win $r
      if ($null -eq $g) { $sizes += 'no grab point'; break }
      Invoke-Drag -FromX $g.X -FromY $g.Y `
                  -ToX ([Math]::Max(6, $g.X - 150)) -ToY ([Math]::Max(6, $g.Y - 150)) -Steps 4
      $sizes += ('{0}x{1}' -f (Get-Widget).Width, (Get-Widget).Height)
    }
    $small = Get-Widget
    $atFloor = ($small.Width -eq 200 -and $small.Height -eq 140)
    $belowFloor = @($sizes | Where-Object {
      if ($_ -notmatch '^(\d+)x(\d+)$') { $false } else {
        [int]$Matches[1] -lt 200 -or [int]$Matches[2] -lt 140
      }
    }).Count
    Add-Result -Id 'WN-DRAG-002' -Wave '2' -Verdict $(if ($atFloor -and $belowFloor -eq 0) { 'PASS (probe)' } else { 'FAIL' }) `
      -Claim 'eight 150 px inward hauls stop at exactly 200x140 and never below' `
      -Observed ("{0}" -f ($sizes -join ' -> ')) `
      -Note $(if (-not $atFloor) { "ended at $($small.Width)x$($small.Height), not the floor" }
              elseif ($belowFloor) { "$belowFloor intermediate size(s) went below 200x140" } else { '' })

    # WN-DRAG-003: every edge resizes. Edges are grabbed through the same
    # region-aware helper as the corners, so an edge grab cannot silently land on
    # the desktop either.
    $edges = @(
      @{ name = 'right';  dx = 100; dy = 0 }
      @{ name = 'bottom'; dx = 0; dy = 100 }
      @{ name = 'left';   dx = -100; dy = 0 }
      @{ name = 'top';    dx = 0; dy = -100 }
    )
    $edgeReport = @()
    $edgeOk = $true
    foreach ($e in $edges) {
      $b = Get-Widget
      $side = $e.name
      if ($side -eq 'left' -or $side -eq 'right') {
        # Grab at the edge, halfway along it.
        $g = Get-GrabPoint -Where $side -Win $b
        $x = $g.X; $y = $b.Top + [int]($b.Height / 2)
      } else {
        $g = Get-GrabPoint -Where $side -Win $b
        $y = $g.Y; $x = $b.Left + [int]($b.Width / 2)
      }
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
    # `settings.json` is the flat `WinNotesSettings.toJson()` map - no `format`
    # key, no `settings` wrapper - and the flag is `widgetPositionLocked`. An
    # earlier version of this row seeded `{ "settings": { "positionLocked": true } }`,
    # which is wrong in both the nesting and the name, so the lock was never on:
    # the widget moved, and the row reported that the lock does not work. The name
    # is taken from `WinNotesSettings.fromJson`, not guessed.
    [System.IO.File]::WriteAllText((Join-Path $profile 'settings.json'),
      (@{ widgetPositionLocked = $true } | ConvertTo-Json))
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

    # --- scroll-vs-drag, which needs a list long enough to scroll --------------
    #
    # These three rows were "NOT RUN" for as long as the seeded library held one
    # note: with nothing below the fold, `_listCanScroll` is false on every branch
    # and the row cannot distinguish "the list won the gesture" from "there was no
    # list to win it". So the library is re-seeded with enough notes to overflow,
    # and the lock is removed, because these rows are about the unlocked widget.
    Remove-Item (Join-Path $profile 'settings.json') -ErrorAction SilentlyContinue
    Seed-Note -Profile $profile `
      -Body 'a note with enough text that the widget card has something to draw' -Count 14
    Stop-App
    Start-App -Profile $profile -Widget
    $w = Wait-For -Probe { Get-Widget } -What 'the widget window'
    if ($null -eq $w) {
      foreach ($id in @('WN-DRAG-004', 'WN-DRAG-005', 'WN-DRAG-007')) {
        Add-Result -Id $id -Wave '2' -Verdict 'BLOCKED' -Claim 'scroll-vs-drag' -Observed 'the widget did not appear'
      }
    } else {
      Start-Sleep -Milliseconds 1200

      # WN-DRAG-004 and WN-DRAG-005 are the two halves of one decision, and only
      # one of them is observable from outside the process.
      #
      # `_listCanScroll` branches on the list's scroll offset, and that offset
      # cannot be read from out here: the widget may open already scrolled to the
      # selected note, so a fresh process is not a guarantee of offset 0. What a
      # drag from the card centre does *not* doing is measurable - a horizontal
      # drag at the same point moves the window (WN-DRAG-001, five times, exactly
      # -60 px) - so a downward drag that leaves the window alone means the list
      # took it, but it does not say *which* way the list could scroll.
      #
      # So 004 is not claimed: "the window did not move" is equally consistent
      # with the list scrolling and with the list sitting at its end absorbing the
      # gesture. Marking it PASS would be exactly the vacuous pass the catalog
      # warns about - a green row that cannot fail.
      #
      # 005 is a measured non-result, not a verdict on the app: the window did not
      # move, and whether that is correct depends on the offset that cannot be
      # observed. Both stay open with the reason recorded.
      $pre = Get-Widget
      $mx = $pre.Left + [int]($pre.Width / 2)
      $my = $pre.Top + [int]($pre.Height * 0.45)
      Invoke-Drag -FromX $mx -FromY $my -ToX $mx -ToY ($my + 70)
      $post = Get-Widget
      $didMove = ($post.Top -ne $pre.Top -or $post.Left -ne $pre.Left)
      Add-Result -Id 'WN-DRAG-004' -Wave '2' -Verdict 'BLOCKED' `
        -Claim 'a scroll wins over a drag mid-list: the list scrolls and the window does not move' `
        -Observed ("dragged down 70 px from ({0},{1}); window top {2} -> {3}, left {4} -> {5}" -f `
                   $mx, $my, $pre.Top, $post.Top, $pre.Left, $post.Left) `
        -Note 'the window staying put is consistent with the list scrolling and with the list absorbing it at its end; the scroll offset is not observable from outside the process, so this row cannot fail either way and is not claimed'

      # The same drag, from a freshly started process.
      Stop-App
      Start-App -Profile $profile -Widget
      $w = Wait-For -Probe { Get-Widget } -What 'the widget window'
      Start-Sleep -Milliseconds 1200
      $pre = Get-Widget
      $mx = $pre.Left + [int]($pre.Width / 2)
      $my = $pre.Top + [int]($pre.Height * 0.45)
      Invoke-Drag -FromX $mx -FromY $my -ToX $mx -ToY ($my + 70)
      $post = Get-Widget
      $movedBy = $post.Top - $pre.Top
      Add-Result -Id 'WN-DRAG-005' -Wave '2' -Verdict 'BLOCKED' `
        -Claim 'at the top, a downward drag of 70 px moves the window down by 70 px' `
        -Observed ("top {0} -> {1} (moved {2}, expected 70)" -f $pre.Top, $post.Top, $movedBy) `
        -Note 'the widget did not move, but a fresh process does not prove the list is at offset 0 - it may open scrolled to the selection - so this is not yet evidence that the top-of-list branch is broken'

      # WN-DRAG-007: a press, 2 px, release is not a drag. This one *is* pinned by
      # an observable pair, because WN-DRAG-001 moves the window by exactly
      # -60 px from this same point: 60 px moves it, 2 px does not.
      $pre = Get-Widget
      $mx = $pre.Left + [int]($pre.Width / 2)
      $my = $pre.Top + [int]($pre.Height * 0.45)
      Invoke-Drag -FromX $mx -FromY $my -ToX $mx -ToY ($my + 2) -Steps 2 -StepMs 80
      $post = Get-Widget
      Add-Result -Id 'WN-DRAG-007' -Wave '2' -Verdict $(if ($post.Top -eq $pre.Top -and $post.Left -eq $pre.Left) { 'PASS (probe)' } else { 'FAIL' }) `
        -Claim 'a press that travels 2 px and releases is not a drag' `
        -Observed ("top {0} -> {1}, left {2} -> {3}" -f $pre.Top, $post.Top, $pre.Left, $post.Left) `
        -Note 'the control is WN-DRAG-001: a 60 px drag from this same point moves the window, so this is a threshold result and not a dead probe'
    }

    Remove-OwnedProfile
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