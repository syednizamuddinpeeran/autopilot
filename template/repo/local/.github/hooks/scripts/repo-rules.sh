# Repo type: local (no remote). Sourced by guard.sh; uses its deny(), $root and $branch_prefixes.
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # repo_branch_prefixes is read by guard.sh; root/branch_prefixes come from it
repo_branch_prefixes="agent/"

repo_shell_rules() {
  local norm="$1" cur
  # Commits/merges are allowed only on agent branches (pushes are denied by policy).
  if grep -Eq '(^|[;&|[:space:]])git\s+(-C\s+\S+\s+)?(commit|merge|rebase|cherry-pick|am|revert)\b' <<<"$norm"; then
    cur="$(git -C "$root" branch --show-current 2>/dev/null || true)"
    local ok=1 p
    for p in $branch_prefixes; do [[ "$cur" == "$p"* ]] && ok=0; done
    [[ $ok -ne 0 ]] && deny "git commit/merge is only allowed on branches starting with: $branch_prefixes (current: ${cur:-detached})"
  fi
}
