#!/usr/bin/env bash
# preToolUse guard: logs every tool call, then allows or denies it.
#
# Output contract (Copilot hooks): print ONE JSON object, or nothing.
#   deny  -> {"permissionDecision":"deny","permissionDecisionReason":"..."}
#   allow -> print nothing (fall through to normal permissions)
# A crash or non-zero exit DENIES the call (fail-closed). A timeout ALLOWS it (fail-open),
# so keep this script fast.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"

root="$(factory_root)"
policy_dir="${FACTORY_POLICY_DIR:-$root/.github/hooks/policy}"

payload="$(cat)"
factory_context

tool="$(jq -r '.toolName // .tool_name // ""' <<<"$payload")" || exit 2
args="$(jq -c '(.toolArgs // .tool_input // {}) | if type == "string" then (fromjson? // {raw: .}) else . end' <<<"$payload")" || exit 2

deny() {
  local reason="$1"
  factory_log "preToolUse" "$payload" "$(jq -nc --arg r "$reason" '{decision: "deny", reason: $r}')" || true
  jq -nc --arg r "Blocked by factory guard: $reason. Do not retry this action or work around it; choose a safe alternative or record it as a follow-up in the PR or handoff." \
    '{permissionDecision: "deny", permissionDecisionReason: $r}'
  exit 0
}

allow() {
  factory_log "preToolUse" "$payload" '{"decision":"allow"}' || true
  exit 0
}

# Repo-type rules: may define repo_shell_rules and repo_branch_prefixes.
# shellcheck source=/dev/null
if [[ -f "$here/repo-rules.sh" ]]; then source "$here/repo-rules.sh" || exit 2; fi
# shellcheck disable=SC2034  # used by repo_shell_rules
branch_prefixes="${FACTORY_BRANCH_PREFIXES:-${repo_branch_prefixes:-agent/}}"

# Read regex lines from a policy file, skipping comments/blank lines.
patterns() { [[ -f "$1" ]] && grep -Ev '^\s*(#|$)' "$1" || true; }

# ---------- shell commands ----------
check_shell() {
  local cmd norm pat
  cmd="$(jq -r '.command // .cmd // .script // .input // .raw // empty' <<<"$args")"
  [[ -z "$cmd" ]] && cmd="$(jq -r 'tostring' <<<"$args")"
  norm="$(tr '\n\t' '  ' <<<"$cmd" | tr -s ' ')"

  while IFS= read -r pat; do
    if grep -Eiq -- "$pat" <<<"$norm"; then
      deny "command matches denied pattern [$pat]"
    fi
  done < <(patterns "$policy_dir/deny-commands.txt")

  # Repo-type rules (e.g. which branches may push or commit), if installed.
  if declare -F repo_shell_rules >/dev/null; then repo_shell_rules "$norm"; fi
  allow
}

# ---------- file tools ----------
paths_in_args() {
  jq -r '[.. | objects | to_entries[] | select(.key | test("path|file"; "i")) | .value | strings] | .[]' <<<"$args" 2>/dev/null
  # apply_patch style headers: "*** Update File: path"
  jq -r 'tostring' <<<"$args" | grep -oE '\*\*\* (Add|Update|Delete) File: [^\\"]+' | sed -E 's/^\*\*\* (Add|Update|Delete) File: //'
}

check_paths() {
  local mode="$1" path rel pat rule
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    rel="${path#"$root"/}"; rel="${rel#/workspace/}"; rel="${rel#./}"
    while IFS= read -r rule; do
      if [[ "$rule" == write:* ]]; then
        [[ "$mode" != "write" ]] && continue
        pat="${rule#write:}"
      else
        pat="$rule"
      fi
      if grep -Eq -- "$pat" <<<"$rel" || grep -Eq -- "$pat" <<<"$path"; then
        deny "$mode access to '$rel' is not allowed [$pat]"
      fi
    done < <(patterns "$policy_dir/deny-paths.txt")
  done < <(paths_in_args)
  allow
}

if [[ "$tool" == "str_replace_editor" && "$(jq -r '.command // ""' <<<"$args")" == "view" ]]; then
  tool="view"
fi

case "$tool" in
  bash|powershell|shell|Bash|execute)          check_shell ;;
  edit|create|str_replace_editor|str_replace|apply_patch|write|Write|Edit|MultiEdit) check_paths write ;;
  view|read|Read)                               check_paths read ;;
  *)                                            allow ;;
esac
