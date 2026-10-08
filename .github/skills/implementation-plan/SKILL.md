---
name: implementation-plan
description: Format and rules for writing an ordered, test-first implementation plan from an issue brief. Use when planning code changes.
---

# Implementation plan

Write `.agent-work/issue-N/plan.md` in this exact format:

```markdown
# Plan for issue #N

## Approach
<3–6 sentences: the design, and why it is the smallest change that works>

## Tasks
### T1: <imperative title>
- Files: `path/a.ext`, `path/b.ext`
- Tests: `path/test_a.ext` — <what the test asserts>
- Covers: AC1, AC2
- Done when: <observable condition>

### T2: ...

## AC coverage
| AC | Tasks | Tests |
|----|-------|-------|
| AC1 | T1 | test_a::test_x |

## Risks and rollback
- <risk> → <mitigation>
```

## Rules
- 1–6 tasks. Each task is one commit and fits comfortably in one focused session.
- Order tasks so the build and tests pass after every task.
- Name real paths found by searching the repo. Mark new files as `(new)`.
- No task may say "refactor" without a concrete reason tied to an AC.
- Include a task for docs/README only if behavior visible to users changes.
