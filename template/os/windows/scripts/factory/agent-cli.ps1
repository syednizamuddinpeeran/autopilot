# Starts the coding assistant this repo was installed for (ASSISTANT in commands.env) with the
# factory agent. Dot-sourced by run-issue.ps1 / run-task.ps1. PowerShell counterpart of agent-cli.sh.
#
#   Invoke-AgentCli -Assistant <copilot|claude-code> -Prompt <text> -Deny <shell commands> [-Watch]
#
# The deny list is an extra CLI-level layer; the preToolUse guard hook enforces the full policy.
# Flag names can change between CLI versions: check `copilot help permissions` / `claude --help`.
function Invoke-AgentCli([string]$Assistant, [string]$Prompt, [string[]]$Deny, [switch]$Watch) {
  if (-not $Assistant) { $Assistant = 'copilot' }
  switch ($Assistant) {
    'copilot' {
      if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) { throw 'Missing: copilot' }
      # In prompt mode (-p) the CLI loads repository hooks only for trusted folders. The worktree is
      # new, so opt in explicitly; without this the guard, logging and stop-gate hooks would not run.
      $env:GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS = 'true'
      $flags = @(foreach ($c in $Deny) { '--deny-tool'; "shell($c)" })
      $extra = if ($env:COPILOT_EXTRA_FLAGS) { @($env:COPILOT_EXTRA_FLAGS -split '\s+' | Where-Object { $_ }) } else { @() }
      if ($Watch) {
        Write-Output 'Starting interactive session. Paste this, then switch to autopilot (Shift+Tab or /autopilot):'
        Write-Output '----'; Write-Output $Prompt; Write-Output '----'
        & copilot --agent factory @flags
      } else {
        & copilot --agent factory -p $Prompt --allow-all-tools @flags @extra
      }
    }
    'claude-code' {
      if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { throw 'Missing: claude' }
      # claude -p runs the project's .claude/settings.json hooks even in an untrusted folder.
      $flags = @(foreach ($c in $Deny) { "Bash($c *)"; "Bash($c)"; "PowerShell($c *)"; "PowerShell($c)" })
      $extra = if ($env:CLAUDE_EXTRA_FLAGS) { @($env:CLAUDE_EXTRA_FLAGS -split '\s+' | Where-Object { $_ }) } else { @() }
      if ($Watch) {
        Write-Output 'Starting interactive session. Paste this, then pick a permission mode (Shift+Tab):'
        Write-Output '----'; Write-Output $Prompt; Write-Output '----'
        & claude --agent factory --disallowedTools @flags
      } else {
        & claude --agent factory --permission-mode bypassPermissions --disallowedTools @flags @extra -p $Prompt
      }
    }
    default { throw "Unknown ASSISTANT in commands.env: $Assistant" }
  }
  exit $LASTEXITCODE
}
