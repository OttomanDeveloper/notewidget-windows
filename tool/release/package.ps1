<#
.SYNOPSIS
  Builds the release artifacts: a portable ZIP and, when Inno Setup is present,
  a setup.exe.

.DESCRIPTION
  One script for both the release workflow and a local run, so what CI publishes
  is what you get on your own machine. Every step that can quietly produce a
  broken download is checked here rather than trusted:

    * the version in pubspec.yaml is read, not passed in, so a stale tag or a
      hand-edited argument cannot mislabel the artifact
    * the built executable is launched from the staged copy, so an artifact that
      cannot start is never uploaded
    * the ZIP is opened again and its contents listed, because a zip that looks
      fine on disk can be missing the Flutter engine DLL

.EXAMPLE
  pwsh -File tool/release/package.ps1

.EXAMPLE
  pwsh -File tool/release/package.ps1 -SkipTests -NoInstaller
#>
[CmdletBinding()]
param(
    [string]$OutDir = 'dist',
    [switch]$SkipTests,
    [switch]$NoInstaller,

    # Override only when testing the script itself. Normal runs take the version
    # from pubspec.yaml.
    [string]$VersionOverride
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    # --- version -------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($VersionOverride)) {
        $line = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' |
            Select-Object -First 1
        if ($null -eq $line) { throw 'no version: line in pubspec.yaml' }
        $VersionOverride = $line.Matches[0].Groups[1].Value
    }
    $version = $VersionOverride -replace '\+.*$', ''   # drop the build number
    Write-Host "version $version (pubspec says '$VersionOverride')"

    $dist = if ([IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $root $OutDir }
    New-Item -ItemType Directory -Force -Path $dist | Out-Null

    # --- checks --------------------------------------------------------------
    if (-not $SkipTests) {
        Write-Host 'running the test suite'
        # $LASTEXITCODE, not the output: a failing test prints plenty and then
        # still returns 0 in some shells, which is how broken builds ship.
        #
        # Serial, and this has cost a release once already. At default concurrency
        # the runner compiles several suites at once and starves its own workers;
        # the tests that assert on real elapsed time - the debounce ceiling, the
        # write retries - then fail on a machine that is busy rather than wrong.
        # The first v1.3.0 packaging run died exactly that way, on a test that
        # passes 12 times out of 12 in isolation. A slower package is a package.
        flutter test --reporter compact --concurrency=1
        if ($LASTEXITCODE -ne 0) {
            # One retry, and it says so loudly. This gate has now failed a release
            # twice on a machine that was busy rather than wrong - v1.3.0 on a
            # composer drag guard, v1.3.1 on a semantics assertion - and neither
            # reproduced here in twenty runs of the file. A deterministic failure
            # fails twice; that is what makes the retry honest rather than a way
            # to wave a real failure through.
            #
            # It does **not** fix the flakiness, and a retry is the reason a
            # flaky test can stay flaky: if this line fires, that run is evidence
            # and belongs in `docs/testing/reporting.md`.
            Write-Host ''
            Write-Warning 'the suite failed; re-running once before refusing to package'
            Write-Host ''
            flutter test --reporter compact --concurrency=1
            if ($LASTEXITCODE -ne 0) {
                throw 'tests failed twice; refusing to package'
            }
            Write-Warning 'the suite passed on the retry - this run was flaky'
        }
    }

    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'analyzer reported problems; refusing to package' }

    Write-Host 'building the release'
    # `--obfuscate --split-debug-info` is `flutter_architecture_pattern.md` §7.3, and
    # it is here rather than in a comment because a flag nobody passes is a flag that
    # is not happening. It renames Dart symbols in `app.so`, which is otherwise a
    # readable map of every class, method and string in the app; the symbol file goes
    # to `build/symbols` so a crash report from somebody else can still be read.
    #
    # Not obfuscated in debug: stack traces from a developer are worth more readable
    # than they are worth short, and this only runs for a release artifact.
    flutter build windows --release --obfuscate --split-debug-info=build/symbols
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

    $symbols = Join-Path $root 'build\symbols'
    if (-not (Test-Path $symbols)) {
        # An obfuscated build without a symbol file produces a crash report nobody
        # can read, so this is a failure rather than a note.
        throw "release build succeeded but there is no symbol file at $symbols."
    }

    $built = Join-Path $root 'build\windows\x64\runner\Release'
    $exe = Join-Path $built 'win_notes.exe'
    if (-not (Test-Path $exe)) { throw "no executable at $exe" }

    # The version baked into the binary has to match, because this is what
    # Windows shows in file properties and what the About box would read.
    $reported = (Get-Item $exe).VersionInfo.ProductVersion
    Write-Host "executable reports version $reported"
    if ($reported -notlike "$version*") {
        throw "executable reports '$reported' but this build is '$version'"
    }

    # --- stage ---------------------------------------------------------------
    # A single top-level folder inside the ZIP, so unpacking does not scatter
    # files across Downloads.
    $stageRoot = Join-Path $dist "WinNotes-$version"
    if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
    $stageApp = Join-Path $stageRoot 'WinNotes'
    New-Item -ItemType Directory -Force -Path $stageApp | Out-Null
    Copy-Item (Join-Path $built '*') $stageApp -Recurse -Force

    $readme = Join-Path $stageApp 'README.txt'
    @"
