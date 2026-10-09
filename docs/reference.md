# Reference

## Scripts (`scripts/factory/`)

| Script | Who runs it | Purpose |
|---|---|---|
| `commands.env` | human edits | `BASE_BRANCH`, `SETUP_CMD`, `FORMAT_CHECK_CMD`, `LINT_CMD`, `TYPECHECK_CMD`, `TEST_CMD`, `BUILD_CMD`, `ALLOW_NO_CHECKS` |
| `setup.sh` | run-issue, setup job, CI, agents | Requires `git`, `jq`; `chmod +x` scripts; creates `.agent-logs`, `.agent-work`; runs `SETUP_CMD` |
| `check.sh` | agents, humans, CI | Runs format → lint → typecheck → test → build; skips empty; writes `.agent-logs/.verified` hash on success. Exit 0 pass, 1 fail, 3 nothing configured |
| `run-issue.sh <N> [--watch]` | human (local) | Fetches the issue with `gh`; creates worktree + `agent/issue-N-<slug>` from `origin/<base>`; launches Copilot with `--agent factory` |
| `test-hooks.sh` | human, CI | 38 assertions in a throwaway repo (guard allow/deny, stop gate, logging, redaction) |

`install.sh <target> [--force]` (repo root) copies the template files into another repo.

## Workflows (`.github/workflows/`)

| File | Purpose |
|---|---|
| `copilot-setup-steps.yml` | Prepares the cloud agent environment. The job must be named `copilot-setup-steps`. Runs `setup.sh` |
| `ci.yml` | Jobs `verify` (setup + `check.sh`), `hooks-selftest`, `guardrails-unchanged` (agent/copilot branches only) |

## Hook events (`.github/hooks/factory.json`)

| Event | Script | Timeout | Notes |
|---|---|---|---|
| `sessionStart`, `sessionEnd` | `log.sh` | 10s | Also written to `index.jsonl` |
| `userPromptSubmitted` | `log.sh` | 10s | |
| `preToolUse` | `guard.sh` | 15s | Logs + allow/deny |
| `postToolUse`, `postToolUseFailure` | `log.sh` | 10s | |
| `subagentStart`, `subagentStop` | `log.sh` | 10s | |
| `preCompact`, `errorOccurred` | `log.sh` | 10s | |
| `agentStop` | `stop-gate.sh` | 20s | Blocks once if unverified |

`common.sh` provides `factory_log`, `factory_redact`, `factory_state_hash`, `factory_has_changes`, `factory_context`.

## Policy files (`.github/hooks/policy/`)

- `deny-commands.txt` — case-insensitive extended regexes against shell commands.
- `deny-paths.txt` — regexes against file paths; `write:` prefix = writes only.
Lines starting with `#` are comments. Humans edit; agents cannot.

## Environment variables

| Variable | Used by | Effect |
|---|---|---|
| `FACTORY_STOP_GATE=off` | stop-gate | Disable the stop gate for a session |
| `FACTORY_LOG_DIR` | common.sh | Override log directory |
| `FACTORY_POLICY_DIR` | guard.sh | Override policy directory |
| `FACTORY_BRANCH_PREFIXES` | guard.sh | Branch prefixes allowed to `git push` (default `agent/ copilot/`) |
| `FACTORY_WORKTREE_ROOT` | run-issue | Worktree parent (default `../<repo>-worktrees`) |
| `COPILOT_EXTRA_FLAGS` | run-issue | Extra flags for autonomous runs |

## Log format

One JSON line per event in `.agent-logs/<sessionId>.jsonl`: `ts`, `event`, `branch`, `surface` (`cloud` or `cli`), the hook payload (strings clipped to 4000 chars), and for `preToolUse` `decision` (`allow`/`deny`) and `reason`. `index.jsonl` records session start/end. Useful queries are in [usage-guide.md](usage-guide.md#logs).

## Guard decision contract

Print `{"permissionDecision":"deny","permissionDecisionReason":"…"}` to deny; print nothing to allow. Non-zero exit = deny; timeout = allow.
