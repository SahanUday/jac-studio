---
id: 2026-08-23-client-editor-no-per-keystroke-request-queuing
date: 2026-08-23
category: ergonomics
severity: minor
status: open
phase: 1
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [client-component, async, editor-core, decision-point]
---

## What we tried

Testing the Phase 1 minimal client editor component (`src/editor/client/text_editor.jac`) end to
end with a real running server (`jac start --dev` + `jac browse`): typing character keys with no
artificial delay between `jac browse press` calls (simulating faster-than-human or programmatic
input, e.g. paste or held-key auto-repeat).

## What happened

Characters landed out of order / scrambled (`"Hi there"` typed as 8 back-to-back keypresses came
back as `"ithWere"`, spliced partway into the seeded document's own text). The same sequence typed
with a 250ms delay between keypresses (ordinary human typing speed) landed correctly every time,
repeated across several runs.

Root cause is in this project's own component code, not a Jac limitation: each keydown handler
does `new_lines = await apply_document_edit(cursor_line, cursor_column, ...)` then updates local
`cursor_line`/`cursor_column` from the *result*. If a second keydown fires before the first
request's response has come back and updated cursor state, the second edit computes its
insertion point from stale `cursor_column`, and out-of-order response arrival can additionally
apply edits to the buffer in the wrong sequence entirely. There is no request queue, debounce, or
per-request cursor-generation check.

## Plan

Not fixed in this pass -- Phase 1's exit criteria ("type, delete... as a standalone demo") doesn't
require handling adversarial input rates, and fixing this properly is exactly the kind of
work the roadmap's own "decision point" should settle *first*: a hand-rolled request queue here is
throwaway effort if the decision lands on a Monaco-embed bridge instead (which owns its own input
pipeline and wouldn't need this fix at all). Documented here so it isn't rediscovered as a
surprise, and so it's an explicit input to that decision rather than a silent gap:

- If the decision lands on **continuing the native client component**: fix belongs in
  `text_editor.jac`, most simply as a per-request monotonic sequence number (only apply a
  response if it's the most recent request issued) or a strict queue (never issue edit N+1 until
  edit N's response has been applied). Either is a small, well-understood client-side fix.
- If the decision lands on **the Monaco-embed bridge**: this specific gap is moot (Monaco owns its
  own model and input handling internally), and this finding becomes a data point *for* that
  direction rather than a task to carry forward.
