# 0015 — Default a service to `obj`; promote to `node` only on demonstrated need

- **Date**: 2026-08-23
- **Status**: accepted

## Decision

Make a service a graph `node` only if it must survive a restart, be discoverable by traversal, or
participate in the graph's permission model. Otherwise use a plain `obj`, lazily created and
cached in the same `jid(root)`-keyed dict, never attached to the graph.

## Why

A cached `obj` never pays the ~600us graph query even once (0013). The shape was forced first by
a real bug — a node whose fields transitively hold a self-referential structure crashes graph
persistence (`2026-08-23-node-persistence-crashes-on-self-referential-fields`, workaround-found,
not resolved) — but holds on the merits: `document_service.jac`'s `DocumentBuffer` needs none of
the three properties. `output_service.jac`'s `OutputChannel` later followed the same rule.

## Consequences

Rules out reflexively making every service a node "for consistency". The persistence crash is
still open upstream: any future workbench node (`Workspace`, `File`, `EditorGroup`) that ends up
holding a ported tree structure (an `IntervalTree`, a piece tree) will hit it again.
