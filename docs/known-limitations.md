# Known limitations

What doesn't work yet, and what is a deliberate trade-off. Settled decisions live in
[`decisions/`](decisions/); Jac/tooling blockers live in the challenge tracker. This file is for
gaps a user could actually hit.

## Open gaps

| Gap | Effect | Fix would be |
|---|---|---|
| **Cursor doesn't move in an already-open tab** | `initialCursor` is read once at mount, so clicking a search result, problem, go-to-definition or outline entry only jumps the cursor when the tab wasn't already open. Otherwise it just activates the tab. | An imperative `revealLine`/`setPosition` call instead of relying on mount-time props |
| **Breadcrumbs empty on a freshly opened tab** | `jac lsp` was measured at 30s+ to type-check a 7-line file, and `textDocument/documentSymbol` answers from current state rather than waiting. A single 4s retry is an explicit partial mitigation. | An LSP-side "outline changed" push, which doesn't exist today |
| **No call hierarchy** | `jaclang.lsp.server.server` ships no call-hierarchy handler, so there is nothing to wire a UI to. | Server-side capability first |
| **Outline reflects last save, not the live buffer** | A sidebar view can't reach a mounted editor's model without pulling in `loader.init()`'s singleton API. Same trade-off as diagnostics refreshing on save. | Either the singleton API, or routing outline through the editor instance |
| **Outline highlight doesn't auto-reveal** | The cursor-containment highlight won't expand collapsed ancestors the way real VS Code does. | Tree auto-expansion on highlight |
| **No PTY in the terminal** | Commands stream over RPC/SSE, so interactive programs, job control and TTY-aware behavior don't work. One command runs at a time. | A real PTY backend |

## Unresolved runtime traps

Root cause not isolated. Don't assume these are fixed.

- **A `glob` cache can read back empty** when its function is reached as a nested cross-module
  `def:pub` call rather than its own endpoint, despite an identical `jid(root)`.
  `2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache`
- **A folder's `scanned=True` flag can get permanently stuck** after edge loss. Three same-day
  self-heal attempts each passed `jac check`/`jac test` and failed differently live, and were
  reverted. The edge-loss theory is unconfirmed, not disproven.
  `2026-09-01-folder-scan-flag-permanently-stuck-after-edge-loss`
- **Diagnostics duplicated** under an in-memory index that had the same `jid(root)` shape as a
  working one. Only a graph-only `batch` field fixed it; why the index failed is still open.

- **A directory deleted and recreated at the exact same path fast enough to coalesce the watcher
  events** can leave its new contents unwatched until the workspace is reopened. Rare, not yet hit
  in practice, and the cost is a stale nested subtree, not a crash — not worth defensive bookkeeping
  until it's a real, reproduced problem.

## Accepted trade-offs

These are deliberate. Don't "fix" them without a reason.

- **Closed tabs' Monaco models are never disposed**, and `_focused_editor_handlers` entries are
  never removed on unmount. Correct for a local single-user tool; revisit if that changes.
- **Ephemeral state is excluded from the session** — dirty flags, active bottom panel,
  notifications, pending AI prompts. Persisting a dirty flag without the unsaved buffer it
  describes would be actively misleading, since keystrokes never round-trip to the server.
- **Orphaned graph nodes are not reclaimed.** The read path de-duplicates instead, because the
  write path cannot be made atomic — see the tracker entries on `WriteConflict` and edge deletion.
- **SCM is ungated while tasks and the terminal are gated.** Git runs as fixed subcommands passed
  as argument lists; tasks use `shell=True` with an arbitrary string. The asymmetry is the point.
- **Outline is a top-level activity-bar entry**, not an Explorer sub-section as in real VS Code —
  the file tree has no collapsible-sections concept. An explicit fidelity compromise.
- **Debugging is one combined panel** — toolbar, status, call stack, variables and output together,
  rather than VS Code's Debug sidebar plus a separate Debug Console. Enough to set a breakpoint and
  step; splitting it is parity work (M10).
- **The title bar has no window controls or menu bar**, since the browser owns window chrome for a
  web app. The Command Center opens the command palette rather than a unified file-and-command
  search, and the workspace name label is static.
