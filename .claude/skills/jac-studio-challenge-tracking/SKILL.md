---
name: jac-studio-challenge-tracking
description: This skill should be used whenever a real blocker, compiler quirk, missing capability, docs-vs-behavior mismatch, or other genuine Jac/tooling limitation is hit anywhere in jac-studio — editor core, workbench, extensions, persistence, desktop, tooling, translator, any subsystem. Not specific to the translator (see jac-studio-translator for that tool's own commands). Covers the entry format and how to land it. Do not silently work around a real finding without logging it.
---

# Logging a challenge or blocker

**Not optional, and not translator-specific.** Any time something in jac-studio doesn't work the
way it should — a Jac compiler error that looks wrong, a missing capability, a doc that
contradicts actual behavior, an ergonomics problem that forces an awkward workaround — it gets
logged, in the same sitting it's hit, regardless of which subsystem was being worked on. Tracking
real friction with jac-lang is a stated project goal, not a nice-to-have; silently working around
something and moving on is the one thing this project exists to avoid.

## Decide first: is this worth an entry?

Yes, if it's a real Jac/tooling limitation, a docs-vs-behavior mismatch, a missing capability, or
a design decision worth recording for future reference. No, if it's just your own bug — fix it,
no entry needed. But if the *mistake* was caused by misleading docs or genuinely non-obvious
compiler behavior, it likely IS worth an entry even if the immediate fix was simple (see the
`jac-language` skill's gotcha list — several entries there are exactly this shape: quick fix,
still worth recording because the behavior was surprising).

## The entry format

Full schema and rationale: `docs/challenge-tracking.md` on `main`.

```yaml
---
id: YYYY-MM-DD-slug
date: YYYY-MM-DD
category: compiler-bug | missing-feature | doc-gap | ergonomics | translator-blocker | workaround-found | resolved
severity: blocker | major | minor | note
status: open | workaround | resolved | upstream-tracked
phase: <current roadmap phase number>
subsystem: editor-core | workbench-shell | extensions | persistence | desktop | tooling | translator
jac_version: "<output of jac --version, or note 'dev build' + the jaseci commit if relevant>"
related_vscode_ref: "<upstream VS Code source path, if relevant, else empty>"
upstream_issue: "<owner/repo#N if already tracked upstream, else empty>"
tags: [relevant, tags]
---

Body: what you tried, what happened, the minimal repro if there is one, and a **Plan** section —
what unblocking this would look like, or why the workaround is acceptable.
```

`subsystem` spans the whole project — pick the one you were actually working in. Most existing
entries happen to say `translator` only because that's the only subsystem built so far, not
because tracking is scoped to it.

## How to land it

1. Write the markdown file following the schema above — either by hand (any subsystem), or, if
   the blocker came from a translator session, scaffold it first with
   `jac run main.jac -- block --id <manifest-id> --summary "..." --error "..."` from
   `translator/` (see `jac-studio-translator`), which pre-fills the frontmatter from the manifest
   record.
2. **Fill in the `**Plan**` section by hand** — real judgment, nothing automates this.
3. Land it: `translator/land-blocker.sh <path-to-your-finished-file>.md`. One shot — checks out
   `tracking`, pulls, copies the file into `log/`, rebuilds the site, commits, pushes, switches
   back to whatever branch you started on. Refuses to run if the Plan section is still the TODO
   placeholder, if your current branch has uncommitted changes (it will not stash), or if a file
   of that name already exists on `tracking`. The file doesn't need to have come from the
   translator's `block` command — the script only cares that it's finished.

After landing, the live dashboard at https://sahanuday.github.io/jac-studio/ updates
automatically via GitHub Actions within about a minute.
