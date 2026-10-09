# Claude Code (`--assistant claude-code`)

The same factory — agents, skills, guard, stop gate, logging, `check.sh` — driven by [Claude Code](https://code.claude.com/docs) instead of GitHub Copilot.

```bash
./install.sh ~/code/my-repo --repo github --assistant claude-code     # or --repo local, --os windows
```

## What changes

| | Copilot (`--assistant copilot`, default) | Claude Code (`--assistant claude-code`) |
|---|---|---|
| Agents | `.github/agents/*.agent.md` | `.claude/agents/*.md` (same bodies; Claude tool names in `tools:`) |
| Skills | `.github/skills/*/SKILL.md` | `.claude/skills/*/SKILL.md` (same files) |
| Hook wiring | `.github/hooks/factory.json` | `.claude/settings.json` → same scripts in `.github/hooks/scripts/` |
| Project instructions | `AGENTS.md` | `AGENTS.md` (Claude Code reads it when there is no `CLAUDE.md`) |
| CLI-level denies | `--deny-tool 'shell(…)'` | `permissions.deny` in `settings.json` + `--disallowedTools` |
| Local run | `copilot --agent factory -p … --allow-all-tools` | `claude --agent factory --permission-mode bypassPermissions -p …` |
| Cloud (GitHub repos) | Copilot cloud agent, `copilot/*` branch, opens the PR | `claude-factory.yml` (anthropics/claude-code-action), `claude/*` branch, posts a link to open the PR |
| Extra write-protected paths | — | `.claude/`, `CLAUDE.md` |

`run-issue.sh` / `run-task.sh` (and the `.ps1` versions) read `ASSISTANT` from `commands.env`, which the installer sets, and start the matching CLI.

## Guard behaviour under Claude Code

Claude Code differs from Copilot in ways that matter for a policy hook ([hooks reference](https://code.claude.com/docs/en/hooks)):

- **Only exit code 2 blocks.** A hook that exits 1, crashes or prints invalid JSON is a *non-blocking* error and the tool call goes ahead. The guard therefore answers Claude-shaped payloads (`tool_name`/`tool_input`) with `hookSpecificOutput.permissionDecision: "deny"`, the reason on stderr, **and exit 2**, and exits 2 on its own errors.
- **`onFailure: "block"`** is set on the `PreToolUse` hook, so a guard that cannot start or times out blocks the call instead of allowing it (Claude Code v2.1.295 or later; older versions ignore the field — keep Claude Code up to date).
- **Hooks load in `-p` mode** even in an untrusted folder, so autonomous runs in a fresh worktree are guarded without extra flags.
- **`bypassPermissions` skips permission prompts, not hooks or deny rules.** The guard and `permissions.deny` still apply.
- **Timeouts:** the hooks set their own (10–20 s); Claude Code's default would be 600 s.
- Tool names covered: `Bash`, `PowerShell` (shell); `Write`, `Edit`, `MultiEdit`, `NotebookEdit` (write); `Read`, `Glob`, `Grep` (read).

`test-hooks.sh` / `test-hooks.ps1` run every case in `hook-cases.txt` in both the Copilot and the Claude payload shape.

## GitHub repos: the Claude GitHub Action

`.github/workflows/claude-factory.yml` runs the factory with `anthropics/claude-code-action@v1` when an issue gets the `agent-ready` label (the Agent task form adds it) or someone with write access comments `@claude`.

One-time setup:
1. Install the Claude GitHub App on the repository (`/install-github-app` in Claude Code, or see the [GitHub Actions docs](https://code.claude.com/docs/en/github-actions)).
2. Add the `ANTHROPIC_API_KEY` repository secret (or `CLAUDE_CODE_OAUTH_TOKEN` and switch the input in the workflow).
3. Uncomment the language runtime in the workflow (keep it in step with `ci.yml`).
4. Branch protection as for Copilot; `claude/*` branches are covered by `guardrails-unchanged`.

Notes:
- The action only acts for users with write access by default; don't enable `allowed_non_write_users`.
- On pull-request events it restores `.claude/` from the base branch, so a PR cannot swap in its own hooks.
- Claude pushes to its `claude/*` branch and posts a link to open the PR; it does not merge.
- The runner has the API key in its environment; the guard denies `printenv`/`env` and token echoes, but treat the workflow like any CI job that runs branch code.

## Sandboxing

Claude Code has its own sandbox ([sandboxing docs](https://code.claude.com/docs/en/sandboxing)); enable it for local runs the same way you would the Copilot CLI sandbox ([sandboxing.md](sandboxing.md)): writes limited to the worktree, no access to `~/.ssh` or `~/.aws`, network limited to what the task needs.

## Mixing assistants

Install one assistant per repository. Copilot CLI also reads `.claude/settings.json` hooks, so a repo with both `.github/hooks/factory.json` and `.claude/settings.json` runs every hook twice under Copilot (double log lines; decisions stay correct).
