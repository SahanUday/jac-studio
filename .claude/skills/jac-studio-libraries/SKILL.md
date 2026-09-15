---
name: jac-studio-libraries
description: This skill should be used when adopting, upgrading, or evaluating a third-party library or npm package in jac-studio — Monaco, xterm.js, Radix, a search backend, a git backend, and so on. Covers when to reuse versus build, and the capability note that must be written when a library is actually wired in.
---

# Adopting a library

jac-studio reuses proven libraries for solved problems. Jac effort goes to the architecture, the
Jac-specific workflows, and the AI layer — not to re-deriving a text editor or a terminal emulator.

## Before adopting

1. **Is the problem genuinely solved elsewhere?** If commercial editors all use the same library
   for it, that's the answer. Don't rebuild it to prove Jac can.
2. **Can it reach the context it's needed in?** String-path npm imports
   (`import from "pkg" { ... }`) are structurally **client-only** and `[placement.pins]` cannot
   override that. Server-side work needs a subprocess instead.
3. **Does it force a shape on us we'll regret?** A thin wrapper we control beats deep coupling to
   someone else's abstractions. We adopt the library, not its worldview.
4. **If it is a real Jac limitation forcing the library** — not just convenience — that belongs in
   the challenge tracker too. See `jac-studio-challenge-tracking`.

## Write the capability note when you wire it in

When a library is actually used in an implementation — **not before** — create
`docs/libraries/<name>.md`. The point is a durable record of what the library makes available to
us, so later milestones don't re-research it or miss a feature already paid for.

Keep it to the budget: short sections, tables over paragraphs, no narrative.

```markdown
# <library> — <version>

What we use it for: <one line>
Where it's wired in: <file paths>

## Capabilities we use
| Capability | API | Where |
|---|---|---|

## Capabilities available but not yet used
| Capability | API | Possible use |
|---|---|---|

## Limits and gotchas
- <things that bit us, or constraints that will shape later work>
```

The "available but not yet used" table is the valuable half — it's what turns a dependency into a
map of what we can build next cheaply. Update the note when a milestone starts using more of the
library, and record version-specific behavior when an upgrade changes something.

## Already in use

Monaco (editor engine), xterm.js (terminal rendering), Radix/shadcn-in-Jac (UI primitives),
react-markdown, Tailwind v4. Check `jac.toml` for the authoritative dependency list and versions
before assuming what's available.
