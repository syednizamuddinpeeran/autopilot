#!/usr/bin/env bash
# Starts the coding assistant this repo was installed for (ASSISTANT in commands.env) with the
# factory agent. Sourced by run-issue.sh / run-task.sh.
#
#   agent_cli <auto|--watch> <prompt> <shell command to deny>...
#
# The deny list is an extra CLI-level layer; the preToolUse guard hook enforces the full policy.
# Flag names can change between CLI versions: check `copilot help permissions` / `claude --help`.
agent_cli() {
  local mode="$1" prompt="$2" c
  shift 2
  local flags=()
  case "${ASSISTANT:-copilot}" in
    copilot)
      command -v copilot >/dev/null || { echo "Missing: copilot" >&2; exit 1; }
      # In prompt mode (-p) the CLI loads repository hooks only for trusted folders. The worktree is
      # new, so opt in explicitly; without this the guard, logging and stop-gate hooks would not run.
      export GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true
      for c in "$@"; do flags+=(--deny-tool "shell($c)"); done
      if [[ "$mode" == "--watch" ]]; then
        echo "Starting interactive session. Paste this, then switch to autopilot (Shift+Tab or /autopilot):"
        echo "----"; echo "$prompt"; echo "----"
        exec copilot --agent factory "${flags[@]}"
      fi
      # shellcheck disable=SC2086  # COPILOT_EXTRA_FLAGS is a list of flags
      exec copilot --agent factory -p "$prompt" --allow-all-tools "${flags[@]}" ${COPILOT_EXTRA_FLAGS:-}
      ;;
    claude-code)
      command -v claude >/dev/null || { echo "Missing: claude" >&2; exit 1; }
      # claude -p runs the project's .claude/settings.json hooks even in an untrusted folder.
      for c in "$@"; do flags+=("Bash($c *)" "Bash($c)"); done
      if [[ "$mode" == "--watch" ]]; then
        echo "Starting interactive session. Paste this, then pick a permission mode (Shift+Tab):"
        echo "----"; echo "$prompt"; echo "----"
        exec claude --agent factory --disallowedTools "${flags[@]}"
      fi
      # shellcheck disable=SC2086  # CLAUDE_EXTRA_FLAGS is a list of flags
      exec claude --agent factory --permission-mode bypassPermissions --disallowedTools "${flags[@]}" \
        ${CLAUDE_EXTRA_FLAGS:-} -p "$prompt"
      ;;
    *) echo "Unknown ASSISTANT in commands.env: ${ASSISTANT}" >&2; exit 1 ;;
  esac
}
