#!/usr/bin/env bash
# HUMAN-ONLY: review and merge an agent branch into the base branch, locally.
# This replaces "CI + branch protection + merge button" for repos with no remote.
#
#   scripts/factory/accept.sh add-csv-export                 # verify, then merge --no-ff
#   scripts/factory/accept.sh add-csv-export --allow-guardrails   # you reviewed guardrail edits
#
# Run it from the main checkout (base branch checked out, clean tree). Agents are denied this
# script by the guard hook.
set -euo pipefail

task="${1:?usage: accept.sh <task-id> [--allow-guardrails]}"
allow_guardrails="${2:-}"
root="$(git rev-parse --show-toplevel)"
cd "$root"
# shellcheck disable=SC1091
source scripts/factory/commands.env
base="${BASE_BRANCH:-main}"
branch="agent/${task}"
repo_name="$(basename "$root")"
wt="${FACTORY_WORKTREE_ROOT:-$(dirname "$root")/${repo_name}-worktrees}/${task}"

[[ "$(git branch --show-current)" == "$base" ]] || { echo "Check out '$base' first." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree is not clean." >&2; exit 1; }
git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null || { echo "No branch $branch" >&2; exit 1; }

echo "── commits on $branch"; git log --oneline "$base..$branch"
echo "── files changed";      git diff --stat "$base...$branch"

# 1. Guardrails unchanged (local equivalent of the CI 'guardrails-unchanged' job).
guard_changes="$(git diff --name-only "$base...$branch" -- .github scripts/factory tasks AGENTS.md install.sh)"
if [[ -n "$guard_changes" && "$allow_guardrails" != "--allow-guardrails" ]]; then
  echo "Branch modifies guardrail files (review them, then re-run with --allow-guardrails):" >&2
  echo "$guard_changes" >&2
  exit 1
fi

# 2. Verify the branch from its own worktree (or a temporary one), using the BASE's guardrails.
tmp=""
if [[ -d "$wt" ]]; then dir="$wt"; else tmp="$(mktemp -d)"; git worktree add --detach -q "$tmp" "$branch"; dir="$tmp"; fi
cleanup() { [[ -n "$tmp" ]] && git worktree remove --force "$tmp" >/dev/null 2>&1 || true; }
trap cleanup EXIT
( cd "$dir" && bash scripts/factory/setup.sh && bash scripts/factory/check.sh )
bash scripts/factory/test-hooks.sh

# 3. Merge.
read -r -p "Merge $branch into $base? [y/N] " ans
[[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Not merged."; exit 0; }
git merge --no-ff "$branch" -m "merge: ${task}"
echo "Merged. Clean up with: git worktree remove '$wt' && git branch -d '$branch'"
