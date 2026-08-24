---
id: 2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale
date: 2026-08-24
category: ergonomics
severity: major
status: resolved
phase: 2
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: "src/vs/workbench/contrib/files"
upstream_issue: ""
tags: [performance, graph-query, workspace-graph, phase-2, file-tree]
---

Found in `internal/workspace-graph-spike/`, built to validate `docs/architecture.md`'s
`Workspace --Contains--> Folder --Contains--> File` proposal at realistic scale before Phase 2's
file-tree feature gets built on it -- Phase 0's `service-registry-spike` only ever validated the
graph for service lookup (a handful of small, static objects), never a deep, editable tree with
real node counts.

**What was found**: scanned this project's own repo (137 nodes) and the `jaclang` compiler repo
(2,974 nodes -- 322 folders, 2,651 files) via a real recursive `os.listdir`-backed scan into
`Folder`/`File` nodes, then measured both construction and a full recursive traversal
(`count_subtree`, using the documented one-hop `[parent->:Contains:->]` query at every level):

| Target | Nodes | Build | Traverse |
|---|---|---|---|
| jac-studio | 137 | 8.86ms | 91.76ms |
| jaclang | 2,974 | 1,318ms | 1,570ms |

At real-world scale, building and traversing the tree each take over a second -- roughly 3 seconds
combined for something a file explorer needs to feel instant opening. This is the same per-query
cost `2026-08-23-service-registry-query-cost` measured (~600us/call for a fresh graph query)
showing up again, compounded across thousands of one-hop reads in one recursive walk instead of
one or two service lookups. Data model correctness itself was verified separately and holds --
every node reached exactly once, no duplicates, `count_subtree`'s independent count always matches
construction's own count (see the spike's own test suite and README for the full methodology).

**Why `major`, not `minor`**: this directly blocks Phase 2's file-tree exit criteria ("browse files
in a tree" needs to feel instant, not take ~1.5+ seconds on a real-sized project) if built the
naive way this spike's own `scan_directory`/`count_subtree` do it.

**Plan**: resolved, not a workaround -- the real file-tree feature must NOT eagerly scan-and-render
the whole workspace on open. It needs the same lazy, expand-on-demand model VS Code's own file
explorer already uses: populate a `Folder`'s children only when the user actually expands it in
the UI, never eagerly recurse the whole tree up front. This isn't a novel idea specific to this
finding, but the measured numbers here are the first real evidence for *why* it's required for
this project specifically, not just "how VS Code happens to do it" -- worth citing when Phase 2's
file-tree sidebar gets designed, so the lazy-loading requirement isn't accidentally dropped as a
premature optimization.
