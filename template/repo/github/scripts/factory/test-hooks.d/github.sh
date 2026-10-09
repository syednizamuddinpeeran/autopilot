# Repo type: github. Sourced by test-hooks.sh (uses expect, sh, ed; runs on an agent/* branch).
# shellcheck shell=bash
agent_branch="$(git branch --show-current)"
expect allow "push current branch"     "$(sh 'git push -u origin HEAD')"
expect allow "push named branch"       "$(sh "git push origin $agent_branch")"
expect allow "push then pr"            "$(sh 'git push -u origin HEAD && gh pr create --fill')"
expect deny  "force push"              "$(sh 'git push --force origin HEAD')"
expect deny  "push to main"            "$(sh 'git push origin main')"
expect deny  "push refspec to main"    "$(sh 'git push origin HEAD:main')"
expect deny  "merge pr"                "$(sh 'gh pr merge 3 --squash')"
expect deny  "gh token"                "$(sh 'gh auth token')"
expect allow "view workflow"           "$(ed view .github/workflows/ci.yml)"
expect deny  "create workflow"         "$(ed create .github/workflows/evil.yml)"

# push from main is denied
git checkout -q main
expect deny  "push from main branch"   "$(sh 'git push -u origin HEAD')"
git checkout -q "$agent_branch"
