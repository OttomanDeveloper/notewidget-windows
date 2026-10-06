<#
.SYNOPSIS
  The gate. One command that runs every check this repository has.

.DESCRIPTION
  This file exists because "did you run everything" was tribal knowledge. There
  were three verify scripts and one check script, run in a specific order that
  only existed in one session's head - and the order matters, because each stage
  assumes the one before it passed:

    Caps      the size and privacy rules. Needs no Dart VM, so it runs first and
              fails in under a second on the mistake you are about to make 400
              times in an editor.
    Analyze   static errors. Needs no build.
    Test      the suite, and the architecture guards inside it.
    Build     the release binary. This is the only stage that compiles C++, so
              it is where runner breakage shows up - the Dart tests never link
              Win32.
    Release   drives that binary through a first launch against a throw-away
              profile. The only stage that runs the app.
    Icons     reads the icon out of the built exe and installer. Needs Build's
              output, and checks four places rather than one.

  Every stage prints a heading and a verdict. The script's exit code is 1 if any
  stage failed, 0 otherwise, so CI and a person get the same answer.

  What this gate does NOT establish, and what no stage of it can:
  `docs/testing_pattern.md` §2 Tier C and Tier D. Drag arithmetic, acrylic, the
  tray, the global hotkey, autostart, single-instance and multi-monitor are
  verified by hand or by a probe, not here. A green gate is a floor.

.EXAMPLE
  pwsh -File tool\verify\verify.ps1

.EXAMPLE
  pwsh -File tool\verify\verify.ps1 -Action Test

.EXAMPLE
  pwsh -File tool\verify\verify.ps1 -Action All -Skip Release
#>
[CmdletBinding()]
param(
  # What to run. `All` is every stage in order.
  [ValidateSet('All', 'Caps', 'Analyze', 'Test', 'Random', 'Build', 'Release', 'Icons')]
  [string] $Action = 'All',
  # Stages to skip, so a long stage can be left out of a quick pass. Naming one
  # is a decision, so it is printed in the summary. Comma-separated, because
  # `powershell -File` hands `-Skip Icons,Random` over as the *single* string
  # `Icons,Random`, which is why the split below is not optional.
  [string[]] $Skip = @()
)

$ErrorActionPreference = 'Continue'

# tool\verify\ -> tool\ -> repo. Two levels, not three: this file is two
# directories deep, and the third one lands in the parent of the repository.
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repo

# `flutter` is on PATH for a person; on a GitHub runner it is whatever
# `subosito/flutter-action` installed, and each `run` is a fresh shell.
# Resolving it once, here, is what makes the two runs of this script identical.
if ($null -eq (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'flutter is not on PATH. On CI, `subosito/flutter-action` puts it ' +
    'there; locally, add %FLUTTER_HOME%\bin to PATH.'
}

# --- stage running ----------------------------------------------------------

$script:results = @()

function Invoke-Stage {
  param(
    [string] $Name,
    # Untyped on purpose: annotating this `[string]` stringifies the scriptblock
    # and the stage silently passes without running anything.
    $Command,
    [string] $Why
  )

  Write-Host ''
  Write-Host "=== $Name ==="
  Write-Host "    $Why"

  $started = Get-Date
  # A stage that throws must fail the gate, not print PASS: the exception is
  # caught below and turned into a non-zero exit.
  try {
    & $Command
    $code = $LASTEXITCODE
  } catch {
    Write-Host "    $($_.Exception.Message)"
    $code = 1
  }
  $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)

  if ($null -eq $code) { $code = 0 }
  $ok = ($code -eq 0)
  $script:results += [pscustomobject]@{
    Stage = $Name
    Ok = $ok
    Seconds = $elapsed
    Exit = $code
  }

  if ($ok) {
    Write-Host ("    PASS  {0}  ({1}s)" -f $Name, $elapsed)
  } else {
    Write-Host ("    FAIL  {0}  (exit {1}, {2}s)" -f $Name, $code, $elapsed)
  }
  # No return value: a stage's result is in the summary, and a function that both
  # prints and returns puts `True` into the caller's output stream, which is how
  # the first version of this printed a stray `True` under every stage.
}

