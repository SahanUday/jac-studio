---
description: Write a short architecture decision record in docs/decisions/
argument-hint: <the decision, e.g. "use monaco instead of a native editor">
---

Write an ADR for: **$ARGUMENTS**

Check `docs/decisions/` for the highest existing number and use the next one. Filename:
`NNNN-kebab-case-title.md`.

Keep it under 25 lines. Tables and statements, not narrative — this is a record, not an essay.

```markdown
# NNNN — <title>

- **Date**: YYYY-MM-DD
- **Status**: accepted | superseded by [NNNN](NNNN-....md) | reversed

## Decision

<one or two sentences: what we do now>

## Why

<the forcing reason — a measurement, a constraint, a limitation hit. If there's a tracker entry or
a benchmark, cite the id/number rather than retelling the story.>

## Consequences

<what this commits us to, and what it rules out. Include anything a future session would otherwise
re-litigate or accidentally undo.>
```

Rules:

- One decision per file. If you're writing "and also", it's two ADRs.
- A reversal never edits the old ADR's decision — set the old one's status to `superseded by` /
  `reversed` and write a new one. The record stays honest.
- If the decision came from prose you're removing from source or docs, make sure the ADR captures
  the claim faithfully before that prose is deleted.
- Add the entry to `docs/decisions/README.md`'s index.
