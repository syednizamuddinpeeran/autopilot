# Repo type: local. Sourced by test-hooks.sh (uses expect, sh, ed; runs on an agent/* branch).
# shellcheck shell=bash
agent_branch="$(git branch --show-current)"
expect allow "commit on agent branch"  "$(sh 'git commit -am x')"
expect deny  "any push"                "$(sh 'git push -u origin HEAD')"
expect deny  "force push"              "$(sh 'git push --force origin HEAD')"
expect deny  "add remote"              "$(sh 'git remote add origin https://example.com/x.git')"
expect deny  "merge main"              "$(sh 'git merge main')"
expect deny  "accept script"           "$(sh 'bash scripts/factory/accept.sh t')"
expect deny  "gh cli"                  "$(sh 'gh pr create --fill')"
expect deny  "gh token"                "$(sh 'gh auth token')"
expect allow "view hook config"        "$(ed view .github/hooks/factory.json)"
expect deny  "edit agent file"         "$(ed edit .github/agents/factory.agent.md)"
expect deny  "edit AGENTS.md"          "$(ed edit AGENTS.md)"
expect deny  "edit task file"          "$(ed edit tasks/x.md)"

# commits/merges on the base branch are denied
git checkout -q main
expect deny  "commit on main branch"   "$(sh 'git commit -am x')"
git checkout -q "$agent_branch"
