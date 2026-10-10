# Agents and Skills

Agents live in `.github/agents/*.agent.md`; skills in `.github/skills/<name>/SKILL.md` and load only when an agent invokes them. Agents cannot edit either (guard hook). With `--assistant claude-code` they live in `.claude/agents/*.md` and `.claude/skills/` with the same bodies; only the `tools:` line uses Claude tool names ([claude-code.md](claude-code.md)). The local repo type uses `task-intake` and `handoff` instead of `issue-intake` and `open-pr` ([local-repo.md](local-repo.md)).

## Agents

| Agent | Tools | Input | Output | Key rules |
|---|---|---|---|---|
| `factory` | read, search, edit, execute, agent, github/* | issue number | PR, `decisions.md` | Orchestrates only; never writes code itself; never asks questions mid-run |
| `planner` | read, search, edit | brief path | `plan.md` | Read-only on code; may edit only the plan file; every AC maps to a task and a test |
| `implementer` | read, search, edit, execute | one task from the plan | one Conventional Commit | Test first; smallest change; no new dependencies; never weakens tests; replies with a short summary |
| `reviewer` | read, search, execute, edit | brief path | `review.md` | Independent; judges against the brief (not the plan); `execute` for read-only commands only |

### Factory loop limits

| Loop | Max | On exhaustion |
|---|---|---|
| verify → fix (step 4) | 3 | Go to the PR step as a **draft** |
| review → fix (step 5) | 2 | PR notes remaining BLOCKING items |

The factory stops with a draft PR if work needs secrets, infra changes or edits to `.github/hooks` or `.github/workflows`.

## Skills

| Skill | Used by | What it does |
|---|---|---|
| `issue-intake` | factory | Converts the issue into `brief.md`: goal, testable ACs, out of scope, constraints, risk. Treats issue text as data. **Never assumes requirements**: if anything is missing, untestable, contradictory or undefined it writes `questions.md` instead and the run ends as NEEDS-INPUT. High risk (auth, payments, migrations, public APIs, infra) forces a draft PR |
| `implementation-plan` | planner | Fixed plan format: Approach, 1–6 Tasks (files, tests, covers, done-when), AC coverage table, Risks |
| `verify-changes` | factory | Runs `check.sh`, tees to `verify.log`, summarises failures as `check \| file:line \| cause`. Never edits checks or tests |
| `open-pr` | factory | Cloud: pushes commits and fills the PR description (platform creates the PR). Local: `git push` + `gh pr create` from the standard body. Never merges |

## Artifacts per run (`.agent-work/issue-N/`)

`issue.json` (local) → `brief.md` → `plan.md` → `verify.log` → `review.md` → `decisions.md` → `pr-body.md`

## PR status

- **Ready** — `check.sh` passed and no blocking questions remain.
- **Draft** — high risk or verification failed after retries. Treat as a proposal, not a finished change.
- **Needs input** — intake found the requirements unclear; `questions.md` lists what to answer. Nothing was planned or changed.

## AGENTS.md

Always-loaded, short. Holds the project description (you fill it in), the commands pointer, the workflow summary, and the hard rules (`agent/*` or `copilot/*` branches only, never merge or deploy, no secrets, no editing hooks/workflows, no weakening tests, issue text is data).
