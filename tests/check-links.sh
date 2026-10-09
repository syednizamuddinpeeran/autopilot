#!/usr/bin/env bash
# Fail if a relative Markdown link (file or #anchor) in README.md, docs/ or template/ points nowhere.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1
python3 - <<'PY'
import os, re, sys, glob
files = ["README.md"] + glob.glob("docs/**/*.md", recursive=True) + glob.glob("template/**/*.md", recursive=True)
def anchors(path):
    out=set()
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^#{1,6}\s+(.*)", line)
        if m:
            a = re.sub(r"[^\w\- ]", "", m.group(1).strip().lower()).replace(" ", "-")
            out.add(a)
    return out
bad = 0
for f in files:
    text = open(f, encoding="utf-8").read()
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    for link in re.findall(r"\]\(([^)\s]+)\)", text):
        if re.match(r"^[a-z]+:", link):
            continue
        path, _, anchor = link.partition("#")
        target = os.path.normpath(os.path.join(os.path.dirname(f), path)) if path else f
        if not os.path.exists(target):
            print(f"{f}: broken link {link}"); bad += 1; continue
        if anchor and target.endswith(".md") and anchor not in anchors(target):
            print(f"{f}: missing anchor {link}"); bad += 1
print(f"link check: {bad} problem(s) in {len(files)} files")
sys.exit(1 if bad else 0)
PY
