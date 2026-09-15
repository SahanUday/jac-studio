---
name: jac-studio-challenge-tracking
description: This skill should be used whenever a real blocker, compiler quirk, missing capability, docs-vs-behavior mismatch, or genuine Jac/tooling limitation is hit anywhere in jac-studio — any subsystem, not just the translator. Covers the entry format and how to land it. Do not silently work around a real finding without logging it.
---

# Logging a challenge

**Not optional.** Tracking real friction with Jac is a stated project goal. Anything that doesn't
work the way it should — a wrong-looking compiler error, a missing capability, docs contradicting
behavior, an ergonomics problem forcing an awkward workaround — gets logged in the same sitting,
whatever subsystem you were in.

## Is it worth an entry?

**Yes** for a real Jac/tooling limitation, a docs-vs-behavior mismatch, or a missing capability.
**No** for your own bug — just fix it. But if misleading docs or genuinely non-obvious compiler
behavior *caused* your bug, it's worth an entry even though the fix was one line.

## Format

Full schema: `docs/challenge-tracking.md` on `main`.

```yaml
---
id: YYYY-MM-DD-slug
date: YYYY-MM-DD
category: compiler-bug | missing-feature | doc-gap | ergonomics | translator-blocker | workaround-found | resolved
severity: blocker | major | minor | note
status: open | workaround | resolved | upstream-tracked
phase: <current milestone>
subsystem: editor-core | workbench-shell | extensions | persistence | desktop | tooling | translator
jac_version: "<jac --version, or 'dev build' + jaseci commit>"
related_vscode_ref: ""
upstream_issue: ""
tags: []
---
```

Body: what you tried, what happened, a minimal repro, and a **Plan** section — what unblocking it
looks like, or why the workaround is acceptable.

Three rules that get gotten wrong:

- **`workaround-found` ≠ `resolved`.** Use `workaround-found` only when the real fix plausibly
  belongs upstream in jaseci. Use `resolved` when what you did is the correct permanent practice
  regardless of what jaseci adds later.
- **One finding per entry**, even when two were found in the same sitting. Cross-reference instead
  of merging.
- **Correct in place, never rewrite or delete.** If a `resolved` entry's fix later proves wrong,
  mark the wrong claims inline and append a `**CORRECTION**` section. A quietly-fixed entry hides
  the lesson.

## Landing it

1. Write the file (or scaffold from a translator session with
   `jac run main.jac -- block --id <manifest-id> --summary "..." --error "..."`).
2. **Fill in `Plan` by hand** — nothing automates judgment.
3. `internal/translator/land-blocker.sh <path>.md` — checks out `tracking`, copies, rebuilds,
   commits, pushes, returns you to your branch. It refuses if `Plan` is still a placeholder, if
   your branch has uncommitted changes, or if the filename already exists.

The dashboard at https://sahanuday.github.io/jac-studio/ updates within about a minute.
