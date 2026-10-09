#!/usr/bin/env bash
# Self-test for the guard and stop-gate hooks. Runs in a throwaway git repo.
#   bash scripts/factory/test-hooks.sh
set -uo pipefail
src="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
mkdir -p .github scripts
cp -r "$src/.github/hooks" .github/
cp -r "$src/scripts/factory" scripts/
printf '.agent-logs/\n.agent-work/\n' > .gitignore
# Neutral config: the self-test must not run the project's real checks in this throwaway repo.
printf 'BASE_BRANCH="main"\nSETUP_CMD=""\nFORMAT_CHECK_CMD=""\nLINT_CMD=""\nTYPECHECK_CMD=""\nTEST_CMD=""\nBUILD_CMD=""\nALLOW_NO_CHECKS=0\n' > scripts/factory/commands.env
git add -A && git commit -qm init
git checkout -qb agent/test-1

pass=0; fail=0
expect() { # expect <allow|deny> <description> <payload-json>
  local want="$1" desc="$2" out got
  out="$(bash .github/hooks/scripts/guard.sh <<<"$3")"; rc=$?
  if [[ $rc -ne 0 ]]; then got="deny"
  elif [[ "$(jq -r '.permissionDecision // "allow"' <<<"${out:-{\}}")" == "deny" ]]; then got="deny"
  else got="allow"; fi
  if [[ "$got" == "$want" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $desc (want $want, got $got) $out"; fi
}
sh() { jq -nc --arg c "$1" '{sessionId:"test",timestamp:0,cwd:".",toolName:"bash",toolArgs:{command:$c}}'; }
ed() { jq -nc --arg t "$1" --arg p "$2" '{sessionId:"test",timestamp:0,cwd:".",toolName:$t,toolArgs:{path:$p}}'; }

# guard cases from hook-cases.txt (core + repo type + other layers)
agent_branch="$(git branch --show-current)"
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
  if [[ "$line" =~ ^@checkout[[:space:]]+(.+)$ ]]; then
    b="${BASH_REMATCH[1]}"; [[ "$b" == "-" ]] && b="$agent_branch"
    git checkout -q "$b"; continue
  fi
  want="$(awk '{print $1}' <<<"$line")"; kind="$(awk '{print $2}' <<<"$line")"
  desc="$(sed -E 's/^[[:space:]]*[a-z]+[[:space:]]+[a-z]+[[:space:]]+//; s/[[:space:]]*::.*$//' <<<"$line")"
  arg="${line#* :: }"; arg="${arg//\{branch\}/$agent_branch}"
  case "$kind" in
    sh) expect "$want" "$desc" "$(sh "$arg")" ;;
    *)  expect "$want" "$desc" "$(ed "$kind" "$arg")" ;;
  esac
done < scripts/factory/hook-cases.txt
git checkout -q "$agent_branch"

# payload shapes
expect deny  "apply_patch hook"        "$(jq -nc '{sessionId:"test",toolName:"apply_patch",toolArgs:{input:"*** Begin Patch\n*** Update File: .github/hooks/factory.json\n@@"}}')"
expect deny  "string toolArgs"         "$(jq -nc '{sessionId:"test",toolName:"bash",toolArgs:"{\"command\":\"sudo ls\"}"}')"

# stop gate
stop() { bash .github/hooks/scripts/stop-gate.sh <<<'{"sessionId":"test","stop_hook_active":false}'; }
[[ -z "$(stop)" ]] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: stop gate should pass with no changes"; }
echo "x" > new.txt
[[ "$(stop | jq -r .decision)" == "block" ]] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: stop gate should block unverified changes"; }
sed -i 's/^ALLOW_NO_CHECKS=0/ALLOW_NO_CHECKS=1/' scripts/factory/commands.env
bash scripts/factory/check.sh >/dev/null
[[ -z "$(stop)" ]] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: stop gate should pass after check.sh"; }
echo "y" >> new.txt
[[ "$(stop | jq -r .decision)" == "block" ]] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: stop gate should block after a new edit"; }

# logging
[[ -s .agent-logs/test.jsonl ]] && jq -e . .agent-logs/test.jsonl >/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: log file missing or invalid JSONL"; }
echo '{"sessionId":"test","toolName":"bash","toolArgs":{"command":"echo ghp_abcdefghijklmnopqrstuvwxyz0123"}}' | bash .github/hooks/scripts/log.sh postToolUse
grep -q 'ghp_abcdefghij' .agent-logs/test.jsonl && { fail=$((fail+1)); echo "FAIL: token not redacted"; } || pass=$((pass+1))

echo "hooks self-test: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
