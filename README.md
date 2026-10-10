# Autopilot — Agent Factory Template

Reusable setup that takes a piece of work — a GitHub issue or a local task file — to a verified, reviewed change, with coding agents running autonomously inside guardrails and every action logged. A human always merges.

```
Issue / task file
  └─ factory agent (orchestrator, small context)
       ├─ skill: issue-intake | task-intake  → .agent-work/<id>/brief.md
       ├─ planner subagent                    → plan.md        (read-only on code)
       ├─ implementer subagent ×T             → 1 commit per task, test-first
       ├─ skill: verify-changes               → scripts/factory/check.sh
       ├─ reviewer subagent                   → review.md      (independent)
       └─ skill: open-pr | handoff            → PR "Closes #N" | handoff.md
Hooks on every tool call → guard (allow/deny) + audit log; stop gate until verified
Human merges: branch protection + CI | accept.sh
```

## One template, your combination

```bash
./install.sh ~/code/my-repo [--repo github|local] [--os linux|wsl|windows] \
                            [--assistant copilot|claude-code] [--cloud none|aws]
pwsh ./install.ps1 C:\code\my-repo [-Repo …] [-Os …] [-Assistant …] [-Cloud …]   # same result
```

| Choice | Options | Docs |
|---|---|---|
| Repo type | `github` (default): issue → PR, cloud agent or local CLI, CI + branch protection · `local`: task file → local branch, no remote | [usage-guide](docs/usage-guide.md), [local-repo](docs/local-repo.md) |
| OS | `linux` / `wsl`: bash · `windows`: + PowerShell 7 hooks and scripts | [platforms](docs/platforms.md) |
| Assistant | `copilot` (default): Copilot cloud agent + CLI · `claude-code`: Claude Code CLI + GitHub Action | [claude-code](docs/claude-code.md) |
| Cloud | `none` (default) · `aws`: credential-free agents, AWS deny rules, OIDC deploy from CI | [aws](docs/aws.md) |

Full option reference: [docs/install.md](docs/install.md). Start here: [docs/README.md](docs/README.md).

## Why this is safe with "allow all"

| Layer | What it stops |
|---|---|
| Isolation | Cloud: ephemeral runner, own branch. Local: git worktree + CLI sandbox |
| Guard hook (`preToolUse`) | Force-push / push to base, deploys, `sudo`, secret reads, `curl \| sh`, editing hooks/policy/workflows/agents, log tampering — same policy files for bash and PowerShell, Copilot and Claude Code |
| Stop gate | Finishing with changes that have not passed `check.sh` since the last edit |
| CI / `accept.sh` | Claims the agent did not earn; agent changes to guardrail files |
| Branch protection / human merge | Agents merging their own work |
| No standing credentials | Credential theft and cloud damage (`--cloud aws` enforces it for local runs) |

Deny-lists reduce risk; they are not a sandbox. Isolation, keeping credentials out, and the human merge are the real boundary. Details: [security-model](docs/security-model.md), [human-safety-checklist](docs/human-safety-checklist.md).

## Quick start (GitHub + Copilot)

```bash
./install.sh ~/code/my-repo && cd ~/code/my-repo
# edit scripts/factory/commands.env and the Project section of AGENTS.md
bash scripts/factory/test-hooks.sh && bash scripts/factory/check.sh
git add -A && git commit -m "chore: add agent factory" && git push
```
Then: enable the Copilot cloud agent, protect `main` ([usage-guide §4](docs/usage-guide.md#4-one-time-github-setup)), create an issue with the **Agent task** form and assign it to Copilot with the **factory** agent — or run it locally with `scripts/factory/run-issue.sh <N>`.

## This repository

```
install.sh, install.ps1           compose the layers and copy them into a target repo
template/core/                    files every installation gets
template/repo/{github,local}/     repo types
template/os/windows/              PowerShell 7 hooks and scripts
template/assistant/{copilot,claude-code}/   agents, skills and hook wiring per assistant
template/cloud/aws/               AWS guardrails and deploy workflow
tests/                            install-matrix.sh/.ps1, installer-parity.sh, check-assistant-sync.sh, check-links.sh
.github/workflows/selftest.yml    CI for this repo only (not installed)
docs/                             documentation
```
How layers combine: [docs/install.md](docs/install.md#how-the-template-is-built-for-maintainers). Contributor rules: [AGENTS.md](AGENTS.md).

## Known limits
- Shell is expressive: edits through `sed -i`, scripts or other runtimes can bypass path rules. The stop gate, CI / `accept.sh` and your review catch unverified or guardrail changes.
- A Copilot hook timeout lets the call through; Claude Code's guard is wired to block on failure.
- `.env.example` is blocked by the `.env` rule; rename it (e.g. `env.example`) or edit `deny-paths.txt`.
