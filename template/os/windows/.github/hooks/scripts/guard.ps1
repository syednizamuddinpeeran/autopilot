# preToolUse guard for Windows (PowerShell 7+). Same policy files and decisions as guard.sh.
#
# Output contract (Copilot hooks): print ONE JSON object, or nothing.
#   deny  -> {"permissionDecision":"deny","permissionDecisionReason":"..."}
#   allow -> print nothing (fall through to normal permissions)
# A crash or non-zero exit DENIES the call (fail-closed). A timeout ALLOWS it (fail-open),
# so keep this script fast.
$ErrorActionPreference = 'Stop'
try {
  . (Join-Path $PSScriptRoot 'common.ps1')

  $root = (Get-FactoryRoot) -replace '\\', '/'
  $policyDir = if ($env:FACTORY_POLICY_DIR) { $env:FACTORY_POLICY_DIR } else { Join-Path $root '.github/hooks/policy' }

  $payloadJson = [Console]::In.ReadToEnd()
  Set-FactoryContext
  $payload = ConvertFrom-FactoryJson $payloadJson
  if ($payload -isnot [System.Collections.IDictionary]) { exit 2 }

  $tool = ''
  foreach ($k in 'toolName', 'tool_name') { if ($payload.Contains($k) -and $payload[$k]) { $tool = [string]$payload[$k]; break } }
  $toolArgs = @{}
  foreach ($k in 'toolArgs', 'tool_input') {
    if ($payload.Contains($k) -and $null -ne $payload[$k]) { $toolArgs = $payload[$k]; break }
  }
  if ($toolArgs -is [string]) {
    try { $toolArgs = ConvertFrom-FactoryJson $toolArgs } catch { $toolArgs = @{ raw = $toolArgs } }
    if ($toolArgs -isnot [System.Collections.IDictionary]) { $toolArgs = @{ raw = [string]$toolArgs } }
  }
  $argsJson = $toolArgs | ConvertTo-Json -Compress -Depth 100
} catch { exit 2 }

function Deny([string]$Reason) {
  try { Write-FactoryLog 'preToolUse' $payloadJson @{ decision = 'deny'; reason = $Reason } } catch { }
  $msg = "Blocked by factory guard: $Reason. Do not retry this action or work around it; choose a safe alternative or record it as a follow-up in the PR or handoff."
  [ordered]@{ permissionDecision = 'deny'; permissionDecisionReason = $msg } | ConvertTo-Json -Compress
  exit 0
}

function Allow {
  try { Write-FactoryLog 'preToolUse' $payloadJson @{ decision = 'allow' } } catch { }
  exit 0
}

