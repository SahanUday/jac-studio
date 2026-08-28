---
id: 2026-08-28-edge-deletion-not-committed-across-real-http-requests
date: 2026-08-28
category: compiler-bug
severity: blocker
status: workaround
phase: 3
subsystem: persistence
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [persistence, edges, jac-run, def-pub, jac-test]
---

## What happened

Building the file-tree context menu's delete/rename operations
(`workspace_service.jac`'s `delete_path`/`rename_path`), deleting a graph edge inside a `def:pub`
function (`del e` on an edge object from `[edge node ->:Contains:->]` /
`<-:Contains:<-]`) does **not** reliably take effect for a *later, separate* real HTTP request's
traversal -- even though the exact same code passes every `jac test` run, because `jac test` never
crosses a real request/response boundary the way an actual served app does.

This is the same class of gap as the already-documented
`2026-08-28-field-mutation-on-cached-node-not-persisted` (a `has`-field write not surviving past a
`def:pub` function's return, because the real commit happens afterward in
`_finalize_call_response`, `jaclang/runtimelib/impl/server.impl.jac`) -- but for **edge deletion**
specifically, which that earlier entry never tested.

## Repro (live, not `jac test`)

Against a real `jac run --serve --dev` process, via `jac browse`, not just `jac check`/`jac test`:

1. Open a workspace, create a file via the file-tree context menu's "New File" (`create_file`,
   itself confirmed working correctly and visible in the very next `list_children_by_path` call).
2. Right-click that file, choose "Delete" -- `delete_path` runs: `shutil.rmtree`/`os.remove`
   (confirmed via `ls` on the real filesystem: the file is genuinely gone), then detaches the
   node's edges (`del e` on both edge directions), then `del _path_index[key][path]`.
3. The client's next `list_children_by_path(parent_path)` call (a **separate** HTTP request) still
   returns the deleted file. Confirmed by calling the RPC endpoint directly from the browser
   console (`fetch('/function/list_children_by_path', ...)`, same-origin, same session) rather
   than trusting the rendered UI: the phantom entry is a real part of the server's response, not a
   client-side stale-render artifact.
4. The identical `delete_path` code, exercised via `jac test` (calling `delete_path` then
   `list_children_by_path` directly in one test function body), correctly shows the file gone --
   `jac test` cannot reproduce this at all, since it never crosses the real commit boundary.

A rename (delete-old-edge + create-new-node-and-edge, avoiding field mutation on the live node
entirely -- see the sibling `2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability`
entry for why field mutation was abandoned in favor of this shape) hits the identical symptom: the
old, edge-deleted node keeps reappearing in later listings, indefinitely, across a real server
process, despite `os.path.exists` confirming the underlying file is gone from disk.

## Why this is more severe than the field-mutation finding

Edge deletion is the *only* mechanism this project's own existing code already uses for detaching
subtrees (`get_or_create_workspace`'s root-switch cleanup, documented in `workspace_service.jac` as
already "verified live against a real restart") -- but that verification only checked that the
*new* root's children list correctly re-scans from scratch, never that the *old* root's
now-detached children stay gone if the old root were re-queried. This entry's finding suggests that
existing code path may carry the same latent gap, simply never triggered because nothing re-lists
an abandoned workspace root after switching away from it.

## Plan

Workaround shipped in `list_children_by_path`: make the **read** path authoritative against the
real filesystem instead of trusting graph edge state for correctness -- filter out any child whose
`path` no longer exists on disk (`os.path.exists`) before returning it, the same "guarantee the
display is correct regardless of what the graph underneath ends up holding" stance already taken
for the pre-existing duplicate-node de-dup step in the same function. `delete_path`/`rename_path`
still attempt the edge-deletion cleanup (harmless best-effort; matches this project's existing
"detach and let it become graph garbage" convention if it ever does take effect on a later restart
or under different conditions), but nothing depends on it succeeding for correctness anymore.

This is a workaround, not a fix -- the underlying question (does `del` on an edge object reliably
commit across a real `def:pub` request/response cycle, and if not, why does it differ from node
field mutation, which has its own documented but distinct gap) is still open and would need
Postgres-level inspection (the same technique used to root-cause the original field-mutation entry)
to actually resolve. Flagging as `blocker` severity because this affects the correctness of *any*
future feature that needs to durably detach a graph edge and trust that detachment on a later,
separate request -- not just this file tree's delete/rename.
