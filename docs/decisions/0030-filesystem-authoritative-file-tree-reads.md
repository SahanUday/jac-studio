# 0030 — Make the file-tree read path authoritative against the real filesystem

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

`workspace_service.jac`'s `list_children_by_path` checks `os.path.exists` rather than trusting
graph edge state for correctness — the same stance already taken there for duplicate-node dedup
(0023). A workaround, not a fix.

## Why

`del` on an edge object inside a `def:pub` does not reliably take effect for a *later, separate*
real HTTP request's traversal, even though the identical code passes every `jac test` — which
never crosses that commit boundary at all. Confirmed live: deleting a file via the context menu
removed it from disk correctly, but the detached node kept reappearing in every subsequent
`list_children_by_path`, indefinitely. Tracker entry
`2026-08-28-edge-deletion-not-committed-across-real-http-requests` (blocker severity).

## Consequences

Affects any future feature needing to durably detach an edge and trust that on a later request —
not just the file tree. `get_or_create_workspace`'s own root-switch edge cleanup was only ever
verified for "the new root re-scans correctly", never for "the old root's detached children stay
gone", so it may carry the same latent gap. Verify explicitly; do not assume the pattern is safe.