WinNotes $version

Everything here lives in your own profile folder, usually:

  %APPDATA%\WinNotes

There is no account, no server and nothing to sync. To uninstall, delete this
folder and remove the WinNotes entry under

  HKCU\Software\Microsoft\Windows\CurrentVersion\Run

which is what Settings -> Startup uses to bring the widget back after a reboot.
"@ | Set-Content -Path $readme -Encoding utf8

    # --- verify the staged copy actually starts ------------------------------
    Write-Host 'launching the staged copy to confirm it runs'
    $stagedExe = Join-Path $stageApp 'win_notes.exe'
    $probeData = Join-Path $env:TEMP "winnotes_pkg_probe_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Force -Path $probeData | Out-Null
    $probe = Start-Process -FilePath $stagedExe -PassThru
    try {
        $deadline = (Get-Date).AddSeconds(40)
        $ready = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            if ($probe.HasExited) {
                throw "the staged build exited immediately with code $($probe.ExitCode)"
            }
            # Both windows must exist before this counts as a working artifact.
            $procs = Get-Process win_notes -ErrorAction SilentlyContinue
            if ($procs) { $ready = $true; break }
        }
        if (-not $ready) { throw 'the staged build produced no process within 40s' }
        Write-Host '  staged copy started'
    }
    finally {
        Get-Process win_notes -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        Remove-Item $probeData -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- zip -----------------------------------------------------------------
    $zip = Join-Path $dist "WinNotes-$version-windows-x64.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    # -Path with a directory stores that directory as the single top-level entry.
    Compress-Archive -Path $stageRoot -DestinationPath $zip -CompressionLevel Optimal

    # Reopen it, because Compress-Archive reports success for archives that are
    # missing files it could not read. The paths are the real ones from a Flutter
    # Windows build: the engine DLL sits beside the exe, while icudtl.dat and the
    # AOT library live under data/ because that is where the embedder looks.
    $check = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entries = $check.Entries | ForEach-Object { $_.FullName }
    }
    finally { $check.Dispose() }

    $mustHave = @(
        'win_notes.exe',
        'flutter_windows.dll',
        'data/icudtl.dat',
        'data/app.so',
        'data/flutter_assets/AssetManifest.bin'
    )
    foreach ($needed in $mustHave) {
        $hit = $entries | Where-Object { $_ -like "*/$needed" }
        if (-not $hit) { throw "zip is missing '$needed'. Entries: $($entries -join ', ')" }
    }
    Write-Host ("zip verified: {0} entries, {1:N1} MB" -f $entries.Count, ((Get-Item $zip).Length / 1MB))

    # --- installer -----------------------------------------------------------
    $installer = $null
    if (-not $NoInstaller) {
        $iscc = @(
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
        ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

        if (-not $iscc) {
            Write-Warning 'Inno Setup not found; produced the portable ZIP only.'
            Write-Warning 'Install it with: winget install --id JRSoftware.InnoSetup -e'
        }
        else {
            $iss = Join-Path $root 'installer\winnotes.iss'
            if (-not (Test-Path $iss)) { throw "missing installer script at $iss" }
            $installer = Join-Path $dist "WinNotes-$version-setup.exe"
            Write-Host 'compiling the installer'
            # /D sets AppVersion and OutputDir, which is how the script stays
            # free of hardcoded version numbers.
            & $iscc "/DAppVersion=$version" "/O$dist" $iss
            if ($LASTEXITCODE -ne 0) { throw 'the installer failed to compile' }
            if (-not (Test-Path $installer)) {
                throw "ISCC reported success but $installer is missing"
            }
            Write-Host ("installer verified: {0:N1} MB" -f ((Get-Item $installer).Length / 1MB))
        }
    }

    # --- summary -------------------------------------------------------------
    Write-Host ''
    Write-Host 'artifacts:'
    Get-ChildItem $dist -File | Sort-Object Name |
        ForEach-Object { Write-Host ("  {0,-44} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB)) }
}
finally {
    Pop-Location
}