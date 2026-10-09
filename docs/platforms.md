# Platforms: Linux, WSL, native Windows

Choose with `--os` (`install.sh`) or `-Os` (`install.ps1`). Both installers produce the same files for the same options.

| `--os` | Hooks and scripts installed | Use when |
|---|---|---|
| `linux` (default for `install.sh`) | bash (`*.sh`) | Linux, macOS, and the cloud agent |
| `wsl` | bash (`*.sh`) — same files as `linux` | Windows with WSL 2 Ubuntu |
| `windows` (default for `install.ps1`) | bash **and** PowerShell 7 (`*.ps1`) | Native Windows, no WSL |

The bash files are always installed: the Copilot **cloud agent** runs on Linux and only honours the `bash` field of each hook. With `--os windows`, `factory.json` has both a `bash` and a `powershell` command per hook; the CLI on Windows runs the `powershell` one.

## Linux / macOS

`git`, `jq`, Node.js (for `npm install -g @github/copilot`), and `gh` for the GitHub variant. Sandbox requirements: [sandboxing.md](sandboxing.md#platform-requirements).

## WSL

Same as Linux, inside the WSL distro.

- Keep repos in the WSL filesystem (`~/code/...`), not `/mnt/c/...` — faster, correct file modes and line endings.
- Install the tools inside WSL, not on Windows.
- GitHub's sandbox docs do not cover WSL; it behaves as Linux when the Linux requirements (`bwrap` ≥ 0.5.0 and friends) are met.

## Native Windows

### Prerequisites

- **PowerShell 7+** (`pwsh`). The hooks run `pwsh -NoProfile -ExecutionPolicy Bypass -File …`; Windows PowerShell 5.1 is not supported.
- Git for Windows, Node.js, `npm install -g @github/copilot`, and `gh` for the GitHub variant.
- No `jq` or bash needed.
- For local sandboxing: a recent Windows 11 build (see [sandboxing.md](sandboxing.md#platform-requirements)). Network host rules on Windows rely on programs honouring proxy settings, so they are weaker than on Linux/macOS.

### Install and run

```powershell
pwsh ./install.ps1 C:\code\my-repo -Repo github     # or -Repo local
cd C:\code\my-repo
# edit scripts\factory\commands.env and the Project section of AGENTS.md
pwsh scripts/factory/test-hooks.ps1; pwsh scripts/factory/check.ps1
```

| bash (Linux/WSL) | PowerShell (Windows) |
|---|---|
| `scripts/factory/run-issue.sh 42 [--watch]` | `pwsh scripts/factory/run-issue.ps1 42 [-Watch]` |
| `scripts/factory/run-task.sh <id> [--watch]` | `pwsh scripts/factory/run-task.ps1 <id> [-Watch]` |
| `scripts/factory/accept.sh <id> [--allow-guardrails]` | `pwsh scripts/factory/accept.ps1 <id> [-AllowGuardrails]` |
| `bash scripts/factory/check.sh` | `pwsh scripts/factory/check.ps1` |
| `bash scripts/factory/setup.sh` | `pwsh scripts/factory/setup.ps1` |
| `bash scripts/factory/test-hooks.sh` | `pwsh scripts/factory/test-hooks.ps1` |

Commands in `commands.env` are run with `pwsh -Command` on Windows and `bash -c` elsewhere; keep them to tool invocations (`npm test`, `dotnet test`, `uv run pytest`) that work in both.

### How the PowerShell port matches the bash one

- `guard.ps1` reads the **same** `deny-commands.txt`, `deny-paths.txt` and `git-rules.env`, and returns the same decisions. `--os windows` appends PowerShell/cmd patterns to `deny-commands.txt` (e.g. `Remove-Item -Recurse C:\`, `Start-Process -Verb RunAs`, `irm … | iex`, `Get-Content .env`, `Get-ChildItem env:`).
- Paths are normalised (`\` → `/`) and matched case-insensitively.
- `test-hooks.ps1` runs the same `hook-cases.txt` as `test-hooks.sh`, with `toolName: powershell`.
- `check.ps1` and `stop-gate.ps1` share their own state-hash function, so verify with `check.ps1` on Windows (a marker written by `check.sh` is not recognised by `stop-gate.ps1`, and the other way round).

### Known limits on Windows

- PowerShell is even more expressive than bash; the deny-lists are a speed bump, not a sandbox. The sandbox, branch protection / `accept.ps1`, and your review remain the boundary.
- Each hook starts `pwsh`, which adds roughly half a second per tool call.
- `cmd.exe` built-ins are only partly covered by the patterns.
