#!/usr/bin/env bash
# Install every supported combination into a scratch git repo and run its self-tests there.
#   bash tests/install-matrix.sh            # all combinations
#   bash tests/install-matrix.sh github     # only repo type "github"
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repos=("${@:-}")
[[ -z "${repos[0]}" ]] && mapfile -t repos < <(ls "$root/template/repo")

fail=0
for repo in "${repos[@]}"; do
  echo "=== repo=$repo"
  tmp="$(mktemp -d)"
  (
    set -e
    cd "$tmp"
    git init -q -b main . && git config user.email t@t && git config user.name t
    echo "# scratch" > README.md && git add -A && git commit -qm init
    bash "$root/install.sh" "$tmp" --repo "$repo" >/dev/null
    # Second run must skip everything and change nothing.
    before="$(git status --porcelain | sort; find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum)"
    if bash "$root/install.sh" "$tmp" --repo "$repo" | grep -q '^added:'; then echo "re-install added files"; exit 1; fi
    after="$(git status --porcelain | sort; find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum)"
    [[ "$before" == "$after" ]] || { echo "re-install changed files"; exit 1; }
    bash scripts/factory/test-hooks.sh
    # The installed default must refuse to pass with nothing configured.
    if bash scripts/factory/check.sh >/dev/null 2>&1; then echo "check.sh passed with no checks configured"; exit 1; fi
    sed -i 's/^ALLOW_NO_CHECKS=0/ALLOW_NO_CHECKS=1/' scripts/factory/commands.env
    bash scripts/factory/setup.sh >/dev/null
    bash scripts/factory/check.sh >/dev/null
  ) || { echo "FAILED: repo=$repo"; fail=1; }
  rm -rf "$tmp"
done
[[ $fail -eq 0 ]] && echo "install matrix: all passed"
exit $fail
