---
name: jac-studio-git-workflow
description: This skill should be used before committing, pushing, or opening a pull request in jac-studio (or the jaseci repo), and when finishing a roadmap milestone. Covers branch and PR conventions, the testing-workspace fixture obligation, and the milestone closeout habit.
---

# Git and milestone conventions

## Committing and pushing

- **Never commit to `main`.** Feature branch → push → `gh pr create --base main`, left
  **unmerged** for the user to review and merge. Don't merge, however routine the change.
- **The `tracking` branch is the exception** — pushed to directly via
  `internal/translator/land-blocker.sh`. It's the challenge log and its site, not product code.
- **No AI attribution** anywhere in commit messages or PR bodies — no `Co-Authored-By: Claude`, no
  mention of AI authorship.
- **Check `git status` before anything that could discard work.** Several long-lived branches share
  one working tree, so files tracked on one branch linger as untracked leftovers on another. That's
  expected, not a bug.
- **Address every automated review comment** before calling a PR ready.

## The `testing-workspace/` obligation

`testing-workspace/` (repo root, gitignored) is the standing fixture: a real, small project with
its own nested git repo that demonstrates everything jac-studio has shipped. It's what live
`jac browse` verification and the maintainer's manual checks both use.

- **A PR adding a user-visible capability updates the fixture to demonstrate it, before the PR
  opens.** Small targeted additions — a new symbol shape for LSP work, a task case for the runner,
  a git state for SCM. Skip only for pure refactors, internal helpers, or docs-only changes.
- **It stays gitignored, and its own git state is part of the fixture** — deliberately uncommitted
  changes give SCM something real to show. Don't `git add` or commit inside it to tidy up, and
  don't regenerate it wholesale.
- **Give it its own `jac.toml`** (`[project] name = "testing-workspace"`, no `kind` needed — infers
  `cli`). Without one, `jac run <file>` inside it walks up and "takes over" jac-studio's own
  `jac.toml`, spawning a second full dev server on a random port instead of just executing the
  file — confirmed live, tracker entry
  `2026-09-22-jac-run-takeover-spawns-competing-dev-server-from-a-nested-project-less-directory`.
  Untracked (matches the rest of the fixture), so this doesn't ship in any PR — just don't skip it
  when setting the fixture up fresh.

## Ending a milestone

Write or update `docs/milestones/<id>-<name>.md`: what was actually built, decisions made (link the
ADR in `docs/decisions/`), deviations found by building, blockers logged (link tracker entries),
what's left, and what to tackle next. Keep it to the doc budget — short sections, tables over
paragraphs. This is what lets the next session get oriented without re-reading every PR.

Anything that changed *why* the project does something belongs in an ADR, not buried in the
milestone writeup.
