---
name: jac-studio-architecture
description: This skill should be used when deciding how to build a new jac-studio component, scoping a milestone, asking "does VS Code have this and do we cover it," or navigating which doc holds an answer. Also applies when the user asks about the project's plan, current milestone, or what has been decided versus what is still open.
---

# Deciding how to build a jac-studio component

Goal: VS Code's capabilities and UX, as a Jac web app, AI-first. Not a literal clone — where an
AI-native workflow is better, take it. Web app first; desktop comes last by bundling the same
client.

## The decision procedure

Ask in order. Stop at the first yes.

1. **Is this a solved problem with a proven library the commercial editors already use?**
   → **Reuse it.** Monaco, xterm.js, ripgrep-class search, Radix. Wrap it thinly in Jac and record
   what it gives us in `docs/libraries/<name>.md` (see `jac-studio-libraries`). Engineering effort
   belongs on Jac-specific workflows and the AI layer, not on re-deriving a text editor.
2. **Does VS Code's shape exist only because TypeScript/Electron lacked something Jac has?**
   → **Redesign it.** The graph from `root` instead of a DI container; `root spawn` instead of a
   hand-written RPC protocol; a capability gate instead of always-on OS access.
3. **Is it small, self-contained, pure, and does upstream have tests for it?**
   → Translate it (`jac-studio-translator`). Rare now, and the translator is idle.
4. **Otherwise** → build fresh in Jac, informed by reading upstream, never mechanically copied.

## Service design rules

Before making anything a `node`, check it needs to be one: it must survive a restart, be reachable
by graph traversal, or participate in the permission model. Otherwise a plain `obj` is correct and
skips the ~600µs/call graph query entirely.

If it *is* graph-resolved and cached:

- **Key the cache by `jid(root)`** — `glob _cache: dict[str, T] = {}`. Never a bare
  `X | None = None`. `root` is per-caller, so an unkeyed cache leaks one user's data to another.
- **Pair it with `_reset_<x>_cache_for_tests()`**, called at the top of every test touching it.
- **Verify multi-user before calling it done** — two logged-in users via `JacTestClient`. A single-
  `root` test suite cannot prove this; 13 passing tests once missed exactly this leak.

## Known constraints that outlive their context

- **The file tree must load lazily.** Eagerly building and traversing a real workspace graph
  measured ~3s at 2,974 nodes. Expand-on-demand is a requirement, not an optimization.
- **Placement needs explicit pins.** A client module importing one server `def:pub` gets pulled
  server-side wholesale, and vice versa. See `jac.toml`'s `[placement.pins]`.

## The doc map

| Need | Go to |
|---|---|
| What's being built, in what order | `docs/roadmap.md` |
| How the system is put together now | `docs/architecture.md` |
| Why a past call was made | `docs/decisions/` |
| What a library gives us | `docs/libraries/` |
| Does upstream have X, do we cover it | `docs/vscode-complete-triage.md` |
| Prior research (dated, point-in-time) | `docs/research/` |

Docs are the source of truth — read them, don't trust a paraphrase, including this one. If
something here contradicts a doc, the doc wins and this skill needs fixing.

## Stuck or surprised?

Don't guess past it and don't silently work around it — see `jac-studio-challenge-tracking`.
