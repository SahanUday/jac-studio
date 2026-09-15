# 0031 — Never `del` a cache-dict entry keyed by something with graph-edge significance

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

Leave the stale entry in place (harmless) rather than deleting it. Overwrite a flag instead of
removing a key.

## Why

A plain application-level dict `del` — not a graph operation at all — was reproduced in isolation
corrupting an *unrelated* node's edge reachability, with a minimal `Parent`/`Child` node pair.
Tracker entry `2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability` (major,
workaround). Found while root-causing the edge-deletion gap (0030) and distinct from it.

## Consequences

A `del` whose blast radius is not obviously scoped to the dict alone is not safe here, however
ordinary it looks. A future cleanup that "tidies up stale cache entries" can silently break
traversal somewhere unrelated, with no error at the deletion site.
