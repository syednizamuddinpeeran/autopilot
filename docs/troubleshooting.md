# Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Missing: gh/copilot/jq/git` | Tool not installed | Install it (see usage-guide) |
| `No checks configured` (exit 3) | All commands empty in `commands.env` | Configure them, or `ALLOW_NO_CHECKS=1` for docs-only repos |
| Copilot rejects flags | CLI flag names changed | `copilot help permissions`; adjust `run-issue.sh` (human edit) |
| Cloud agent can't build/test | Runtime missing in its environment | Uncomment the runtime in `copilot-setup-steps.yml`; the job must be named `copilot-setup-steps` and the file must be on the default branch |
| `factory` agent missing from the dropdown | Agent file not on the default branch | Merge `.github/agents/` into the default branch and refresh |
| CI never starts on a Copilot PR | Workflow runs need approval by default | Read the diff, then click **Approve and run workflows** |
| Local run: no `.agent-logs`, nothing blocked | Repository hooks not loaded in `-p` mode | Use `run-issue.sh` (sets `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true`) or trust the folder |
| "Blocked by factory guard" in the agent output | Policy matched a command/path | Check the `reason` in `.agent-logs`; if legitimate, change the issue approach or adjust the policy files yourself — the agent cannot |
| Legit command blocked (e.g. `.env.example`, a word matching `\bgh\b`) | Regex too broad | Narrow the pattern in `policy/` and rerun `test-hooks.sh` |
| Agent keeps being told to verify | Stop gate: changes since last green `check.sh` | Run `check.sh` and fix failures; the marker is invalidated by any edit |
| CI `guardrails-unchanged` fails | Agent PR touched hooks, workflows, `check.sh` or `commands.env` | Make that change yourself in a separate PR; revert it from the agent PR |
| PR is Draft | High risk, failed verification, or open questions | Read Risks and questions; refine the issue and rerun |
| Hooks seem not to run | Not in the repo/worktree where Copilot starts, or scripts not executable | Run `scripts/factory/setup.sh`; confirm `.github/hooks/factory.json` is on the branch the agent uses |
| Hook slow → a call slipped through | Timeout is fail-open | Keep policy files small; avoid heavy work in hooks |
| Sandbox blocks a legitimate write | Path outside allowed dirs | Add the path in `/sandbox config` → Filesystem, or move work inside the worktree |
| `/sandbox` says unavailable on Linux/WSL | Missing `bwrap` (≥ 0.5.0), `slirp4netns` or other requirements | Install them; see [sandboxing.md](sandboxing.md#platform-requirements) |
| Different results on `/mnt/c` | Slow filesystem, line endings | Use the WSL filesystem |
