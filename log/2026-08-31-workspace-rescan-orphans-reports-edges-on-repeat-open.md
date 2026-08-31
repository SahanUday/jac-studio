---
id: 2026-08-31-workspace-rescan-orphans-reports-edges-on-repeat-open
date: 2026-08-31
category: compiler-bug
severity: major
status: open
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jaseci, anchor, persistence, workspace, diagnostics, reports-edge, root-node]
---

## What happened

Verifying Phase 4's task runner live: ran a task, confirmed `list_all_diagnostics()` correctly
returned 3 diagnostics attached to a real file. Then, with no further task runs, simply opening a
**new browser session against the same server process** (same `root`, confirmed identical workspace
via `get_current_workspace`) and calling `list_all_diagnostics()` again returned `[]` -- every
diagnostic gone, with no `clear_diagnostics` call in between. Reproduced 4/4 times across different
triggers that all share one thing in common: a second real request calling `get_or_create_workspace`
for a workspace that was already open in an earlier request within the same long-running server
process (a page reload, or simply opening a second browser tab against the same session).

The server log shows a warning at exactly this moment, once per second-or-later `open_workspace`
call:

```
{"msg": "[trace=...] could not materialize anchor a0ccbba1-0a64-4570-8df7-962229c98fcd (Workspace); skipping"}
```

## Root cause (theory, not fully confirmed against jaseci internals)

`workspace_service.jac`'s `get_or_create_workspace` (unmodified by this PR):

```jac
key = jid(root);
if key in _cached_workspace_jid {
    ws = jobj(_cached_workspace_jid[key]) as Workspace;
} else {
    ...
}
if ws.root_path != root_path {
    for e in [edge ws ->:Contains:->] { del e; }
    ws.root_path = root_path;
    ws.scanned = False;
}
```

If `jobj(_cached_workspace_jid[key])` fails to materialize the anchor (the warning above), the
resulting `ws` appears to come back with default/empty field values rather than raising -- so
`ws.root_path` reads as `""`, which is `!= root_path`, which trips the "different root, detach the
old `Contains` subtree and rescan" branch. The file tree itself looks unaffected (a fresh scan
produces the same file *names*, so nothing looks wrong in the Explorer), but the **new** scan
creates entirely new `File` node identities for the same paths. Anything that was attached to the
**old** `File` node via a `Reports` edge (this phase's own `Diagnostic` nodes -- the first real
producer this data model has ever had) becomes unreachable: `get_file_node_by_path` now resolves to
the new node, which has zero `Reports` edges of its own.

Confirmed this isn't specific to diagnostics: `list_children_by_path` was checked immediately after
the same trigger and still returned the correct file list, exactly as this theory predicts (a
silent, invisible rescan, not a visible failure) -- the *loss* is only visible because
`Diagnostic`/`Reports` is the first workspace-graph feature that attaches state to a `File` node the
Explorer itself doesn't already re-derive fresh on every read.

## What this isn't

Not the already-documented `2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache` finding
(that one is about an in-memory `glob` dict reading empty across a cross-module call; this one
reproduces with **zero cross-module calls at all** -- a single module, `list_all_diagnostics`,
called twice from two ordinary direct RPC requests) and not the `2026-08-28-field-mutation-on-
cached-node-not-persisted` finding either (that one is about a mutated field not being *durably
committed*; this one is about a *read* -- `jobj()` -- apparently failing to materialize an anchor
that was, by every other evidence, committed just fine).

## Impact on this PR

`task_service.jac`'s own re-run-duplication fix (batch-marker filtering, see
`diagnostics.jac`'s docstring) is unaffected and independently verified -- it's a different bug,
already fixed, with its own regression test. This finding is a pre-existing gap in
`workspace_service.jac`'s anchor-caching path that this phase's diagnostics work is simply the first
feature to make visibly, jarringly wrong (diagnostics quietly vanishing on an ordinary page reload).
Not fixed in this PR -- `get_or_create_workspace` is core, heavily-relied-on infrastructure several
other features already depend on, and a rushed fix without first understanding *why* `jobj()`
apparently fails to materialize a real, previously-committed anchor risks a worse regression than
the bug itself.

## Plan

Before the next feature that attaches durable state to a `File`/`Folder` node via a custom edge
type (the LSP client's diagnostics, or any future per-file annotation), check whether this still
reproduces. To actually root-cause it: instrument `get_or_create_workspace` to log `jobj()`'s
literal return value (not just whether the `if` branch was taken) when the "could not materialize
anchor" warning fires, across a clean, minimal repro (two sequential real HTTP requests, no
concurrent load) -- this session's own repro was found amid heavy concurrent/automated testing
(many rapid `jac browse` sessions, several hard `kill -9` server restarts), so isolating whether
process load or restart history is a contributing factor, versus this reproducing on a single clean
process every time, is the first thing to nail down. If `jobj()` on a failed materialize truly
returns a non-`None`, non-raising stub object, that's arguably a jaseci-level runtime gap worth its
own upstream report; if it turns out to be specific to this project's own caching pattern, the fix
likely belongs in `get_or_create_workspace` itself (verify the resolved node's identity/`jid` before
trusting its field values, not just checking `key in _cached_workspace_jid`).
