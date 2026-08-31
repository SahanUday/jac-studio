---
id: 2026-08-31-anchor-free-root-using-module-pulled-client-wholesale
date: 2026-08-31
category: doc-gap
severity: major
status: workaround
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [placement, codespace-inference, root, jid, server-anchor, output-panel]
---

## What happened

Building Phase 4's Output panel (`docs/roadmap.md`), `src/workbench/output/output_service.jac` was
written following `docs/architecture.md`'s own recommended "not every service needs to be a node"
pattern: a plain `obj OutputChannel`, cached in a `dict[str, dict[str, OutputChannel]]` keyed by
`jid(root)`, with no Python import and no graph archetype anywhere in the file -- the module's
whole storage layer is just dicts/lists plus `root`/`jid()`.

The moment a client component (`src/workbench/output/output.jac`) imported one of its `def:pub`
functions (`list_channels`), the app crashed at runtime with:

```
TypeError: jid() expected a node or edge with graph identity, but received
["__reactContainer$...", "_reactListening..."]. Only node and edge archetypes have a jid.
    at Object.jid (compiled/src/workbench/output/output_service.js:1289:15)
    at _get_channels (compiled/src/workbench/output/output_service.js:1776:26)
    at list_channels (compiled/src/workbench/output/output_service.js:1795:51)
    at refresh (compiled/src/workbench/output/output.js:18:30)
```

`jac check`/`jac test` both passed cleanly beforehand -- this only surfaced in the real compiled
client bundle (`jac browse` against a live `jac run --serve --dev` process), the same category of
gap this project has hit repeatedly (see e.g. `2026-08-24-client-dict-literal-variable-key-miscompiles`).

## Root cause

`jac guide jac-codespaces`'s own evidence rules, read closely:

> **Server is anchored by server-only facts.** Python imports, graph archetypes (`node`/`edge`/
> `walker`), `::py::` blocks, and typed context blocks anchor their module server. Unreferenced
> pure code defaults to server too.
>
> ... in a module with NO server anchor at all, a pure `def:pub` can be pulled client wholesale --
> there is no server side to bridge to.

`root`/`jid()` usage is **not** in that anchor-fact list. The guide's rule 5 (native placement)
*does* call out "`root`/persistence access" as a **native blocker** -- but that's a different rule,
for a different codespace decision (whole-module native-vs-server), and does not also make it a
*server anchor* for the client-vs-server decision rule 2 governs. A module using nothing but
`root`/`jid()` and plain collections -- exactly the shape `docs/architecture.md`'s own "not every
service needs to be a node" section recommends for a service that doesn't need to be a graph node
-- has zero facts in rule 2's list, so once a client component imports one of its `def:pub`
functions, the whole module (private helpers, the `jid(root)`-keyed cache, everything) gets pulled
into the client bundle by rule 4's reference-propagation, where `jid(root)` then fails at runtime
because `root` client-side resolves to something else entirely (whatever the JS bundler's own
module-scope binding happens to produce, not the graph anchor) rather than failing at compile time
with a clear diagnostic.

Every other server module in this project happens to import something Python-only
(`document_service.jac`: `import os;`; `terminal_service.jac`: `import asyncio;`; `command_registry.jac`:
`import threading;`) which incidentally anchors it server -- `output_service.jac` is the first
module in this project with a real `root`/`jid()`-only storage layer and literally nothing else, so
it's the first to expose this gap. Any future service following the exact pattern
`docs/architecture.md` recommends (plain `obj` + `jid(root)`-keyed cache, deliberately *not* a
node, to skip the ~600us/call graph-query cost) is equally exposed unless it happens to also import
something Python.

## Repro (minimal)

```jac
# no python import, no node/edge/walker
glob _cache: dict[str, str] = {};
def:pub get_my_id -> str {
    return jid(root);
}
```
Import `get_my_id` from any client (`app -> JsxElement`) component and call it -- compiles and
`jac check`/`jac test` both pass; crashes at runtime the moment it actually runs, client-side,
with the "expected a node or edge with graph identity" error above.

## Workaround (shipped)

An explicit `[placement.pins]` entry in `jac.toml`, the officially documented fix for exactly this
class of problem ("Pin in `jac.toml` when client code references something that must stay
server-side"):

```toml
[placement.pins]
"src.workbench.output.output_service" = "server"
```

Confirmed fixed: the compiled client bundle now calls `await __jacCallFunction("list_channels", {})`
(a real RPC bridge) instead of inlining `_get_channels`/`jid(root)` into the browser bundle.

## Plan

Two possible upstream fixes, either would close this without every anchor-free-but-`root`-using
module needing its own hand-written pin:
1. Add `root`/`jid()`/persistence-primitive usage to rule 2's server-anchor fact list (the same
   list rule 5 already treats as a *native* blocker) -- the most direct fix, since it's already
   recognized as server-only-meaningful elsewhere in the same evidence system, just not wired into
   the client-vs-server decision.
2. Failing that, a compile-time diagnostic when a client-placed reference closure resolves to code
   calling `root`/`jid()`/`jobj()` with no server anchor, instead of a silent client-side inline
   that only fails at runtime. Even a `jac check --placements` note wouldn't have been enough here
   without knowing to run it -- this should ideally be impossible to accidentally ship past
   `jac check` clean.

Until either lands: any new service module in this project that stores state purely via
`root`/`jid()` (no Python import, no graph archetype) and is imported by a client component needs
an explicit `[placement.pins]` server entry from the start, not discovered the hard way via a live
browser crash. Worth a line in `jac-studio-architecture`'s service-registry section calling this out
explicitly, next time that skill file is touched.
