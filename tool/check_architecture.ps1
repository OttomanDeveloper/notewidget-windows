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

$privates = Get-ChildItem lib -Recurse -Filter *.dart | Select-String -Pattern 'class _\w+ extends (StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|CustomPainter)'
foreach ($p in $privates) { Write-Host "private widget: $($p.Path):$($p.LineNumber): $($p.Line.Trim())"; $fail = 1 }

$builds = Get-ChildItem lib -Recurse -Filter *.dart | Select-String -Pattern 'Widget _\w+\('
foreach ($b in $builds) { Write-Host "private build method: $($b.Path):$($b.LineNumber): $($b.Line.Trim())"; $fail = 1 }

exit $fail
