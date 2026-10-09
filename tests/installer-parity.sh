#!/usr/bin/env bash
# install.sh and install.ps1 must produce identical files for every combination. Needs pwsh.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v pwsh >/dev/null || { echo "pwsh not found" >&2; exit 1; }
fail=0
for repo_dir in "$root"/template/repo/*/; do
  repo="$(basename "$repo_dir")"
  for os in linux wsl windows; do
    for assistant_dir in "$root"/template/assistant/*/; do
      assistant="$(basename "$assistant_dir")"
      a="$(mktemp -d)"; b="$(mktemp -d)"
      for d in "$a" "$b"; do (cd "$d" && git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m i); done
      bash "$root/install.sh" "$a" --repo "$repo" --os "$os" --assistant "$assistant" >/dev/null
      pwsh -NoProfile -File "$root/install.ps1" "$b" -Repo "$repo" -Os "$os" -Assistant "$assistant" >/dev/null
      if diff -r -x .git "$a" "$b" >/dev/null; then echo "same: repo=$repo os=$os assistant=$assistant"
      else echo "DIFFERENT: repo=$repo os=$os assistant=$assistant"; diff -r -x .git "$a" "$b" | head -20; fail=1; fi
      rm -rf "$a" "$b"
    done
  done
done
exit $fail
