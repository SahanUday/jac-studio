---
name: jac-studio-git-workflow
description: This skill should be used before committing, pushing, or opening a pull request in jac-studio (or the jaseci repo), and when finishing work on a roadmap phase. Covers branch/PR conventions, attribution rules, and the phase-summary habit. Not for translator usage or blocker logging — see jac-studio-translator and jac-studio-challenge-tracking for those.
---

# jac-studio git & phase conventions

## Committing and pushing

- **Never commit directly to `main`.** Every change lands via a feature branch + PR
  (`git checkout -b <topic>/<slug>`, push, `gh pr create --base main`), left **unmerged** for the
  user to review and merge themselves — do not merge PRs regardless of how routine the change is.
- **The `tracking` branch is different**: it's pushed to directly (via
  `translator/land-blocker.sh` — see `jac-studio-challenge-tracking`), not via PR. It's the
  challenge log and its own static site, not product code, and has its own norms.
- **No AI co-author attribution** in commit messages or PR descriptions, for this project and
  the jaseci repo — no `Co-Authored-By: Claude` trailers, no mentioning Claude/AI authorship
  anywhere in commit messages or PR bodies.
- Before any command that could discard uncommitted work, check `git status` first — this
  matters more than usual here since the repo has multiple long-lived branches (`main`,
  `tracking`, feature branches) sharing one working tree, and files tracked on one branch persist
  as untracked leftovers when a different branch is checked out. This is expected, not a bug —
  e.g. `translator/` shows as untracked while `tracking` is checked out, and `log/`/`site/` show
  as untracked while `main` or a feature branch is checked out.
- If a PR gets an automated review (Copilot or otherwise) requesting changes, address every
  comment before considering the PR ready — don't leave requested changes unaddressed and move
  on to other work.

## Ending a phase

Write (or update, if it already exists as a living doc) `docs/phases/phase-N-<name>.md` — see
`docs/phases/phase-0-foundations.md` for the template: goal recap, what was actually built, key
decisions made, deviations from the original plan (found by building, not assumed upfront),
blockers logged during the phase (link the tracker entries), what's left, and a **suggested next
steps** section pointing at what to tackle first in the next phase and why. This is what lets a
future session (agent or human) get oriented without re-reading every doc and PR from that phase
— treat it as required, not optional, before considering a phase actually finished.
