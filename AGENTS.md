# AGENTS.md (this template repository)

This repo *is* the agent-factory template; it is not an installed copy.

- Template files live under `template/` in layers (`core`, `repo/<type>`). `install.sh` composes them.
  Edit the layer, never an installed copy. Files ending in `.append` extend the base file.
- `.github/workflows/selftest.yml` is this repo's own CI and is not installed.
- Before pushing run: `bash tests/install-matrix.sh`, `bash tests/check-links.sh`, and
  `shellcheck --severity=warning --shell=bash` on every `*.sh`.
- Keep `docs/` in step with any behaviour change.
