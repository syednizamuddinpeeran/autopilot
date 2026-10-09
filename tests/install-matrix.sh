#!/usr/bin/env bash
# Install every supported combination into a scratch git repo and run its self-tests there.
#   bash tests/install-matrix.sh            # all combinations
#   bash tests/install-matrix.sh github     # only repo type "github"
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repos=("$@")
[[ ${#repos[@]} -eq 0 ]] && mapfile -t repos < <(ls "$root/template/repo")

snapshot() { git status --porcelain | sort; find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum; }

# One combination. Every step is checked explicitly: set -e does not apply inside a function
# whose status is tested by the caller.
run_one() {
  local repo="$1" tmp="$2" before
  cd "$tmp" || return 1
  git init -q -b main . && git config user.email t@t && git config user.name t || return 1
  echo "# scratch" > README.md && git add -A && git commit -qm init || return 1
  bash "$root/install.sh" "$tmp" --repo "$repo" >/dev/null || { echo "install failed"; return 1; }
  before="$(snapshot)"
  if bash "$root/install.sh" "$tmp" --repo "$repo" | grep -q '^added:'; then echo "re-install added files"; return 1; fi
  [[ "$before" == "$(snapshot)" ]] || { echo "re-install changed files"; return 1; }
  bash scripts/factory/test-hooks.sh || return 1
  if bash scripts/factory/check.sh >/dev/null 2>&1; then echo "check.sh passed with no checks configured"; return 1; fi
  sed -i 's/^ALLOW_NO_CHECKS=0/ALLOW_NO_CHECKS=1/' scripts/factory/commands.env
  bash scripts/factory/setup.sh >/dev/null || { echo "setup.sh failed"; return 1; }
  bash scripts/factory/check.sh >/dev/null || { echo "check.sh failed"; return 1; }
}

fail=0
for repo in "${repos[@]}"; do
  echo "=== repo=$repo"
  tmp="$(mktemp -d)"
  ( run_one "$repo" "$tmp" ) || { echo "FAILED: repo=$repo"; fail=1; }
  rm -rf "$tmp"
done
if [[ $fail -eq 0 ]]; then echo "install matrix: all passed"; else echo "install matrix: FAILED"; fi
exit $fail
