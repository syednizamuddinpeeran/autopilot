# Copilot CLI Local Sandboxing

Local sandboxing is the OS-level layer under this repo's hooks. It is a **public-preview** feature of GitHub Copilot CLI, so behaviour and flags may change — always check the current GitHub documentation:

- [About cloud and local sandboxes](https://docs.github.com/en/copilot/concepts/about-cloud-and-local-sandboxes)
- [Using local sandboxing](https://docs.github.com/en/copilot/how-tos/cloud-and-local-sandboxes/using-local-sandboxing)
- [Configuring local sandbox settings](https://docs.github.com/en/copilot/how-tos/cloud-and-local-sandboxes/configuring-local-sandbox-settings)
- [Copilot CLI hooks reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference) (the `preToolUse` hook used by `guard.sh`)

> The summaries below are based on those pages as of writing; verify against them before relying on a detail.

## Setup steps

1. Install and sign in: `npm install -g @github/copilot`, then `copilot`.
2. Sandboxing is experimental: start with `copilot --experimental` or run `/experimental on` in a session.
3. Run `/sandbox enable`. It applies to the current session immediately and persists for later sessions until disabled (`/sandbox disable`, or `--no-sandbox` per session — unless enterprise-managed settings require it).
4. Run `/sandbox` for the settings UI: **General**, **Filesystem**, **Network** tabs.
5. Run `/sandbox policy` to see the *effective* filesystem policy (settings + automatic grants + any managed policy).
6. For this project (local runs via `run-issue.sh`): keep the working directory (and the sibling `<repo>-worktrees/` directory) read/write; deny `~/.ssh` and `~/.aws`; consider restricting network to the domains your task and package manager need.
7. Check platform support in the docs (macOS and Linux; Windows support is newer and has gaps).

## What it gives us

By default, sandboxed commands and tools can **write only within the current working directory and temp folders**; your home directory, system and tool locations are **read-only**; other locations are blocked. Specifically for this factory:

| Benefit | Why it matters here |
|---|---|
| Kernel/OS-enforced limits | Holds even when a shell command evades the regex deny-lists in `guard.sh` |
| Writes confined to the worktree | A runaway `rm`, `sed -i` or script cannot damage your home directory or other repos |
| Denied paths (`~/.ssh`, `~/.aws`) | Protects secrets even if a `cat` is obfuscated |
| Credential placeholders | Sandboxed commands receive placeholder Git/`gh` credentials; a local proxy injects real ones only for approved HTTPS destinations (can be turned off in `/sandbox` config) |
| Network allow/deny domain lists | Limits where data can be sent or code fetched from |
| Enterprise policy | Organisations can require sandboxing so it cannot be disabled locally |

## What it does *not* do (per GitHub's documentation and write-ups)

GitHub describes sandboxing as **reducing the impact of unintended commands, not a guarantee** an agent cannot cause harm.

- **Outbound network is on by default.** Enabling the sandbox alone does not block traffic; domain lists only filter once you configure them. Exact hosts match only that host; `*.example.com` does not match `example.com`.
- **Built-in file tools** run inside the (unsandboxed) CLI process and enforce the policy on a best-effort basis — which is why the hook-level path rules still matter.
- **Remote MCP servers are never sandboxed.**
- **Local-network/localhost** behaviour differs by platform (e.g. Linux sandboxed processes cannot connect directly to localhost servers).
- **Windows** coverage is weaker/different; this template targets WSL, macOS, Linux (and the cloud agent).
- It does not judge *what* the agent writes inside the worktree — malicious or wrong code in the diff is still your job to catch.
- It does not apply to the cloud agent, which has its own ephemeral environment and firewall.

## How the layers fit together

| Risk | Sandbox | Hooks (`guard.sh`) | Human |
|---|---|---|---|
| Write outside worktree | **Primary** | path rules for file tools | — |
| Read `~/.ssh`, `~/.aws` | **Primary** | regex + path rules | — |
| Force-push, `gh pr merge`, admin `gh` calls | network/credentials | **Primary** (deny list, push rule) + CLI `--deny-tool` | branch protection |
| Cloud deploys | network limits | **Primary** (terraform/cdk/aws/kubectl patterns) | no creds in env |
| Editing guardrails | writes allowed inside worktree! | **Primary** (`write:` rules) | CI `guardrails-unchanged` + your review |
| Weak/malicious code in diff | — | reviewer agent, stop gate | **Primary** |
| Running branch code in CI | — | — | **Primary** (read diff first) |
| Exfiltration over network | allow-list (if configured) | partial | review logs |

Note the guardrail files live *inside* the worktree, so the sandbox cannot protect them — only the hooks, CI and your review do.

## What you should still do

See [human-safety-checklist.md](human-safety-checklist.md). In short: configure the network list, keep secrets out of the environment, read the diff and logs, and review anything under `.github/` and `scripts/` in the PR before merging.
