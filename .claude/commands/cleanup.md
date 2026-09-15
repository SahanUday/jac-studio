---
description: Cut prose in .jac files down to the project budget, preserving rationale as ADRs
argument-hint: <path or glob, e.g. src/workbench/scm/>
---

Clean up the prose in: **$ARGUMENTS**

1. Measure first. For each `.jac` file in scope, report total lines and prose lines (comments +
   docstring blocks) so there's a baseline to compare against.
2. Delegate the actual editing to the `prose-cleaner` agent — one agent per batch of related files,
   run in parallel when the batches are independent. Never clean more than one batch inline
   yourself; that's what the agent exists for.
3. Collect every `RATIONALE TO PRESERVE` item the agents return. For each one that's a genuine
   decision, write an ADR in `docs/decisions/` using `/adr`. Do not let a single one be dropped
   silently — that knowledge is the reason the prose existed.
4. Verify: `jac check` clean on every touched file, and `jac test src` at the same pass count as
   before the cleanup. A drop means an edit went past the text.
5. Report the before/after totals and list the ADRs created.

Do not change code behavior. Text only.
