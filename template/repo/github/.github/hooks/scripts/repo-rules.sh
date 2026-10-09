# Repo type: github. Sourced by guard.sh; uses its deny(), $root and $branch_prefixes.
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # repo_branch_prefixes is read by guard.sh; root/branch_prefixes come from it
repo_branch_prefixes="agent/ copilot/"

repo_shell_rules() {
  local norm="$1" cur
  # git push: only the current agent branch, only to origin, never base branches.
  if grep -Eq '(^|[;&|[:space:]])git\s+push\b' <<<"$norm"; then
    cur="$(git -C "$root" branch --show-current 2>/dev/null || true)"
    local ok=1 p
    for p in $branch_prefixes; do [[ "$cur" == "$p"* ]] && ok=0; done
    [[ $ok -ne 0 ]] && deny "git push is only allowed from branches starting with: $branch_prefixes (current: ${cur:-detached})"
    # Any explicit refspec must name the current branch or HEAD.
    local refs
    refs="$(sed -E 's/.*git\s+push\s*//; s/[;&|].*//; s/(^|\s)-[-a-zA-Z=]+//g' <<<"$norm" | awk '{for (i=2;i<=NF;i++) print $i}')"
    while IFS= read -r r; do
      [[ -z "$r" ]] && continue
      [[ "$r" == "HEAD" || "$r" == "$cur" || "$r" == "HEAD:$cur" || "$r" == "$cur:$cur" ]] && continue
      [[ "$r" == "HEAD:refs/heads/$cur" ]] && continue
      deny "git push refspec '$r' is not the current branch '$cur'"
    done <<<"$refs"
  fi
}
