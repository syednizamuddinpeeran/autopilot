# Usage Guide

## 1. Prerequisites

Cloud runs need only a GitHub repo with the Copilot cloud agent enabled. Local runs (WSL Ubuntu / macOS / Linux) also need:

```bash
sudo apt-get install -y git jq
npm install -g @github/copilot
gh auth login
copilot            # sign in; then enable the sandbox — see sandboxing.md
```
Keep repos in the WSL filesystem (`~/code/...`), not `/mnt/c/...`. Native Windows is unsupported (hooks are bash).

## 2. Install into a repository

```bash
./install.sh /path/to/repo           # skips files that already exist
./install.sh /path/to/repo --force   # overwrites template files
```
Requires a git repo with at least one commit. Appends `.agent-logs/` and `.agent-work/` to `.gitignore`, makes scripts executable.

## 3. Configure

1. `scripts/factory/commands.env`: `BASE_BRANCH`, `SETUP_CMD`, `FORMAT_CHECK_CMD`, `LINT_CMD`, `TYPECHECK_CMD`, `TEST_CMD`, `BUILD_CMD`. Empty = skipped. Presets for Python, TypeScript, Java, .NET and CDK are in the file. If all are empty, `check.sh` fails (exit 3) unless `ALLOW_NO_CHECKS=1`.
2. `AGENTS.md` → **Project** section: what the repo is, stack, layout, conventions.
3. `.github/workflows/copilot-setup-steps.yml` and `ci.yml`: uncomment the language runtime(s) the project needs.

Then verify and commit to the base branch *before* running agents:
```bash
bash scripts/factory/test-hooks.sh && bash scripts/factory/check.sh
git add -A && git commit -m "chore: add agent factory" && git push
```

## 4. One-time GitHub setup

1. Enable the Copilot cloud agent for the repo.
2. Merge the template into the default branch. Custom agents appear in the agent dropdown, and `copilot-setup-steps.yml` runs, only from the default branch.
3. Branch protection / ruleset on the base branch: require a PR, ≥1 human approval, required checks `verify`, `hooks-selftest`, `guardrails-unchanged`; block force-push; no bypass for bots. GitHub already stops the person who assigned the issue from approving Copilot's PR.
4. Recommended: a `CODEOWNERS` entry for `.github/`, `scripts/factory/` and `AGENTS.md` with "Require review from Code Owners", so guardrail edits need your approval even where CI does not check them.
5. Keep the cloud agent firewall on with the recommended allowlist (Settings → Copilot → Internet access); add hosts only when needed.
6. Do not add AWS or production secrets as **Agents** secrets/variables (Settings → Secrets and variables → Agents). The cloud agent cannot see Actions secrets.

## 5. Create an issue

Use the **Agent task** form: Goal, Acceptance criteria (Given/when/then — make them automatically testable), Out of scope, Pointers, Risk. It applies the `agent-ready` label.

Tips: one outcome per issue; name real files in Pointers; mark risk `high` for auth, payments, migrations, public APIs, infra (result will be a draft PR).

## 6. Run

**Cloud:** assign the issue to Copilot and choose the **factory** agent from the dropdown. It works on a `copilot/*` branch (the only branch it can push to) and opens the PR. By default, CI does not run on Copilot's pushes until someone with write access clicks **Approve and run workflows** — read the diff first, because CI executes branch code.

**Local:**
```bash
scripts/factory/run-issue.sh 42            # autonomous
scripts/factory/run-issue.sh 42 --watch    # interactive; you switch to autopilot
```
This fetches the issue with `gh`, creates `../<repo>-worktrees/issue-42` on `agent/issue-42-<slug>` from `origin/<base>` (or reuses it), runs `setup.sh`, and starts `copilot --agent factory`. Autonomous mode sets `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true` (in `-p` mode the CLI otherwise skips repository hooks in an untrusted folder, and the new worktree is untrusted) and adds `--allow-all-tools` plus CLI-level denies for `git push --force`, `gh pr merge`, `sudo`; extra flags via `COPILOT_EXTRA_FLAGS`. Flag names can change between CLI versions — check `copilot help permissions`.

## 7. Review and merge

Use [human-safety-checklist.md](human-safety-checklist.md). Local run artifacts:
```bash
cat ../<repo>-worktrees/issue-42/.agent-work/issue-42/review.md
jq -c 'select(.decision=="deny")' ../<repo>-worktrees/issue-42/.agent-logs/*.jsonl
```
Merge the PR on GitHub once CI is green and you have approved it. Agents never merge; the cloud agent cannot mark its PR ready for review, approve it or merge it.

## 8. Clean up (local)

```bash
git worktree remove ../<repo>-worktrees/issue-42 && git branch -d agent/issue-42-<slug>
```

## Logs

- Local: `.agent-logs/<sessionId>.jsonl` and `.agent-logs/index.jsonl`.
- Cloud: the environment is destroyed after the job, so hook logs are discarded. Use the agent session log on GitHub.

```bash
jq -c 'select(.event=="preToolUse") | {ts, tool: .toolName, decision, reason}' .agent-logs/*.jsonl
jq -c 'select(.decision=="deny")' .agent-logs/*.jsonl
jq -c 'select(.event|test("subagent")) | {ts, event, agentName}' .agent-logs/*.jsonl
```
