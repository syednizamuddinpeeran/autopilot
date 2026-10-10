# HUMAN-ONLY: review and merge an agent branch into the base branch, locally (Windows).
# PowerShell counterpart of accept.sh; replaces "CI + branch protection + merge button".
#
#   pwsh scripts/factory/accept.ps1 add-csv-export                      # verify, then merge --no-ff
#   pwsh scripts/factory/accept.ps1 add-csv-export -AllowGuardrails     # you reviewed guardrail edits
#
# Run it from the main checkout (base branch checked out, clean tree). Agents are denied this
# script by the guard hook.
param([Parameter(Mandatory)][string]$Task, [switch]$AllowGuardrails)
$ErrorActionPreference = 'Stop'
$root = (git rev-parse --show-toplevel)
Set-Location -LiteralPath $root
. (Join-Path $root '.github/hooks/scripts/common.ps1')
$cfg = Read-FactoryEnvFile (Join-Path $root 'scripts/factory/commands.env')
$base = if ($cfg['BASE_BRANCH']) { $cfg['BASE_BRANCH'] } else { 'main' }
$branch = "agent/$Task"
$repoName = Split-Path -Leaf $root
$wtRoot = if ($env:FACTORY_WORKTREE_ROOT) { $env:FACTORY_WORKTREE_ROOT } else { Join-Path (Split-Path -Parent $root) "$repoName-worktrees" }
$wt = Join-Path $wtRoot $Task

if ((git branch --show-current) -ne $base) { throw "Check out '$base' first." }
if (git status --porcelain) { throw 'Working tree is not clean.' }
git rev-parse --verify --quiet "refs/heads/$branch" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "No branch $branch" }

Write-Output "── commits on $branch"; git log --oneline "$base..$branch"
Write-Output '── files changed';     git diff --stat "$base...$branch"

# 1. Guardrails unchanged.
$guardChanges = git diff --name-only "$base...$branch" -- .github scripts/factory tasks AGENTS.md install.sh install.ps1
if ($guardChanges -and -not $AllowGuardrails) {
  [Console]::Error.WriteLine("Branch modifies guardrail files (review them, then re-run with -AllowGuardrails):`n$($guardChanges -join "`n")")
  exit 1
}

# 2. Verify the branch from its own worktree (or a temporary one), using the BASE's guardrails.
$tmp = $null
if (Test-Path -LiteralPath $wt) { $dir = $wt }
else {
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("factory-accept-" + [guid]::NewGuid())
  git worktree add --detach -q $tmp $branch
  $dir = $tmp
}
try {
  Push-Location -LiteralPath $dir
  & pwsh -NoProfile -File scripts/factory/setup.ps1; if ($LASTEXITCODE -ne 0) { throw 'setup.ps1 failed' }
  & pwsh -NoProfile -File scripts/factory/check.ps1; if ($LASTEXITCODE -ne 0) { throw 'check.ps1 failed' }
  Pop-Location
  & pwsh -NoProfile -File scripts/factory/test-hooks.ps1; if ($LASTEXITCODE -ne 0) { throw 'test-hooks.ps1 failed' }

  # 3. Merge.
  $ans = Read-Host "Merge $branch into $base? [y/N]"
  if ($ans -notin 'y', 'Y') { Write-Output 'Not merged.'; exit 0 }
  git merge --no-ff $branch -m "merge: $Task"
  if ($LASTEXITCODE -ne 0) { throw 'git merge failed' }
  Write-Output "Merged. Clean up with: git worktree remove '$wt'; git branch -d '$branch'"
} finally {
  if ((Get-Location).Path -ne $root) { Set-Location -LiteralPath $root }
  if ($tmp) { git worktree remove --force $tmp 2>$null | Out-Null }
}
