# Copilot CLI Local Sandboxing

Local sandboxing is the OS-level layer under this repo's hooks for **local** runs (`run-issue.sh`). The cloud agent does not use it; it runs in GitHub's ephemeral environment behind its own firewall. Behaviour changes between CLI releases, so check the current GitHub documentation:

- [About cloud and local sandboxes](https://docs.github.com/en/copilot/concepts/about-cloud-and-local-sandboxes)
- [Using local sandboxing](https://docs.github.com/en/copilot/how-tos/cloud-and-local-sandboxes/using-local-sandboxing)
- [Configuring local sandbox settings](https://docs.github.com/en/copilot/how-tos/cloud-and-local-sandboxes/configuring-local-sandbox-settings)
- [Copilot CLI hooks reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference) (the `preToolUse` hook used by `guard.sh`)

> Checked against those pages in October 2026.

## Platform requirements

| OS | Backend | Requirements |
|---|---|---|
| Linux | bubblewrap | `bwrap` ≥ 0.5.0 on `PATH`. With outbound network allowed also `slirp4netns`, util-linux ≥ 2.35 (`unshare`, `nsenter`), `iptables`/`ip6tables` (nf_tables) and `/dev/net/tun` |
| macOS | Seatbelt | macOS 15 or later recommended |
| Windows | Windows sandbox APIs | A recent Windows 11 update; denied paths, localhost and proxy support depend on the build |
| WSL | (Linux) | Not covered by GitHub's docs; it behaves as Linux if the Linux requirements above are met |

## Setup steps

1. Install and sign in: `npm install -g @github/copilot`, then `copilot`.
2. Run `/sandbox enable`. It is saved as `sandbox.enabled` in `~/.copilot/settings.json` and applies to later sessions, including `-p` runs, until `/sandbox disable`. `--sandbox` / `--no-sandbox` override it for one session (an enterprise policy can force it on).
3. Run `/sandbox config` (or just `/sandbox`) for the settings: **General**, **Credentials**, **Filesystem**, **Network** tabs.
4. Run `/sandbox status` to confirm it is on, and `/sandbox policy` to see the *effective* paths and network settings.
5. For this project:
   - Keep the worktree directory (`../<repo>-worktrees/…`) writable — it is the working directory of each run.
   - Don't grant access to `~/.ssh`, `~/.aws` or other credential folders (they are not granted by default).
   - Turn **Allow sandbox bypass** off (General tab). It is on by default and lets the agent ask to re-run a blocked command outside the sandbox.
   - Consider network **Allow** rules for only the hosts your package manager and GitHub need.
   - To force the sandbox for autonomous runs regardless of saved settings: `COPILOT_EXTRA_FLAGS=--sandbox scripts/factory/run-issue.sh <N>`.

## What it gives us

By default, sandboxed commands can **write only to the current working directory, temp folders and the repo's Git metadata**; selected system and developer-tool locations are readable; the rest of your home directory is **not granted**. Specifically for this factory:

| Benefit | Why it matters here |
|---|---|
| OS-enforced limits | Holds even when a shell command evades the regex deny-lists in `guard.sh` |
| Writes confined to the worktree | A runaway `rm`, `sed -i` or script cannot damage your home directory or other repos |
| Home directory not granted | Protects `~/.ssh`, `~/.aws` even if a `cat` is obfuscated |
| Credential placeholders | Sandboxed commands receive placeholder Git/`gh` credentials; a local proxy injects real ones only for approved HTTPS destinations (`gh`: `github.com`, `api.github.com`, `uploads.github.com`). Can be turned off on the Credentials tab |
| Network host rules | Once you add an Allow rule, other hosts are blocked. On macOS/Linux all traffic is forced through the proxy |
| Enterprise policy | Organisations can require sandboxing so it cannot be disabled locally |

## What it does *not* do

GitHub describes sandboxing as reducing the impact of unintended commands, not a guarantee.

- **Outbound internet is on by default.** It is only filtered once you add host rules.
- **Built-in file tools** run inside the (unsandboxed) CLI process and honour the policy on a best-effort basis — which is why the hook-level path rules still matter.
- **Remote MCP servers are never sandboxed.**
- **Hooks run on the host**, outside the sandbox (that is what lets `guard.sh` read the policy files).
- **Localhost:** on Linux, sandboxed processes cannot connect directly to servers on your machine's localhost.
- **Windows:** host rules rely on programs honouring proxy settings, so they are weaker than on macOS/Linux.
- **Credential masking** does not hide secrets in credential files or other environment variables.
- It does not judge *what* the agent writes inside the worktree — wrong or malicious code in the diff is still your job to catch.

## How the layers fit together

| Risk | Sandbox | Hooks (`guard.sh`) | Human / GitHub |
|---|---|---|---|
| Write outside worktree | **Primary** | path rules for file tools | — |
| Read `~/.ssh`, `~/.aws` | **Primary** | regex + path rules | — |
| Force-push, `gh pr merge`, admin `gh` calls | credential/network limits | **Primary** (deny list, push rule) + CLI `--deny-tool` | branch protection |
| Cloud deploys | network limits | **Primary** (terraform/cdk/aws/kubectl patterns) | no creds in env |
| Editing guardrails | writes allowed inside worktree! | **Primary** (`write:` rules) | CI `guardrails-unchanged` + your review |
| Weak/malicious code in diff | — | reviewer agent, stop gate | **Primary** |
| Running branch code in CI | — | — | **Primary** (read the diff before approving workflow runs) |
| Exfiltration over network | host allow rules (if configured) | partial | review logs |

The guardrail files live *inside* the worktree, so the sandbox cannot protect them — only the hooks, CI and your review do.

## What you should still do

See [human-safety-checklist.md](human-safety-checklist.md). In short: configure network rules, turn off sandbox bypass, keep secrets out of the environment, read the diff and logs, and review anything under `.github/` and `scripts/` in the PR before merging.
