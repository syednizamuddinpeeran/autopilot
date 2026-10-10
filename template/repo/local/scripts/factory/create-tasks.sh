#!/usr/bin/env bash
# HUMAN-ONLY: create the sub-tasks of a breakdown the planner proposed, after you reviewed it, and
# commit them on the base branch.
#
#   scripts/factory/create-tasks.sh .agent-work/breakdowns/<task-id>.md [--yes]
#
# Validates the breakdown (check-breakdown.sh: items ready, dependencies, no cycles, parent AC
# coverage when the brief is next to it), shows every item, asks for confirmation, then writes
# tasks/<parent>.<n>.md for each item ("Parent:" and "Depends on:" lines name task ids), adds a
# "Broken down into" section to the parent task, and commits everything in one commit.
# Agents are denied this script by the guard, and tasks/ is write-protected for them.
set -euo pipefail
src="${1:?usage: create-tasks.sh <breakdown.md> [--yes]}"
yes="${2:-}"
[[ -f "$src" ]] || { echo "not found: $src" >&2; exit 1; }
src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"

root="$(git rev-parse --show-toplevel)"
cd "$root"
# shellcheck disable=SC1091
source scripts/factory/commands.env
base="${BASE_BRANCH:-main}"

parent="$(sed -nE '1,3s/^# Breakdown of task ([a-z0-9][a-z0-9._-]*):.*/\1/p' "$src" | head -1)"
[[ -n "$parent" ]] || { echo "The breakdown title must be '# Breakdown of task <id>: <title>'." >&2; exit 4; }
[[ -f "tasks/$parent.md" ]] || { echo "Parent task tasks/$parent.md not found." >&2; exit 1; }
[[ "$(git branch --show-current)" == "$base" ]] || { echo "Check out '$base' first." >&2; exit 1; }
[[ -z "$(git status --porcelain -- tasks)" ]] || { echo "tasks/ has uncommitted changes; commit or stash them first." >&2; exit 1; }

brief=""; [[ -f "${src%.md}.brief.md" ]] && brief="${src%.md}.brief.md"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
items="$tmp/items"
if ! bash scripts/factory/check-breakdown.sh "$src" ${brief:+"$brief"} --split "$items"; then
  echo "Fix the breakdown, then run again." >&2
  exit 4
fi
[[ -n "$brief" ]] || echo "(No parent brief next to the breakdown: acceptance-criteria coverage was not checked — compare with tasks/$parent.md yourself.)"

mapfile -t order < "$items/order"
for i in "${order[@]}"; do
  [[ ! -e "tasks/$parent.$i.md" ]] || { echo "tasks/$parent.$i.md already exists: this breakdown was created before." >&2; exit 1; }
done
echo
echo "──────── Sub-tasks of $parent"
for i in "${order[@]}"; do
  echo
  echo "── tasks/$parent.$i.md"
  cat "$items/$i.md"
done
echo "────────"
if [[ -z "$yes" ]]; then
  [[ -t 0 ]] || { echo "Not a terminal: pass --yes after reviewing the breakdown." >&2; exit 1; }
  read -r -p "Create and commit ${#order[@]} sub-tasks of '$parent' on '$base'? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Not created."; exit 0; }
fi

list=""
for i in "${order[@]}"; do
  f="tasks/$parent.$i.md"
  {
    head -1 "$items/$i.md"
    echo
    echo "Parent: $parent"
    tail -n +2 "$items/$i.md" | sed -E "/^Depends on:/ s/Item ([0-9]+)/$parent.\\1/g"
  } > "$f"
  git add "$f"
  list+="- $parent.$i: $(head -1 "$items/$i.md" | sed 's/^# //')"
  deps="$(paste -sd' ' "$items/$i.deps")"
  [[ -n "$deps" ]] && list+=" (after $(sed -E "s/([0-9]+)/$parent.\\1/g" <<<"$deps"))"
  list+=$'\n'
done
printf '\n## Broken down into\n%s' "$list" >> "tasks/$parent.md"
git add "tasks/$parent.md"
git commit -q -m "task: breakdown of $parent into ${#order[@]} sub-tasks" -- tasks
echo "Committed ${#order[@]} sub-tasks of '$parent' on '$base':"
printf '%s' "$list"
echo "Run them in dependency order with scripts/factory/run-task.sh <id>."