function Invoke-StageScript {
  param(
    [string] $Name,
    [string] $Path,
    [string] $Why
  )
  # Resolved against the repo root before the child process sees it: the child's
  # working directory is not ours, and a relative path that resolves in ours and
  # not in theirs is a stage that fails for the wrong reason.
  $full = Join-Path $repo $Path
  Invoke-Stage -Name $Name -Why $Why -Command {
    powershell -NoProfile -ExecutionPolicy Bypass -File $full
  }
}

# --- the stages -------------------------------------------------------------

$all = [ordered]@{
  Caps = {
    Invoke-StageScript -Name 'Caps' -Path 'tool\check_architecture.ps1' `
      -Why 'file size and widget privacy rules; no Dart VM, so it is first'
  }
  Analyze = {
    Invoke-Stage -Name 'Analyze' -Command { flutter analyze } `
      -Why 'static errors and lints'
  }
  Test = {
    Invoke-Stage -Name 'Test' -Command { flutter test } `
      -Why 'the suite, and the architecture guards inside it'
  }
  Random = {
    # The suite has order-dependent behaviour: temp directories, a directory
    # watcher, and a debounce that measures real elapsed time. Running the files
    # in a shuffled order is the cheapest way to find a test that only passes
    # because something else ran first.
    Invoke-Stage -Name 'Random' -Command {
      $files = Get-ChildItem test -Recurse -Filter *_test.dart |
        Sort-Object { Get-Random }
      flutter test @($files.FullName)
    } -Why 'the suite in randomised order; hunts order-dependent flakes'
  }
  Build = {
    # LNK1104 if the app is running from this directory. Stopping it here rather
    # than failing: a build that fails because you have the app open is a build
    # you did not get to run.
    Get-Process -Name win_notes -ErrorAction SilentlyContinue |
      ForEach-Object { Stop-Process -Id $_.Id -Force }
    Invoke-Stage -Name 'Build' `
      -Command { flutter build windows --release } `
      -Why 'the release binary, and the only stage that compiles C++'
  }
  Release = {
    Invoke-StageScript -Name 'Release' -Path 'tool\verify\verify_release.ps1' `
      -Why 'drives the release build through a first launch against %TEMP%'
  }
  Icons = {
    Invoke-StageScript -Name 'Icons' -Path 'tool\verify\verify_icons.ps1' `
      -Why 'the icon in all four places Windows reads it from'
  }
}

# The order is the dependency order, and `Random` is a second pass over `Test`
# rather than a stage of its own.
$order = @('Caps', 'Analyze', 'Test', 'Random', 'Build', 'Release', 'Icons')

$stages = if ($Action -eq 'All') { $order } else { @($Action) }

# One element per stage, whether it arrived as `-Skip Icons -Skip Random` or as
# the single string `-Skip Icons,Random`. An unknown name is an error rather
# than a no-op: silently skipping nothing because of a typo is how a stage gets
# believed to have run when it did not.
$skipping = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } |
  Where-Object { $_ })
foreach ($name in $skipping) {
  if ($order -notcontains $name) {
    throw "cannot skip '$name': the stages are $($order -join ', ')"
  }
}

foreach ($name in $stages) {
  if ($skipping -contains $name) { continue }
  & $all[$name]
}

# --- summary ----------------------------------------------------------------

Write-Host ''
Write-Host '=== summary ==='
foreach ($r in $script:results) {
  $mark = if ($r.Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  {0,-5} {1,-10} {2,6}s  exit {3}" -f $mark, $r.Stage, $r.Seconds, $r.Exit)
}

$failed = @($script:results | Where-Object { -not $_.Ok })
if ($skipping.Count -gt 0) {
  Write-Host ("  SKIP  {0}" -f ($skipping -join ', '))
}

Write-Host ''
if ($failed.Count -gt 0) {
  Write-Host ("FAILED: {0}" -f (($failed | ForEach-Object { $_.Stage }) -join ', '))
  exit 1
}

Write-Host 'All requested stages passed.'
Write-Host 'Not covered here: docs\testing_pattern.md Tier C and Tier D.'
exit 0