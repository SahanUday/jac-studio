---
id: 2026-08-24-service-registry-node-is-not-the-default
date: 2026-08-24
category: doc-gap
severity: minor
status: resolved
phase: 1
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [service-registry, performance, architecture, phase-1, phase-2]
---

Follow-on to `2026-08-23-service-registry-query-cost` and the Phase 0 spike
(`service-registry-spike/`). Both `docs/architecture.md`'s service-registry section and the
spike's own README verdict read as a blanket rule: every service module built on the pattern
should be a `node`, resolved once per `root` and cached in a keyed `glob dict`. That framing is
broader than the pattern actually needs, and was never corrected until this entry.

**What was found**: node-ness and the caching discipline are two separate decisions, not one.
The caching rules (key by `jid(root)`, add a `_reset_<x>_cache_for_tests()` hook) are mandatory
*if* a service is a node, but whether it should be a node at all is a prior, independent question
with three concrete tests: does it need to (1) survive a process restart without hand-written
save/load code, (2) be discoverable by graph traversal/edges from another node, or (3) participate
in the graph's permission model (`:priv`, `grant`/`revoke`)? If none apply, a plain `obj` cached
the same `dict[jid(root), T]`-keyed way gets the identical "created once, shared, found from
anywhere" property with zero graph-query cost -- not even the one-time ~600us/call hit a cached
node still pays on first resolution per root.

This wasn't purely theoretical: `src/editor/document_service.jac`'s `DocumentBuffer` (built during
Phase 1) already is a plain `obj`, not a `node` -- arrived at while fixing an unrelated bug
(a self-referential field graph crashing persistence serialization), but it holds up independently
of that bug on the three-question test above. A document buffer doesn't need to survive a restart
separately from the file it mirrors on disk, isn't traversed to from another node, and needs no
permission scoping beyond the `jid(root)` cache key it already has. The written guidance just never
caught up to what the code had already correctly done.

**Why this matters going into Phase 2**: more services are about to be built (file tree, command
registry, workspace state) directly off the guidance in `architecture.md` and the
`jac-studio-architecture` skill. Left uncorrected, that guidance would default every one of them
to a graph node -- including ones like a command registry that likely don't need restart-survival,
traversal, or permission scoping at all -- paying graph-query overhead and inheriting the
node-persistence self-reference risk (see `2026-08-23-node-persistence-crashes-on-self-referential-fields`)
for no benefit.

**Plan**: this is a documentation correction, not a code change -- `docs/architecture.md` gained a
new "Not every service needs to be a node" subsection, `service-registry-spike/README.md` got a
visible correction section (not a silent rewrite, per this tracker's own convention), and the
`jac-studio-architecture` skill got the same three-question test added ahead of its existing
node-caching rules. No further action needed; the per-service test should just be applied honestly
when Phase 2's file-tree/command-registry/workspace-state services get designed -- expect at least
one of those (file tree / workspace state, likely) to legitimately need `node`, and at least one
(command registry) to likely not.
