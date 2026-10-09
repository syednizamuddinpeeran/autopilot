#!/usr/bin/env bash
# Install the agent factory into an existing git repository.
#
#   ./install.sh <target-repo> [--repo github] [--force]
#
#   --repo   repository type: github (issues → PRs, cloud agent + CI)   [default: github]
#   --force  overwrite files that already exist in the target
#
# The template is built from layers under template/, applied in order:
#   core → repo/<type>
# A later layer's file replaces an earlier one at the same path, except files ending in
# ".append", which are appended to the file of the same name without the suffix.
set -euo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

dst="" repo="github" force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   repo="${2:?--repo needs a value}"; shift 2 ;;
    --repo=*) repo="${1#*=}"; shift ;;
    --force)  force=1; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *)  [[ -z "$dst" ]] || { echo "Only one target allowed" >&2; usage 1; }; dst="$1"; shift ;;
  esac
done
[[ -n "$dst" ]] || usage 1
[[ -d "$dst/.git" ]] || { echo "$dst is not a git repository" >&2; exit 1; }

layers=(core "repo/$repo")
for l in "${layers[@]}"; do
  [[ -d "$src/template/$l" ]] || { echo "Unknown option value: template/$l does not exist" >&2; exit 1; }
done

# Compose the layers into a staging tree.
stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
for l in "${layers[@]}"; do
  (cd "$src/template/$l" && find . -type f -print0) | while IFS= read -r -d '' f; do
    f="${f#./}"
    if [[ "$f" == *.append ]]; then
      t="${f%.append}"
      [[ -f "$stage/$t" ]] || { echo "template/$l/$f has no base file $t" >&2; exit 1; }
      cat "$src/template/$l/$f" >> "$stage/$t"
    else
      mkdir -p "$stage/$(dirname "$f")"
      cp "$src/template/$l/$f" "$stage/$f"
    fi
  done
done

# Copy into the target.
(cd "$stage" && find . -type f -print | sort) | while IFS= read -r f; do
  f="${f#./}"
  if [[ -e "$dst/$f" && $force -eq 0 ]]; then
    echo "skip (exists): $f"; continue
  fi
  mkdir -p "$dst/$(dirname "$f")"
  cp "$stage/$f" "$dst/$f"
  echo "added: $f"
done

gi="$dst/.gitignore"
# Make sure the last existing line ends with a newline before appending.
[[ -s "$gi" && -n "$(tail -c1 "$gi")" ]] && echo >> "$gi"
for line in ".agent-logs/" ".agent-work/"; do
  grep -qxF "$line" "$gi" 2>/dev/null || echo "$line" >> "$gi"
done
chmod +x "$dst"/.github/hooks/scripts/*.sh "$dst"/scripts/factory/*.sh

echo
echo "Installed: repo=$repo"
echo "Next: edit $dst/scripts/factory/commands.env and the Project section of $dst/AGENTS.md,"
echo "then run: (cd $dst && bash scripts/factory/test-hooks.sh && bash scripts/factory/check.sh)"