# Regex lines from a policy file, skipping comments/blank lines.
function Get-Patterns([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  return @(Get-Content -LiteralPath $Path | Where-Object { $_ -notmatch '^\s*(#|$)' })
}

# POSIX classes used in some policy lines → .NET equivalents.
function ConvertTo-NetRegex([string]$Pattern) {
  return ($Pattern -replace '\[\[:space:\]\]', '\s' -replace '\[:space:\]', '\s')
}

function Get-CurrentBranch { $b = git -C $root branch --show-current 2>$null; if ($b) { return [string]$b } else { return '' } }

# ---------- shell commands ----------
function Test-Shell {
  $cmd = ''
  foreach ($k in 'command', 'cmd', 'script', 'input', 'raw') {
    if ($toolArgs.Contains($k) -and $toolArgs[$k]) { $cmd = [string]$toolArgs[$k]; break }
  }
  if (-not $cmd) { $cmd = $argsJson }
  $norm = ($cmd -replace '[\r\n\t]', ' ') -replace ' {2,}', ' '

  foreach ($pat in Get-Patterns (Join-Path $policyDir 'deny-commands.txt')) {
    if ($norm -match (ConvertTo-NetRegex $pat)) { Deny "command matches denied pattern [$pat]" }
  }

  $rules = Read-FactoryEnvFile (Join-Path $policyDir 'git-rules.env')
  $prefixes = if ($env:FACTORY_BRANCH_PREFIXES) { $env:FACTORY_BRANCH_PREFIXES } elseif ($rules['BRANCH_PREFIXES']) { $rules['BRANCH_PREFIXES'] } else { 'agent/' }
  $branchOnly = [string]$rules['BRANCH_ONLY_GIT']

  # Some git subcommands (push, or commit/merge for local repos) only on agent branches.
  if ($branchOnly -and $norm -cmatch "(^|[;&|\s])git\s+(-C\s+\S+\s+)?($branchOnly)\b") {
    $cur = Get-CurrentBranch
    $ok = $false
    foreach ($p in ($prefixes -split '\s+' | Where-Object { $_ })) { if ($cur.StartsWith($p)) { $ok = $true } }
    if (-not $ok) { Deny "git $branchOnly is only allowed on branches starting with: $prefixes (current: $(if ($cur) { $cur } else { 'detached' }))" }
  }

  # Any explicit git push refspec must name the current branch or HEAD.
  if ($rules['PUSH_CURRENT_BRANCH_ONLY'] -eq '1' -and $norm -cmatch '(^|[;&|\s])git\s+push\b') {
    $cur = Get-CurrentBranch
    $rest = ($norm -creplace '.*git\s+push\s*', '') -replace '[;&|].*', ''
    $rest = $rest -replace '(^|\s)-[-a-zA-Z=]+', ''
    $words = @($rest -split '\s+' | Where-Object { $_ })
    foreach ($r in ($words | Select-Object -Skip 1)) {
      if ($r -in 'HEAD', $cur, "HEAD:$cur", "${cur}:$cur", "HEAD:refs/heads/$cur") { continue }
      Deny "git push refspec '$r' is not the current branch '$cur'"
    }
  }
  Allow
}

# ---------- file tools ----------
function Get-PathArgs($Node) {
  if ($Node -is [System.Collections.IDictionary]) {
    foreach ($k in $Node.Keys) {
      $v = $Node[$k]
      if ($k -match 'path|file' -and $v -is [string]) { $v }
      elseif ($v -isnot [string]) { Get-PathArgs $v }
    }
  } elseif ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
    foreach ($v in $Node) { Get-PathArgs $v }
  }
}

function Test-Paths([string]$Mode) {
  $paths = @(Get-PathArgs $toolArgs)
  # apply_patch style headers: "*** Update File: path"
  $paths += @([regex]::Matches(($toolArgs | ConvertTo-Json -Depth 100 -Compress), '\*\*\* (Add|Update|Delete) File: ([^\\"]+)') | ForEach-Object { $_.Groups[2].Value })
  $rules = Get-Patterns (Join-Path $policyDir 'deny-paths.txt')
  foreach ($path in $paths) {
    if (-not $path) { continue }
    $p = $path -replace '\\', '/'
    $rel = $p
    if ($rel.StartsWith("$root/", [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($root.Length + 1) }
    if ($rel.StartsWith('/workspace/')) { $rel = $rel.Substring(11) }
    if ($rel.StartsWith('./')) { $rel = $rel.Substring(2) }
    foreach ($rule in $rules) {
      if ($rule.StartsWith('write:')) {
        if ($Mode -ne 'write') { continue }
        $pat = $rule.Substring(6)
      } else { $pat = $rule }
      $pat = ConvertTo-NetRegex $pat
      # Windows paths are case-insensitive, so match case-insensitively (denies more, never less).
      if ($rel -match $pat -or $p -match $pat) { Deny "$Mode access to '$rel' is not allowed [$rule]" }
    }
  }
  Allow
}

try {
  if ($tool -eq 'str_replace_editor' -and $toolArgs.Contains('command') -and $toolArgs['command'] -eq 'view') { $tool = 'view' }
  switch -CaseSensitive ($tool) {
    { $_ -in 'bash', 'powershell', 'shell', 'Bash', 'execute' } { Test-Shell }
    { $_ -in 'edit', 'create', 'str_replace_editor', 'str_replace', 'apply_patch', 'write', 'Write', 'Edit', 'MultiEdit' } { Test-Paths 'write' }
    { $_ -in 'view', 'read', 'Read' } { Test-Paths 'read' }
    default { Allow }
  }
} catch { exit 2 }
