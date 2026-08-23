---
id: 2026-08-23-node-persistence-crashes-on-self-referential-fields
date: 2026-08-23
category: compiler-bug
severity: blocker
status: workaround-found
phase: 1
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [node, persistence, service-registry, piece-tree, interval-tree, sentinel]
---

## What we tried

Building the first real consumer of the root-graph-as-service-registry pattern outside the
Phase 0 spike: a `DocumentBuffer` `node`, reachable from `root` the same way
`service-registry-spike/src/config_service.jac`'s `ConfigService` is, holding a
`PieceTreeTextBuffer` (the ported piece-tree buffer, `piece_tree_text_buffer.jac`) as a `has`
field, for the Phase 1 client editor component to read/write through `def:pub` RPC functions.

## What happened

`root ++> DocumentBuffer()` succeeds (the returned node's `jid()` resolves fine), but the process
crashes with `RecursionError: maximum recursion depth exceeded` at session-commit time (visible as
`WARNING - commit on close failed: RecursionError...` under `jac run`, or surfacing through
`jac test`'s assertion-failure serializer when a later query touches the graph). Isolated with a
minimal repro, confirmed the trigger precisely:

```jac
obj SelfLoop {
    has val: int;
    has next: SelfLoop postinit;
    def postinit { self.next = self; }
}
node Holder {
    has thing: SelfLoop postinit;
    def postinit { self.thing = SelfLoop(val=1); }
}
with entry:__main__ {
    h = root ++> Holder();   # succeeds
}                             # crashes here, at commit-on-close
```

A plain `SelfLoop(val=1)` constructed and used WITHOUT ever attaching it (directly or
transitively) to a `node` reachable from `root` works perfectly fine — the crash is specifically
in the graph-persistence/serialization layer, which walks an attached node's `has` fields
recursively with **no cycle detection**. Any self-referential object graph reachable from a
persisted node's fields triggers it, whether the self-reference is one hop (`next = self`,
`SENTINEL.parent = SENTINEL`) or several hops deep through wrapping `obj`s (our real case:
`DocumentBuffer.buffer: PieceTreeTextBuffer` → `.piece_tree: PieceTreeBase` →
`.tree_root: TreeNode` → `SENTINEL.parent == SENTINEL`).

**This directly conflicts with an idiom this project has already established and validated twice.**
Both `interval_tree.jac`'s `IntervalNode`/`SENTINEL` and `piece_tree_base.jac`'s `TreeNode`/
`SENTINEL` use a self-referential sentinel (`SENTINEL.parent = SENTINEL`, etc.) as the correct Jac
translation of upstream's `null!`-typed sentinel pattern — documented in both modules' docstrings,
and specifically justified by `==` being identity comparison on a plain `obj` in this Jac build
(`2026-08-23-obj-equality-not-structural`). That idiom is completely correct and necessary for the
tree algorithms themselves. It just cannot currently be attached to a persisted `node` — a real,
previously-undiscovered interaction between two separately-validated pieces of this project (the
translator's tree-port idiom, and the service-registry pattern), only surfacing now that Phase 1
is the first time a ported tree structure is being held by a service-registry node.

## Plan

Not filed upstream yet — needs a jaseci maintainer to confirm whether cycle detection is missing
entirely from the persistence serializer or just mis-implemented for this case, and whether the
fix belongs in the serializer (the more likely and more valuable fix, since it would unblock this
pattern generally) or is a fundamental constraint of the current persistence model worth
documenting instead. The minimal repro above is ready to hand off as-is.

**Workaround adopted for `document_service.jac`**: `DocumentBuffer` is a plain `obj`, not a
`node` — held in the existing `jid(root)`-keyed cache dict directly, with no `root ++>` edge and
nothing added to the persisted graph. This keeps the correct per-user isolation the
service-registry pattern's caching rule requires (see `config_service.jac`'s own docstring and
`2026-08-23-service-registry-query-cost`), but gives up real persistence-by-reachability — the
document's content lives only for the server process's lifetime, not across restarts. Acceptable
for now: Phase 1's roadmap item doesn't call for a real save-to-disk action yet ("no save action to
wire up yet -- there's nowhere to save *to* until a real file-system service exists"). This is a
`workaround-found`, not `resolved`: the correct permanent fix is for node persistence to handle
cycles, at which point `DocumentBuffer` (and any other node wanting to hold a ported tree
structure) should go back to being a real graph node. Revisit once fixed upstream.

**Broader implication worth flagging for later phases**: any future workbench-graph node
(`Workspace`, `File`, `EditorGroup`, etc. from `architecture.md`'s data model) that ends up
holding — directly or via a wrapped field — an `IntervalTree` (decorations) or the piece-tree
buffer itself will hit this identical crash the moment it's attached to `root`. Worth resolving
upstream before Phase 2's workbench-shell work starts wiring the file/editor graph for real,
rather than rediscovering this per-node.
