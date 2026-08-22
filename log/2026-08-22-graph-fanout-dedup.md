---
id: 2026-08-22-graph-fanout-dedup
date: 2026-08-22
category: workaround-found
severity: minor
status: resolved
phase: 2
subsystem: persistence
jac_version: "unspecified — see littleX example"
related_vscode_ref: ""
upstream_issue: ""
tags: [graph, allroots, dedup, walker-patterns]
---

Graph fan-out via `allroots()` does not auto-deduplicate: a node reachable via multiple paths from
different roots gets visited/reported once per path, not once total. Observed directly in the
littleX example's `get_trending`/`get_all_profiles` walkers, which both work around it manually
with jid-based dedup (accumulate into a dict keyed by `jid(node)` instead of a plain list).

**Impact on jac-studio**: any future aggregate-across-users query (e.g., "list all installed
extensions across the deployment," "search all workspaces on this server" if we ever add
multi-user features) needs the same manual dedup — it's not automatic.

**Workaround**: use a dict keyed by `jid(node)` (or an equivalent set-of-ids check) instead of a
plain list/append whenever a walker's `report` accumulates results reached through `allroots()` or
any other multi-path traversal. Confirmed workable in a real, working example app (littleX), not
just theorized — hence `status: resolved` rather than `open`.
