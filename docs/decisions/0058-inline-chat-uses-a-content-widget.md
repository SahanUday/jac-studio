# 0058 — Inline chat is a Monaco content widget, not a `ZoneWidget`

- **Date**: 2026-09-04
- **Status**: accepted

## Decision

`inline_chat_widget.jac`'s Ctrl+I popover is anchored at the cursor via
`editor.addContentWidget`, overlapping nearby lines rather than pushing them apart. React content
reaches Monaco's externally-owned DOM node via `ReactDOM.createPortal`.

## Why

A deliberate, documented scope cut: upstream uses a `ZoneWidget`, which is real VS Code's own
internal contrib class — confirmed **not** part of the public `monaco-editor` npm package's
exported API surface this project embeds.

## Consequences

The portal direction is a genuinely new integration pattern here (every other Monaco-facing
provider goes the opposite way) and was verified live before being relied on. The popover makes
its own `start_chat_turn` call as a fully independent session — closing it ends that context, no
shared state with the sidebar — and handles tool approval inline, since its
`tool_approval_request` events arrive on a separate SSE stream the sidebar never sees.
