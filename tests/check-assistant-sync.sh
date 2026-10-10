#!/usr/bin/env bash
# Agent and skill bodies must be the same for every assistant; only the frontmatter differs.
# Lists Copilot files (.github/agents/*.agent.md, .github/skills/*/SKILL.md) and compares the body
# after the frontmatter with the Claude Code file (.claude/agents/*.md, .claude/skills/*/SKILL.md).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root/template/assistant" || exit 1
# Files whose bodies are allowed to differ, with the reason.
allowed=(
  "_repo/github/.github/skills/open-pr/SKILL.md"   # Copilot cloud agent vs Claude GitHub Action PR flow
)
body() { awk 'BEGIN{n=0} /^---$/ && n<2 {n++; next} n>=2' "$1"; }
fail=0 checked=0
while IFS= read -r f; do
  rel="${f#copilot/}"
  case "$rel" in
    *.github/agents/*.agent.md) other="claude-code/${rel/.github\/agents\//.claude/agents/}"; other="${other%.agent.md}.md" ;;
    *.github/skills/*)          other="claude-code/${rel/.github\/skills\//.claude/skills/}" ;;
    *) continue ;;
  esac
  checked=$((checked + 1))
  [[ -f "$other" ]] || { echo "missing Claude counterpart: $other (for $f)"; fail=1; continue; }
  skip=0; for a in "${allowed[@]}"; do [[ "$rel" == "$a" ]] && skip=1; done
  [[ $skip -eq 1 ]] && continue
  if ! diff -q <(body "$f") <(body "$other") >/dev/null; then
    echo "body differs: $f vs $other"; diff <(body "$f") <(body "$other") | head -10; fail=1
  fi
done < <(find copilot -type f \( -name '*.agent.md' -o -name SKILL.md \) | sort)
echo "assistant sync: $checked files checked, $([[ $fail -eq 0 ]] && echo ok || echo FAILED)"
exit $fail
