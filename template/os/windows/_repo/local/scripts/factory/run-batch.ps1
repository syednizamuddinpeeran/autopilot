# Run the sub-tasks of a broken-down task (create-tasks.ps1), in dependency order, several at a time.
# PowerShell counterpart of run-batch.sh.
#
#   pwsh scripts/factory/run-batch.ps1 <parent-id>                  # run every sub-task that is ready now
#   pwsh scripts/factory/run-batch.ps1 <parent-id> -AutoContinue    # …then keep going as you merge them
#   pwsh scripts/factory/run-batch.ps1 <parent-id> -List            # show the state of each sub-task only
#   options: -Parallel <n> (default: MAX_PARALLEL in complexity.env)
#
# A sub-task is ready when every task on its "Depends on:" line was merged with accept.ps1. Each runs
# as its own run-task.ps1 in its own worktree; output goes to .agent-logs/batch/<id>.log.
# -AutoContinue waits for your merges (every BATCH_POLL_SECONDS, default 60) and starts what they
# unblock. Merging stays a human step.
# Exit codes: 0 every run it started finished, 1 a run failed or stopped, 2 no sub-tasks found.
param([Parameter(Position = 0)][string]$Parent, [switch]$AutoContinue, [switch]$List, [int]$Parallel)
$ErrorActionPreference = 'Stop'
if (-not $Parent) { [Console]::Error.WriteLine('usage: run-batch.ps1 <parent-task-id> [-AutoContinue] [-List] [-Parallel <n>]'); exit 2 }
$root = (git rev-parse --show-toplevel)
Set-Location -LiteralPath $root
. (Join-Path $root '.github/hooks/scripts/common.ps1')
$cfg = Read-FactoryEnvFile (Join-Path $root 'scripts/factory/commands.env')
$limits = Read-FactoryEnvFile (Join-Path $root 'scripts/factory/complexity.env')
$base = if ($cfg['BASE_BRANCH']) { $cfg['BASE_BRANCH'] } else { 'main' }
if (-not $Parallel) { $Parallel = if ($limits['MAX_PARALLEL']) { [int]($limits['MAX_PARALLEL']) } else { 3 } }
if ($Parallel -lt 1) { throw '-Parallel must be a positive number' }
$poll = if ($env:BATCH_POLL_SECONDS) { [int]$env:BATCH_POLL_SECONDS } else { 60 }
$stagger = if ($null -ne $env:BATCH_STAGGER_SECONDS) { [int]$env:BATCH_STAGGER_SECONDS } else { 2 }
$logs = Join-Path $root '.agent-logs/batch'; New-Item -ItemType Directory -Force -Path $logs | Out-Null

$pattern = '^tasks/(' + [regex]::Escape($Parent) + '\.[0-9]+)\.md$'
$subs = @(git ls-tree --name-only $base tasks/ | Where-Object { $_ -match $pattern } | ForEach-Object { $Matches[1] } |
  Sort-Object { [int](($_ -split '\.')[-1]) })
if (-not $subs) { [Console]::Error.WriteLine("No sub-tasks tasks/$Parent.<n>.md on '$base'. Create them with create-tasks.ps1."); exit 2 }

function Test-Merged([string]$id) { @(git log --format=%s $base) -ccontains "merge: $id" }
function Get-Deps([string]$id) {
  $line = @(git show "${base}:tasks/$id.md" | Where-Object { $_ -match '^Depends on:' }) | Select-Object -First 1
  if (-not $line) { return @() }
  @([regex]::Matches(($line -replace '^Depends on:\s*', ''), '[a-z0-9][a-z0-9._-]*[0-9]') | ForEach-Object { $_.Value })
}
$procs = @{}; $rc = @{}
function Get-State([string]$id) {
  if (Test-Merged $id) { return 'merged' }
  if ($procs.ContainsKey($id)) { return 'running' }
  if ($rc.ContainsKey($id) -and $rc[$id] -ne 0) { return 'stopped' }
  git rev-parse --verify --quiet "refs/heads/agent/$id" | Out-Null
  if ($LASTEXITCODE -eq 0) { if ([int](git rev-list --count "$base..agent/$id") -gt 0) { return 'review' } else { return 'stopped' } }
  foreach ($d in Get-Deps $id) { if (-not (Test-Merged $d)) { return 'blocked' } }
  'ready'
}
function Show-State {
  Write-Output "Sub-tasks of ${Parent}:"
  foreach ($id in $subs) {
    $s = Get-State $id
    $text = switch ($s) {
      'merged'  { 'merged' }
      'running' { "running (log: .agent-logs/batch/$id.log)" }
      'review'  { "waiting for your review: pwsh scripts/factory/accept.ps1 $id" }
      'stopped' { "needs you: see .agent-logs/batch/$id.log (questions, breakdown or failure)" }
      'blocked' { "blocked by: $((Get-Deps $id | Where-Object { -not (Test-Merged $_) }) -join ' ')" }
      'ready'   { 'ready' }
    }
    Write-Output ('  {0,-24} {1}' -f $id, $text)
  }
}
if ($List) { Show-State; exit 0 }

$failed = 0
while ($true) {
  foreach ($id in @($procs.Keys)) {
    $p = $procs[$id]
    if ($p.HasExited) {
      $p.WaitForExit(); $rc[$id] = $p.ExitCode; $procs.Remove($id)
      if ($rc[$id] -ne 0) { $failed = 1 }
      Write-Output "finished $id (exit $($rc[$id]))"
    }
  }
  foreach ($id in $subs) {
    if ($procs.Count -ge $Parallel) { break }
    if ((Get-State $id) -ne 'ready') { continue }
    Write-Output "start    $id"
    $log = Join-Path $logs "$id.log"
    $p = Start-Process pwsh -NoNewWindow -PassThru -ArgumentList @('-NoProfile', '-Command',
      "& pwsh -NoProfile -File scripts/factory/run-task.ps1 '$id' *> '$log'; exit `$LASTEXITCODE")
    $null = $p.Handle   # keep the handle so ExitCode is available after exit
    $procs[$id] = $p
    Start-Sleep -Seconds $stagger   # let each run create its worktree before the next starts
  }
  if ($procs.Count -gt 0) { Start-Sleep -Seconds 2; continue }

  $states = @($subs | ForEach-Object { Get-State $_ })
  if (-not ($states | Where-Object { $_ -ne 'merged' })) { Write-Output "All sub-tasks of $Parent are merged."; break }
  if (-not $AutoContinue -or -not ($states | Where-Object { $_ -in 'review', 'ready' })) { break }
  Start-Sleep -Seconds $poll
}
Write-Output ''
Show-State
if (-not $AutoContinue) {
  Write-Output ''
  Write-Output 'Review and merge the finished ones (pwsh scripts/factory/accept.ps1 <id>), then run the batch again'
  Write-Output '(or use -AutoContinue to start the next ones as you merge).'
}
exit $failed
