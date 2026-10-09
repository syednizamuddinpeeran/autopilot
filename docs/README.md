# Agent Factory — Documentation

A GitHub issue goes in; a verified, reviewed pull request comes out. A human merges it. Runs on the Copilot cloud agent (assign the issue) or locally with Copilot CLI (`run-issue.sh`).

## Reading order

| If you want to… | Read |
|---|---|
| Get running in 5 minutes | [Quickstart](#quickstart) below, then [usage-guide.md](usage-guide.md) |
| Understand how it works | [architecture.md](architecture.md), [agents-and-skills.md](agents-and-skills.md) |
| Know why it is safe | [security-model.md](security-model.md) |
| Know what *you* must check | [human-safety-checklist.md](human-safety-checklist.md) |
| Understand Copilot CLI sandboxing | [sandboxing.md](sandboxing.md) |
| Use it without GitHub (local repo) | [local-repo.md](local-repo.md) |
| Run on Linux, WSL or native Windows | [platforms.md](platforms.md) |
| Look something up | [reference.md](reference.md) |
| Fix a problem | [troubleshooting.md](troubleshooting.md) |

## Quickstart

```bash
# 1. One-time: tools and sandbox (see sandboxing.md)
sudo apt-get install -y git jq && npm install -g @github/copilot
gh auth login

# 2. Install into a repo (needs ≥1 commit and a GitHub remote)
./install.sh ~/code/my-repo --repo github
cd ~/code/my-repo

# 3. Configure: edit scripts/factory/commands.env and the Project section of AGENTS.md,
#    and uncomment the runtime in .github/workflows/copilot-setup-steps.yml and ci.yml
bash scripts/factory/test-hooks.sh && bash scripts/factory/check.sh
git add -A && git commit -m "chore: add agent factory" && git push

# 4. On GitHub: enable the Copilot cloud agent, protect main (see usage-guide.md)

# 5. Create an issue with the "Agent task" form, then either:
#    cloud: assign it to Copilot and choose the factory agent
#    local: scripts/factory/run-issue.sh 42

# 6. Review the PR and merge it (human only)
```
