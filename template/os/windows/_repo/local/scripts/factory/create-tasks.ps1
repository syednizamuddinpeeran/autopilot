# HUMAN-ONLY: create the sub-tasks of a breakdown the planner proposed, after you reviewed it, and
# commit them on the base branch. PowerShell counterpart of create-tasks.sh.
#   pwsh scripts/factory/create-tasks.ps1 .agent-work/breakdowns/<task-id>.md [-Yes]
# Validates the breakdown (check-breakdown.ps1), shows every item, asks for confirmation, then writes
# tasks/<parent>.<n>.md for each item, adds "Broken down into" to the parent task, and commits.
param([Parameter(Mandatory, Position = 0)][string]$Breakdown, [switch]$Yes)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Breakdown)) { throw "not found: $Breakdown" }
$Breakdown = (Resolve-Path -LiteralPath $Breakdown).Path
$root = (git rev-parse --show-toplevel)
Set-Location -LiteralPath $root
. (Join-Path $root '.github/hooks/scripts/common.ps1')
$cfg = Read-FactoryEnvFile (Join-Path $root 'scripts/factory/commands.env')
$base = if ($cfg['BASE_BRANCH']) { $cfg['BASE_BRANCH'] } else { 'main' }

$parent = ''
foreach ($l in (Get-Content -LiteralPath $Breakdown -TotalCount 3)) {
  if ($l -cmatch '^# Breakdown of task ([a-z0-9][a-z0-9._-]*):') { $parent = $Matches[1]; break }
}
if (-not $parent) { [Console]::Error.WriteLine("The breakdown title must be '# Breakdown of task <id>: <title>'."); exit 4 }
if (-not (Test-Path -LiteralPath "tasks/$parent.md")) { throw "Parent task tasks/$parent.md not found." }
if ((git branch --show-current) -ne $base) { throw "Check out '$base' first." }
if (git status --porcelain -- tasks) { throw 'tasks/ has uncommitted changes; commit or stash them first.' }

$brief = $Breakdown -replace '\.md$', '.brief.md'
$checkArgs = @($Breakdown) + $(if (Test-Path -LiteralPath $brief) { @($brief) } else { $brief = ''; @() })
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('tasks-' + [guid]::NewGuid())
try {
  $items = Join-Path $tmp 'items'
  & pwsh -NoProfile -File scripts/factory/check-breakdown.ps1 @checkArgs --split $items
  if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine('Fix the breakdown, then run again.'); exit 4 }
  if (-not $brief) { Write-Output "(No parent brief next to the breakdown: acceptance-criteria coverage was not checked — compare with tasks/$parent.md yourself.)" }

  $order = @(Get-Content -LiteralPath (Join-Path $items 'order') | Where-Object { $_ })
  foreach ($i in $order) { if (Test-Path -LiteralPath "tasks/$parent.$i.md") { throw "tasks/$parent.$i.md already exists: this breakdown was created before." } }
  Write-Output ''
  Write-Output "──────── Sub-tasks of $parent"
  foreach ($i in $order) { Write-Output ''; Write-Output "── tasks/$parent.$i.md"; Get-Content -LiteralPath (Join-Path $items "$i.md") }
  Write-Output '────────'
  if (-not $Yes) {
    if ([Console]::IsInputRedirected) { [Console]::Error.WriteLine('Not a terminal: pass -Yes after reviewing the breakdown.'); exit 1 }
    $ans = Read-Host "Create and commit $($order.Count) sub-tasks of '$parent' on '$base'? [y/N]"
    if ($ans -notin 'y', 'Y') { Write-Output 'Not created.'; exit 0 }
  }

  $list = ''
  foreach ($i in $order) {
    $f = "tasks/$parent.$i.md"
    $lines = @(Get-Content -LiteralPath (Join-Path $items "$i.md"))
    $out = @($lines[0], '', "Parent: $parent")
    foreach ($l in ($lines | Select-Object -Skip 1)) {
      if ($l -match '^Depends on:') { $l = $l -replace 'Item ([0-9]+)', "$parent.`$1" }
      $out += $l
    }
    [System.IO.File]::WriteAllText((Join-Path $root $f), (($out -join "`n") + "`n"))
    git add $f
    $list += "- ${parent}.${i}: $($lines[0] -replace '^# ', '')"
    $deps = @(Get-Content -LiteralPath (Join-Path $items "$i.deps") | Where-Object { $_ })
    if ($deps) { $list += " (after $(($deps | ForEach-Object { "$parent.$_" }) -join ' '))" }
    $list += "`n"
  }
  [System.IO.File]::AppendAllText((Join-Path $root "tasks/$parent.md"), "`n## Broken down into`n$list")
  git add "tasks/$parent.md"
  git commit -q -m "task: breakdown of $parent into $($order.Count) sub-tasks" -- tasks
  if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
  Write-Output "Committed $($order.Count) sub-tasks of '$parent' on '$base':"
  Write-Output $list.TrimEnd("`n")
  Write-Output 'Run them in dependency order with pwsh scripts/factory/run-task.ps1 <id>.'
} finally {
  Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}
