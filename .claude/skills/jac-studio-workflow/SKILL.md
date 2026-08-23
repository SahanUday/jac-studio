---
name: jac-studio-workflow
description: This skill should be used before committing, pushing, or opening a PR in jac-studio, whenever a real blocker or unexpected Jac behavior is hit during implementation (in ANY subsystem — editor core, workbench, extensions, persistence, desktop, tooling, translator, not just translator work), when using the translator CLI or land-blocker.sh, or when finishing a roadmap phase. Covers the exact procedures so nothing gets silently worked around or left unrecorded.
---

# jac-studio operating procedures

## When you hit a blocker — read this first, every time

**This is not optional and it is not translator-specific.** Any time something in jac-studio
doesn't work the way it should — a Jac compiler error that looks wrong, a missing capability, a
doc that contradicts actual behavior, an ergonomics problem that forces an awkward workaround —
it gets logged, in the same sitting it's hit, regardless of which subsystem you were working in
(editor core, workbench shell, extensions, persistence, desktop, tooling, translator). Silently
working around something and moving on is the one thing this project explicitly exists to avoid —
tracking real friction with jac-lang is a stated project goal, not a nice-to-have.

**Decide first: is this worth an entry?** Yes, if it's a real Jac/tooling limitation, a
docs-vs-behavior mismatch, a missing capability, or a design decision worth recording for future
reference. No, if it's just your own bug (fix it, no entry needed) — though if the *mistake* was
caused by misleading docs or a genuinely non-obvious compiler behavior, it likely IS worth an
entry even if the immediate fix was simple (see `jac-language`'s gotcha list — several entries
there are exactly this shape).

**The entry format** (full schema and rationale in `docs/challenge-tracking.md`, on `main`):

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

**How to land it**, two paths depending on context:

1. **From the translator tool**: `jac run main.jac -- block --id <manifest-id> --summary "..."
   --error "..."` scaffolds the entry into `translator/blocked/` with the frontmatter filled in
   from the manifest record. Then fill in the **Plan** section by hand (real judgment — the
   script/CLI never writes this for you), then run `translator/land-blocker.sh
   translator/blocked/<file>.md` to land it on `tracking` in one shot (checkout, pull, copy,
   rebuild the site, commit, push, switch back — refuses to run with an unfilled Plan, a dirty
   working tree, or a filename collision).
2. **From anywhere else** (not using the translator tool — e.g. a blocker hit while building the
   workbench shell, extensions, or anything outside `translator/`): write the markdown file by
   hand following the exact schema above, save it anywhere convenient, then still use
   `translator/land-blocker.sh <path-to-your-file>.md` to land it — the script only cares that
   the file exists and its Plan section is filled in, not that it came from the translator's
   `block` command. Don't hand-roll the checkout/copy/commit/push dance; the script exists
   precisely so that isn't necessary.

After landing, the live dashboard at https://sahanuday.github.io/jac-studio/ updates
automatically via GitHub Actions within about a minute.

## Git workflow

- **Never commit directly to `main`.** Every change lands via a feature branch + PR
  (`git checkout -b <topic>/<slug>`, push, `gh pr create --base main`), left unmerged for the
  user to review and merge themselves — do not merge PRs.
- **The `tracking` branch is different**: it's pushed to directly (via `land-blocker.sh` or
  equivalent), not via PR — it's the challenge log + its own static site, not product code.
- **No AI co-author attribution** in commit messages or PR descriptions for this project (and
  the jaseci repo) — no `Co-Authored-By: Claude` trailers, no mentioning Claude/AI authorship in
  commit messages.
- Before any command that could discard uncommitted work, check `git status` first — this
  matters more than usual here since the repo has multiple long-lived branches (`main`,
  `tracking`, feature branches) sharing one working tree, and files from one branch persist as
  untracked leftovers when another branch is checked out (this is expected, not a bug — e.g.
  `translator/` shows as untracked while `tracking` is checked out, and vice versa for `log/`).

## Ending a phase

Write (or update, if it already exists as a living doc) `docs/phases/phase-N-<name>.md` — see
`docs/phases/phase-0-foundations.md` for the template: goal recap, what was actually built, key
decisions made, deviations from the original plan (found by building, not assumed upfront),
blockers logged during the phase (link the tracker entries), what's left, and a **suggested next
steps** section pointing at what to tackle first in the next phase and why. This is what lets a
future session (agent or human) get oriented without re-reading every doc and PR from that phase.

## Research before re-deriving

Before investigating something about upstream VS Code, VSCodium, or Jac's capabilities from
scratch, check whether it's already covered: `docs/research/vscode-architecture.md`,
`docs/research/vscodium-packaging.md`, `docs/research/jac-capabilities.md`,
`docs/research/jac-examples-patterns.md`, plus `docs/vscode-feature-gap-analysis.md` and
`docs/vscode-complete-triage.md` for feature-by-feature dispositions. These are point-in-time
findings (dated), not living docs — if something's changed since, note the discrepancy rather
than silently trusting a stale claim, and consider whether it's itself worth a tracker entry
(a doc-gap on our own docs, same as a doc-gap on jac's).
