# Rulebook §9, as a PowerShell script (the doc shows bash; this is that).
#
# Run from the project root. Prints NOTHING and exits 0 when the rules are
# respected; lists offenders otherwise. Mirrors `flutter_rules_guard_test`,
# which enforces the same rules inside `flutter test`.
$fail = 0

function CodeOnly([string[]]$lines) {
  $n = 0
  foreach ($l in $lines) {
    $t = $l.TrimStart()
    if ($t -eq '') { continue }
    if ($t.StartsWith('//')) { continue }
    if ($t.StartsWith('import ') -or $t.StartsWith('export ') -or $t -eq 'library;') { continue }
    $n++
  }
  return $n
}

function CheckCap([string]$dir, [int]$cap, [string]$kind) {
  if (-not (Test-Path $dir)) { return }
  foreach ($f in (Get-ChildItem $dir -Recurse -Filter *.dart)) {
    $n = CodeOnly(Get-Content $f.FullName)
    if ($n -gt $cap) {
      Write-Host "$($f.FullName): $n code-only lines, cap is $cap ($kind)"
      $script:fail = 1
    }
  }
}

foreach ($d in @('lib/features/notes/presentation/screens', 'lib/features/widget/presentation/screens', 'lib/features/settings/presentation/screens')) {
  CheckCap $d 500 'screen'
}
foreach ($d in @('lib/features/notes/presentation/widgets', 'lib/features/widget/presentation/widgets', 'lib/features/settings/presentation/widgets', 'lib/core/widgets')) {
  CheckCap $d 350 'widget'
}
foreach ($d in @('lib/features/notes/presentation/providers', 'lib/features/widget/presentation/providers', 'lib/features/settings/presentation/providers')) {
  CheckCap $d 300 'provider'
}

# §4: the folder is the widget in snake_case, and the file is the folder.
# A private `State`/`ConsumerState` is not a widget (§3.1), so it is skipped.
$widgetBase = '(?:\w*StatelessWidget|\w*StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|CustomPainter)'
Get-ChildItem lib -Recurse -Filter *.dart | ForEach-Object {
  $source = Get-Content $_.FullName -Raw
  $states = [regex]::Matches($source, "class\s+(\w+)\s+extends\s+(?:Consumer)?State<(\w+)>") |
    ForEach-Object { $_.Groups[2].Value }
  $classes = [regex]::Matches($source, "class\s+(\w+)\s+extends\s+$widgetBase\b") |
    ForEach-Object { $_.Groups[1].Value } | Where-Object { $states -notcontains $_ }
  # Only a file holding exactly one widget: with several, the split is the
  # thing to complain about and naming one of them would be a second complaint.
  if (@($classes).Count -ne 1) { return }
  $name = @($classes)[0]
  $snake = ([regex]::Replace($name, '(?<!^)([A-Z])', '_$1')).ToLower()
  $folder = Split-Path (Split-Path $_.FullName -Parent) -Leaf
  $file = $_.BaseName
  if ($folder -ne $snake -or $file -ne $snake) {
    Write-Host "misnamed widget: $($_.FullName): class $name, expected $snake/"
    $fail = 1
  }
}

$privates = Get-ChildItem lib -Recurse -Filter *.dart | Select-String -Pattern 'class _\w+ extends (StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|CustomPainter)'
foreach ($p in $privates) { Write-Host "private widget: $($p.Path):$($p.LineNumber): $($p.Line.Trim())"; $fail = 1 }

$builds = Get-ChildItem lib -Recurse -Filter *.dart | Select-String -Pattern 'Widget _\w+\('
foreach ($b in $builds) { Write-Host "private build method: $($b.Path):$($b.LineNumber): $($b.Line.Trim())"; $fail = 1 }

exit $fail
