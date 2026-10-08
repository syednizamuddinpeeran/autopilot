---
name: open-pr
description: Push the branch and open or update the pull request with the standard body, linked issue, and evidence. Use as the final step of an issue run.
---

# Open the pull request

## Preconditions
- `verify-changes` passed in this session (unless opening a draft for a blocked run).
- Branch is `agent/issue-N-*` (local) or `copilot/*` (cloud). Never `main`.

## Where you are running
- **Cloud agent** (`/workspace` exists, branch `copilot/*`): the platform creates the PR.
  Push your commits and put the body below into the PR description using your progress/PR update tool.
- **Local CLI**: run
  ```bash
  git push -u origin HEAD
  gh pr create --base "${BASE_BRANCH:-main}" --title "<type>(<scope>): <summary> (#N)" \
    --body-file .agent-work/issue-N/pr-body.md [--draft]
  ```
  Use `--draft` when risk is high, verification failed, or blocking questions remain.

## PR body (write to `.agent-work/issue-N/pr-body.md`)
```markdown
Closes #N

## Summary
<2–4 sentences>

## Acceptance criteria
- [x] AC1 — <test name that proves it>
- [ ] AC2 — <why not met, if any>

## Verification
`scripts/factory/check.sh` — passed | failed (<which check>)

## Assumptions
- A1 ...

## Risks / follow-ups
- ...

## Agent run
Plan, review, and decisions: `.agent-work/issue-N/` (local only). Action log: `.agent-logs/<session>.jsonl`.
```

## Rules
- Never run `gh pr merge` or enable auto-merge. A human merges.
- Never request reviewers who are bots unless the repo already does so.
