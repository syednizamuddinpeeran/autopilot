#!/usr/bin/env bash
# End-to-end launcher flow with fake `copilot` and `gh` CLIs (no network, no real agent):
#   - not ready  → exit 4 and the agent never starts
#   - ready, agent writes questions.md → exit 5 and the questions are shown
#   - ready, agent finishes → exit 0
#   - local: an edited task restarts a worktree that has no commits yet
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fx="$root/tests/fixtures/ready"
fail=0
check() { # check <description> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1 (want $2, got $3)"; fail=1; fi
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"; mkdir -p "$bin"
# Fake agent CLI: records that it ran; writes questions.md when FAKE_AGENT=questions.
cat > "$bin/copilot" <<'SH'
#!/usr/bin/env bash
echo ran >> "$FAKE_LOG"
if [[ "${FAKE_AGENT:-}" == questions ]]; then
  d="$(ls -d .agent-work/*/ | head -1)"
  printf '1. Which columns are exported? — Why it matters: changes the CSV header.\n' > "${d}questions.md"
fi
exit 0
SH
# Fake gh: `gh issue view N --json …` prints an issue whose body is $FAKE_ISSUE_BODY.
cat > "$bin/gh" <<'SH'
#!/usr/bin/env bash
if [[ "$1 $2" == "issue view" ]]; then
  jq -n --arg b "$(cat "$FAKE_ISSUE_BODY")" '{number: 7, title: "Add CSV export", body: $b, labels: [], url: "https://example.test/7"}'
fi
SH
chmod +x "$bin"/*
export PATH="$bin:$PATH" FAKE_LOG="$tmp/agent.log"

setup_repo() { # setup_repo <repo-type> <dir>
  mkdir -p "$2" && cd "$2" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  echo x > README.md && git add -A && git commit -qm init
  bash "$root/install.sh" . --repo "$1" >/dev/null
  sed -i 's/^ALLOW_NO_CHECKS=0/ALLOW_NO_CHECKS=1/' scripts/factory/commands.env
  git add -A && git commit -qm factory
}
runs() { [[ -f "$FAKE_LOG" ]] && wc -l < "$FAKE_LOG" | tr -d ' ' || echo 0; }

# ---- local repo ----
setup_repo local "$tmp/local"
cp "$fx/bad-no-ac.md" tasks/t1.md && git add tasks && git commit -qm "task: t1"
rm -f "$FAKE_LOG"
out="$(bash scripts/factory/run-task.sh t1 2>&1)"; rc=$?
check "local: not-ready task exits 4" 4 "$rc"
check "local: agent not started for not-ready task" 0 "$(runs)"
grep -q "Acceptance criteria" <<<"$out" || { echo "FAIL local: reason not shown"; fail=1; }

cp "$fx/ok-task.md" tasks/t1.md && git add tasks && git commit -qm "task: t1 ready"
out="$(FAKE_AGENT=questions bash scripts/factory/run-task.sh t1 2>&1)"; rc=$?
check "local: agent questions exit 5" 5 "$rc"
grep -q "Which columns are exported" <<<"$out" || { echo "FAIL local: questions not shown"; fail=1; }

sed -i 's/^Users can download the report table as CSV.$/Users can download the visible report table as CSV./' tasks/t1.md
git add tasks && git commit -qm "task: t1 answered"
out="$(bash scripts/factory/run-task.sh t1 2>&1)"; rc=$?
check "local: answered task runs" 0 "$rc"
grep -q "recreating the worktree" <<<"$out" || { echo "FAIL local: worktree not refreshed after task edit"; fail=1; }
grep -q "visible report table" "$tmp/local-worktrees/t1/tasks/t1.md" || { echo "FAIL local: worktree has the old task"; fail=1; }

# ---- github repo ----
setup_repo github "$tmp/gh"
git init -q --bare "$tmp/origin.git" && git remote add origin "$tmp/origin.git" && git push -q origin main 2>/dev/null
rm -f "$FAKE_LOG"
export FAKE_ISSUE_BODY="$fx/bad-issue-empty-field.md"
out="$(bash scripts/factory/run-issue.sh 7 </dev/null 2>&1)"; rc=$?
check "github: not-ready issue exits 4" 4 "$rc"
check "github: agent not started for not-ready issue" 0 "$(runs)"
grep -q "issue #7" <<<"$out" || { echo "FAIL github: reason does not name the issue"; fail=1; }

export FAKE_ISSUE_BODY="$fx/ok-issue-form.md"
out="$(FAKE_AGENT=questions bash scripts/factory/run-issue.sh 7 </dev/null 2>&1)"; rc=$?
check "github: agent questions exit 5" 5 "$rc"
grep -q "Which columns are exported" <<<"$out" || { echo "FAIL github: questions not shown"; fail=1; }

out="$(bash scripts/factory/run-issue.sh 7 </dev/null 2>&1)"; rc=$?
check "github: ready issue runs" 0 "$rc"
[[ ! -e "$tmp/gh-worktrees/issue-7/.agent-work/issue-7/questions.md" ]] || { echo "FAIL github: stale questions.md kept"; fail=1; }

[[ $fail -eq 0 ]] && echo "launcher flow: all passed"
exit $fail
