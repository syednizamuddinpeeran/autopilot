#!/usr/bin/env bash
# Copy the agent-factory template into an existing repository.
#   ./install.sh /path/to/repo           # skip files that already exist
#   ./install.sh /path/to/repo --force   # overwrite template files
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dst="${1:?usage: install.sh <target-repo> [--force]}"
force="${2:-}"
[[ -d "$dst/.git" ]] || { echo "$dst is not a git repository" >&2; exit 1; }

files=(
  AGENTS.md
  .github/agents/factory.agent.md
  .github/agents/planner.agent.md
  .github/agents/implementer.agent.md
  .github/agents/reviewer.agent.md
  .github/skills/issue-intake/SKILL.md
  .github/skills/implementation-plan/SKILL.md
  .github/skills/verify-changes/SKILL.md
  .github/skills/open-pr/SKILL.md
  .github/hooks/factory.json
  .github/hooks/policy/deny-commands.txt
  .github/hooks/policy/deny-paths.txt
  .github/hooks/scripts/common.sh
  .github/hooks/scripts/log.sh
  .github/hooks/scripts/guard.sh
  .github/hooks/scripts/stop-gate.sh
  .github/workflows/copilot-setup-steps.yml
  .github/workflows/ci.yml
  .github/ISSUE_TEMPLATE/agent-task.yml
  .github/pull_request_template.md
  scripts/factory/commands.env
  scripts/factory/check.sh
  scripts/factory/setup.sh
  scripts/factory/run-issue.sh
  scripts/factory/test-hooks.sh
)

for f in "${files[@]}"; do
  if [[ -e "$dst/$f" && "$force" != "--force" ]]; then
    echo "skip (exists): $f"; continue
  fi
  mkdir -p "$dst/$(dirname "$f")"
  cp "$src/$f" "$dst/$f"
  echo "added: $f"
done

for line in ".agent-logs/" ".agent-work/"; do
  grep -qxF "$line" "$dst/.gitignore" 2>/dev/null || echo "$line" >> "$dst/.gitignore"
done
chmod +x "$dst"/.github/hooks/scripts/*.sh "$dst"/scripts/factory/*.sh

echo
echo "Next: edit $dst/scripts/factory/commands.env and the Project section of $dst/AGENTS.md,"
echo "then run: (cd $dst && bash scripts/factory/test-hooks.sh && bash scripts/factory/check.sh)"
