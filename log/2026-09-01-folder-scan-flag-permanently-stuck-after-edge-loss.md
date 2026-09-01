---
id: 2026-09-01-folder-scan-flag-permanently-stuck-after-edge-loss
date: 2026-09-01
category: compiler-bug
severity: major
status: open
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [persistence, workspace-graph, edge-durability, file-tree]
---

## What happened

`src/workbench/workspace/workspace_service.jac`'s `_ensure_scanned` treats a `Folder`/`Workspace`
node's `scanned: bool` field as a permanent, one-way "materialized once" flag: once `True`, it
never re-lists the real directory again, on the theory that lazy per-folder scanning only needs to
happen once per folder per app lifetime.

Found live (not theorized) while investigating a user report that the Explorer's expand-folder
interaction had stopped working in a long-running `testing-workspace` session: several folders
(`docs`, `scripts`, `src`, `.jac-studio`) had `scanned=True` persisted, but zero live `Contains`
edges to their children, even though every one of those folders genuinely has files on disk.
`list_children_by_path` therefore returned `[]` for all of them, permanently, on every future
expand click — indistinguishable in the UI from "this folder is actually empty."

Root cause of the *original* corruption not fully pinned down, but circumstantial: it followed a
session of heavy `git` churn against `testing-workspace` (branch switches, a real merge conflict,
a `git stash push -u`/`drop`/recovery cycle) while jac-studio had that workspace open. This file's
own docstring already documents a confirmed, adjacent gap for `rename_path`/`delete_path`'s edge
*deletion* not reliably committing across separate real HTTP requests
(`2026-08-28-edge-deletion-not-committed-across-real-http-requests`) — plausible that some external
filesystem churn combined with an in-flight scan/delete left a `Folder` node `scanned=True` with no
surviving edges, but this wasn't reproduced from a clean starting state, only found already in that
condition.

## What was tried

Three same-day attempts at a "self-heal" fix (re-scan when `scanned=True` but zero live children
and the real directory on disk is non-empty) were built and each initially passed `jac check`,
`jac test`, and a first live check — then failed differently under further live testing against a
real `jac run --serve --dev` process (verified via plain `curl` straight at
`/function/list_children_by_path`, not just the UI, to rule out client-rendering artifacts):

1. **Unconditional `jobj(jid(parent))` at the top of `_ensure_scanned`, before checking
   `scanned`.** Broke the *common*, previously-fine fast path: a folder with genuine live children
   (the workspace root itself) started coming back empty, because `list_children_by_path`'s own
   separate, unrefreshed `parent` reference apparently lost visibility into `parent`'s own edges
   once `jobj()` was called elsewhere in the same request — even though nothing about that call
   should have touched `parent` at all.
2. **`jobj()` scoped back to only the mutating branch** (matching the original code's own gating),
   with the corruption-check reading via the plain `parent` reference and the write via a separate
   `jobj()`-resolved `fresh_parent`. This fixed the root case reliably, but a folder actually being
   scanned for the *first time* (never previously touched) still came back empty on its own first
   call: a freshly-created `Contains` edge written via `fresh_parent +>:Contains():+> child` was
   not visible to a `[fresh_parent->:Contains:->]` read moments later, in the *same* call — even
   though the exact same edge was correctly visible to every *separate*, later call.
3. **Returning the exact `child` objects the scan loop had just constructed, with no graph read at
   all near the write** (`new_children.append(child)`, returned directly instead of
   `[fresh_parent->:Contains:->]`). This should have been airtight — no read-after-write ambiguity
   possible — and passed a first live check. But a later, independent live re-test (fresh server
   process, real browser click via `jac browse`, immediately after page load) showed the same
   folder consistently returning `[]` again, on both the client's own RPC call and a direct `curl`
   to the same endpoint moments later. Whether the earlier "healed" state was ever durably
   committed to the shared persistence layer at all, versus only ever reflecting an in-process
   object mutation visible for the remainder of that one server process's lifetime, was not
   isolated before time ran out on this investigation.
4. **An explicit `Jac.commit()` immediately after writing the new edges** (`import from jaclang
   { JacRuntime as Jac }`, then `(Jac as any).commit()`), on the theory that attempt 3's failure was
   really a same-request durability gap (this project's own `lsp_client.jac` hit and fixed an
   adjacent version of exactly this with the identical primitive, for a background
   `asyncio.create_task` with no request boundary to auto-commit against). Passed `jac check`/
   `jac test`. Failed the identical live re-test as attempt 3: fresh server process, real browser
   click immediately after page load, same folder still consistently `[]` on both the client's RPC
   and a direct `curl` moments later — no exception or error surfaced anywhere in the server log, so
   the commit call itself did not visibly fail, it just didn't make the corrupted folder queryable
   again. This rules out "the write is simply never durable" as the *whole* story (an explicit
   commit targeting exactly that gap still didn't fix it) and points at something else -- a leading
   hypothesis, **not verified**: `[parent->:Contains:->]` may cache its result on the specific
   in-memory `parent`/`fresh_parent` object the first time it's queried, and never invalidate that
   cache on a later write+commit through a *different* reference to the same node -- which would
   mean the corruption-*detection* read itself (needed to tell "genuinely empty" from "lost edges"
   apart) poisons the very object the fix then tries to read back through, regardless of commit
   timing. Not confirmed with a targeted, isolated repro before time ran out.

## Current state

Reverted to the original, simple, unconditional-early-return `_ensure_scanned` — the known,
pre-existing limitation (a corrupted-empty folder stays stuck until the workspace is closed and a
genuinely different root path is opened, which resets `scanned=False`, per `get_or_create_workspace`'s
own docstring) rather than any of the three unverified attempts above.

## Plan

Needs a real spike, isolated from any specific corrupted fixture state and from `jac test` (which
never crosses the real-HTTP-request boundary these persistence surprises live in), that deliberately
measures whether `[node->:EdgeType:->]` caches per-object and survives a same-node write+commit
through a different reference -- attempt 4's leading hypothesis above, still unconfirmed. Ideally
with jaseci's own persistence-layer maintainers: four independent attempts at a client-code-only fix
each hit a different, non-obvious failure mode, including one (attempt 4) that used this exact
project's own already-proven `Jac.commit()` fix for an adjacent problem and still didn't resolve it
-- strong evidence this isn't simply a missing-commit gap. Once `->:EdgeType:->` read-after-write
semantics are actually understood (not just worked around), `_ensure_scanned`'s self-heal can be
re-attempted with a real verified mental model instead of another guess. In the meantime, the
practical, low-effort mitigation for anyone who hits this on a real workspace is: open a *different*
folder, then reopen the original one — `get_or_create_workspace` resets `scanned=False` and
re-points the tree at a fresh root when the root path actually changes.
