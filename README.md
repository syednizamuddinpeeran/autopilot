# Agent Factory Template (GitHub Copilot)

Reusable setup that takes a GitHub issue to a reviewed pull request with Copilot agents,
running with full tool permissions inside guardrails, with every agent action logged.

```
Issue (agent-task form)
  └─ factory agent (orchestrator, small context)
       ├─ skill: issue-intake        → .agent-work/issue-N/brief.md
       ├─ planner subagent           → plan.md         (read-only on code)
       ├─ implementer subagent ×T    → 1 commit per task, test-first
       ├─ skill: verify-changes      → scripts/factory/check.sh
       ├─ reviewer subagent          → review.md       (independent, read-only)
       └─ skill: open-pr             → PR "Closes #N", human merges
Hooks on every step → .agent-logs/<session>.jsonl
```

Same files drive both surfaces: **Copilot cloud agent** (assign the issue on GitHub) and **Copilot CLI** (local, WSL).

## Why this is safe with "allow all"

| Layer | What it stops | Where |
|---|---|---|
| Isolation | Agent touching your main checkout or machine | Cloud: ephemeral VM. Local: git worktree + CLI sandbox |
| Guard hook (`preToolUse`) | Force-push, push to main, deploys, `sudo`, secret reads, curl\|sh, editing hooks/workflows, log tampering | `.github/hooks/scripts/guard.sh` + `policy/*.txt` |
| Stop gate (`agentStop`) | Finishing with unverified changes | `stop-gate.sh` + `check.sh` marker |
| CI | Anything the agent claims but didn't do | `.github/workflows/ci.yml` |
| Branch protection | Agent merging its own work | GitHub settings (below) |
| No standing secrets | Credential theft / cloud damage | Don't give agents AWS or prod credentials |

The guard is fail-closed on errors, but a hook **timeout is fail-open** — keep the scripts fast.
Deny-lists reduce risk; they are not a complete sandbox. Isolation and branch protection are the real boundary.

## One-time setup

### GitHub (per repo, or once at org level)
1. Enable Copilot cloud agent for the repo.
2. Branch protection / ruleset on `main`: require PR, ≥1 human approval, required checks
   `verify`, `hooks-selftest`, `guardrails-unchanged`; block force-push; no bypass for bots.
3. Keep the cloud agent firewall at its default (GitHub + package registries). Add hosts only when needed.
4. Do not add AWS or production secrets as Agents secrets/variables (Settings → Secrets and variables → Agents).
5. Merge the template to the default branch first: the `factory` agent and `copilot-setup-steps.yml` are only picked up from there.

### Your machine (WSL Ubuntu)
```bash
sudo apt-get install -y git jq
# GitHub CLI: https://cli.github.com   Copilot CLI: npm install -g @github/copilot
gh auth login
copilot          # sign in, then inside the session:
/sandbox enable  # turn on local sandboxing (persists in settings)
/sandbox config  # turn off "Allow sandbox bypass"; don't grant ~/.ssh or ~/.aws
/sandbox policy  # check the effective policy
```
Keep repos in the WSL filesystem (`~/code/...`), not `/mnt/c/...` — faster, and hooks run as bash.

## Per-project changes (the only things you edit)
1. `scripts/factory/commands.env` — setup, format, lint, typecheck, test, build commands (presets included).
2. `AGENTS.md` → **Project** section — what the repo is, layout, conventions.
3. `.github/workflows/copilot-setup-steps.yml` and `ci.yml` — uncomment the language runtime.

Optional: tune `.github/hooks/policy/deny-*.txt`, pin `model:` per agent, add project-specific skills in `.github/skills/`.

Install into an existing repo:
```bash
./install.sh ~/code/my-repo
cd ~/code/my-repo && bash scripts/factory/test-hooks.sh && bash scripts/factory/check.sh
```

## Running

**Cloud (recommended for autonomy):** create an issue with the *Agent task* form → Assign to Copilot →
choose the **factory** agent. It works on a `copilot/*` branch and opens the PR.

**Local (WSL):**
```bash
scripts/factory/run-issue.sh 42          # autonomous run in ../<repo>-worktrees/issue-42
scripts/factory/run-issue.sh 42 --watch  # interactive; switch to autopilot yourself
```
Flag names (`--agent`, `-p`, `--allow-all-tools`, `--deny-tool`) can change between CLI versions —
check `copilot help permissions` once and adjust `run-issue.sh` if needed.

Full documentation: [docs/](docs/README.md).

## Logs
- Local: `.agent-logs/<sessionId>.jsonl` (one JSON line per event) and `.agent-logs/index.jsonl` (session start/end).
- Cloud: the sandbox is destroyed after the job, so hook logs there are discarded. Use the agent
  session log on GitHub, or later add an `http` hook to ship logs out.

```bash
jq -c 'select(.event=="preToolUse") | {ts, tool: .toolName, decision, reason}' .agent-logs/*.jsonl
jq -c 'select(.decision=="deny")' .agent-logs/*.jsonl          # everything the guard blocked
jq -c 'select(.event|test("subagent")) | {ts, event, agentName}' .agent-logs/*.jsonl
```

## Files
```
AGENTS.md                         always-loaded rules (kept short)
.github/agents/*.agent.md         factory, planner, implementer, reviewer
.github/skills/*/SKILL.md         loaded only when needed → clean context
.github/hooks/factory.json        hook wiring for all events
.github/hooks/scripts/            log.sh, guard.sh, stop-gate.sh, common.sh
.github/hooks/policy/             deny-commands.txt, deny-paths.txt
.github/workflows/                copilot-setup-steps.yml, ci.yml
.github/ISSUE_TEMPLATE/           agent-task.yml
scripts/factory/                  commands.env, check.sh, setup.sh, run-issue.sh, test-hooks.sh
```

## Known limits
- Edits made through shell commands (e.g. `sed -i`) bypass path rules, but the stop gate and CI still catch unverified changes.
- `.env.example` is blocked by the `.env` rule; rename it (e.g. `env.example`) or edit `deny-paths.txt`.
- Native Windows needs PowerShell versions of the hooks; this template targets WSL, macOS, Linux, and the cloud agent.
