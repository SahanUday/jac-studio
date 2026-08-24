# Workspace-graph spike (Phase 2)

Validates the "workspace is the graph" proposal in [`../../docs/architecture.md`](../../docs/architecture.md)
(`Workspace --Contains--> Folder --Contains--> File`) at realistic scale, before the real file-tree
feature gets built on top of it — per the Phase 2 planning discussion that flagged this as an open
gap: Phase 0's `service-registry-spike` validated the graph for *service lookup* (a handful of
small, mostly-static objects), not a deep, editable file tree with hundreds or thousands of nodes.

## What this is

`Workspace`/`Folder`/`File` nodes linked by a `Contains` edge (`src/workspace_graph.jac` +
`src/workspace_graph.impl.jac`), a `scan_directory()` walker that builds the graph from a real
on-disk directory (excluding the usual noise: `node_modules`, `.git`, `.jac`, `dist`,
`__pycache__`, venvs), and query helpers (`list_children`, `count_subtree`, `find_by_path`) shaped
the way a file-tree sidebar would actually use them.

`Workspace` is a real `node` here, not a plain cached `obj` — it clears the bar
`architecture.md`'s "not every service needs to be a node" test sets (real workspace state needs
to survive a restart and be reached by graph traversal), unlike `document_service.jac`'s
`DocumentBuffer`.

Run the correctness suite: `jac test` (9 tests — 7 unit tests against a small synthetic fixture,
2 scale-measurement tests against real directories). `jac check .` is clean except intentional
`any`-typed parameters on the traversal helpers (a `Workspace | Folder` union, matching the
project's existing pattern for genuinely heterogeneous node-or-parent arguments).

## Result: the data model itself is correct; two real problems found around it

**Correctness holds at scale.** Scanned this project's own repo (137 nodes) and the `jaclang`
compiler repo (2,974 nodes — 322 folders, 2,651 files) with an explicit no-duplicate-path
traversal check on top of the normal count comparison. Both pass cleanly: every node is reached
exactly once, `count_subtree`'s independent traversal always matches `scan_directory`'s own
construction count. The one-hop query semantics (`[parent->:Contains:->]`) behave exactly as
`jac guide jac-node-edge-patterns` documents them.

**But two real problems surfaced, not in the data model itself:**

### 1. Query cost at scale makes eager traversal too slow for a responsive file tree

| Target | Nodes | Build (`scan_directory`) | Traverse (`count_subtree`) |
|---|---|---|---|
| jac-studio (this repo) | 137 | 8.86ms | 91.76ms |
| jaclang (real compiler repo) | 2,974 | 1,318ms | 1,570ms |

At real-world scale (~3,000 nodes, not an unusual size for an opened project), building *and*
traversing the tree each take over a second — roughly **3 seconds combined** for something a file
explorer needs to feel instant on open. This is the same per-query cost the Phase 0
service-registry spike measured (~600us/call for a fresh graph query) showing up again, this time
compounded across thousands of one-hop reads during a single recursive traversal rather than one
or two service lookups.

**Implication for the real feature**: the file tree cannot eagerly scan-and-render the whole
workspace on open the way this spike's `scan_directory`/`count_subtree` do. It needs the same
lazy, expand-on-demand model VS Code's own file explorer already uses — populate `Folder` nodes
for a directory only when the user actually expands it, never eagerly recurse the whole tree up
front. This isn't a new idea specific to this spike, but the measured numbers here are the first
real evidence for *why* it's required, not just "how VS Code happens to do it."

### 2. `jac run` persists graph state across separate CLI invocations, and `jac clean --data --force` did not reset it

Discovered by accident: running `jac run main.jac -- <path>` against the same target repeatedly
produced an ever-growing, obviously-wrong node count (up to ~5x inflation after five re-runs),
traced to `get_or_create_workspace`'s `[root-->[?:Workspace]]` fallback finding the *previous*
run's already-populated `Workspace` node and scanning a second (third, fourth...) copy on top of
it. `jac clean --data --force` reported "Nothing to clean" both before and after this was
happening, and no `.jac/data` directory was ever observed to exist in this project — the state
survived somewhere `jac clean` doesn't know to look for a `kind = "cli"` project invoked via
`jac run`, not `jac start`/`jac test`. Root-caused only by switching the measurement into `test`
blocks instead (which `jac-testing` guarantees a fresh graph per test, and this was verified
directly: the same target scanned inside a `test` block never showed the inflation, and produced
consistent single-run numbers across repeated `jac test` invocations).

**Implication for the real feature, separate from the performance one above**: any real
`get_or_create_workspace`-shaped accessor needs to treat "found an existing Workspace" as
`Workspace` already representing a genuinely resumed session (correct for a served app across real
requests, restated below), not accidentally reuse stale state left over by a *different, unrelated
process invocation* the way this spike's plain `jac run` testing loop did. Not directly a risk for
`jac start` (a served app's `root` is properly scoped per authenticated user/session, per the
Phase 0 service-registry findings already baked into `architecture.md`) — but worth being aware of
if any future tooling script uses `jac run` against a shared root the way this spike's manual
`main.jac` entry point did.

## What's NOT covered by this spike

- Incremental updates (a file created/deleted/renamed on disk after the initial scan) — nothing
  here re-syncs the graph with the filesystem after the first scan. A real implementation needs a
  refresh/watch story; not measured or designed here.
- Multi-root workspaces (`architecture.md`'s multiple top-level `Folder` nodes under one
  `Workspace`) — structurally trivial given the data model (just more `Contains` edges off the
  same `Workspace`), but not specifically exercised here.
- Permission/multi-user scoping for workspace nodes — this spike never runs as a served app, so it
  says nothing new about the `jid(root)`-keying discipline beyond what Phase 0 already established;
  `get_or_create_workspace` follows that same discipline by construction, not because this spike
  re-validated it.
- Lazy/on-demand scanning itself is not implemented here — this spike identifies that it's needed
  (see finding 1) but building it is real feature work, not spike work.
