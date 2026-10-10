#!/usr/bin/env bash
# Run the sub-tasks of a broken-down task (create-tasks.sh), in dependency order, several at a time.
#
#   scripts/factory/run-batch.sh <parent-id>                   # run every sub-task that is ready now
#   scripts/factory/run-batch.sh <parent-id> --auto-continue   # …then keep going as you merge them
#   scripts/factory/run-batch.sh <parent-id> --list            # show the state of each sub-task only
#   options: --parallel <n> (default: MAX_PARALLEL in complexity.env)
#
# A sub-task tasks/<parent>.<n>.md is ready to run when every task on its "Depends on:" line has
# been merged into the base branch with accept.sh. Each one runs as its own run-task.sh (autonomous)
# in its own worktree and branch, at most <n> at the same time; output goes to
# .agent-logs/batch/<id>.log.
#
# Without --auto-continue the batch stops when the runs it could start have finished: review and
# merge them (accept.sh), then run it again. With --auto-continue it waits for your merges
# (checking every BATCH_POLL_SECONDS, default 60) and starts the sub-tasks they unblock, until
# every sub-task is merged or nothing more can start without you. Merging stays a human step.
#
# Exit codes: 0 every run it started finished, 1 a run failed or stopped (questions, breakdown),
# 2 no sub-tasks found.
set -euo pipefail

parent="" auto="" list="" parallel=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-continue) auto=1; shift ;;
    --list) list=1; shift ;;
    --parallel) parallel="${2:?--parallel needs a number}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) parent="$1"; shift ;;
  esac
done
[[ -n "$parent" ]] || { echo "usage: run-batch.sh <parent-task-id> [--auto-continue] [--list] [--parallel <n>]" >&2; exit 2; }

root="$(git rev-parse --show-toplevel)"
cd "$root"
# shellcheck disable=SC1091
source scripts/factory/commands.env
# shellcheck disable=SC1091
source scripts/factory/complexity.env
base="${BASE_BRANCH:-main}"
parallel="${parallel:-${MAX_PARALLEL:-3}}"
[[ "$parallel" =~ ^[1-9][0-9]*$ ]] || { echo "--parallel must be a positive number" >&2; exit 1; }
poll="${BATCH_POLL_SECONDS:-60}"
logs="$root/.agent-logs/batch"; mkdir -p "$logs"

mapfile -t subs < <(git ls-tree --name-only "$base" tasks/ | sed -n "s|^tasks/\(${parent//./\\.}\.[0-9][0-9]*\)\.md$|\1|p" | sort -V)
[[ ${#subs[@]} -gt 0 ]] || { echo "No sub-tasks tasks/$parent.<n>.md on '$base'. Create them with create-tasks.sh." >&2; exit 2; }

merged() { git log --format=%s "$base" | grep -xF "merge: $1" >/dev/null; }   # no -q: it would cut the pipe (pipefail)
deps_of() { git show "$base:tasks/$1.md" | sed -nE 's/^Depends on:[[:space:]]*//p' | head -1 | grep -oE '[a-z0-9][a-z0-9._-]*[0-9]' | grep -vx none || true; }

declare -A pid=() rc=()
# State of one sub-task: merged | running | finished | review | stopped | blocked | ready
state() {
  local id="$1" d
  merged "$id" && { echo merged; return; }
  [[ -n "${pid[$id]:-}" ]] && { echo running; return; }
  [[ -n "${rc[$id]:-}" && "${rc[$id]}" != 0 ]] && { echo stopped; return; }
  if git rev-parse --verify --quiet "refs/heads/agent/$id" >/dev/null; then
    if [[ "$(git rev-list --count "$base..agent/$id")" -gt 0 ]]; then echo review; else echo stopped; fi
    return
  fi
  for d in $(deps_of "$id"); do merged "$d" || { echo blocked; return; }; done
  echo ready
}
show() {
  local id s
  echo "Sub-tasks of $parent:"
  for id in "${subs[@]}"; do
    s="$(state "$id")"
    case "$s" in
      merged)  printf '  %-24s merged\n' "$id" ;;
      running) printf '  %-24s running (log: .agent-logs/batch/%s.log)\n' "$id" "$id" ;;
      review)  printf '  %-24s waiting for your review: scripts/factory/accept.sh %s\n' "$id" "$id" ;;
      stopped) printf '  %-24s needs you: see .agent-logs/batch/%s.log (questions, breakdown or failure)\n' "$id" "$id" ;;
      blocked) printf '  %-24s blocked by: %s\n' "$id" "$(for d in $(deps_of "$id"); do merged "$d" || printf '%s ' "$d"; done)" ;;
      ready)   printf '  %-24s ready\n' "$id" ;;
    esac
  done
}
[[ -n "$list" ]] && { show; exit 0; }

failed=0
reap() { # collect finished runs
  local id
  for id in "${!pid[@]}"; do
    if ! kill -0 "${pid[$id]}" 2>/dev/null; then
      local r=0; wait "${pid[$id]}" || r=$?
      rc[$id]=$r; unset "pid[$id]"
      [[ $r -eq 0 ]] || failed=1
      echo "finished $id (exit $r)"
    fi
  done
}
while true; do
  reap
  for id in "${subs[@]}"; do
    (( ${#pid[@]} < parallel )) || break
    [[ "$(state "$id")" == ready ]] || continue
    echo "start    $id"
    bash scripts/factory/run-task.sh "$id" </dev/null >"$logs/$id.log" 2>&1 &
    pid[$id]=$!
    sleep "${BATCH_STAGGER_SECONDS:-2}"   # let each run create its worktree before the next starts
  done
  if [[ ${#pid[@]} -gt 0 ]]; then sleep 2; continue; fi

  # Nothing running. Done, or waiting for the human to merge?
  pending=0 waiting=0
  for id in "${subs[@]}"; do
    case "$(state "$id")" in
      merged) ;;
      review) pending=1; waiting=1 ;;
      ready) pending=1; waiting=1 ;;
      *) pending=1 ;;
    esac
  done
  [[ $pending -eq 0 ]] && { echo "All sub-tasks of $parent are merged."; break; }
  [[ -n "$auto" && $waiting -eq 1 ]] || break
  sleep "$poll"
done
echo
show
if [[ -z "$auto" ]]; then
  echo
  echo "Review and merge the finished ones (scripts/factory/accept.sh <id>), then run the batch again"
  echo "(or use --auto-continue to start the next ones as you merge)."
fi
exit "$failed"
