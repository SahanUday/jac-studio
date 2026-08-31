---
id: 2026-08-31-client-import-of-server-function-always-compiles-async-regardless-of-sync-ness
date: 2026-08-31
category: doc-gap
severity: major
status: workaround
phase: 4
subsystem: editor-core
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac2js, placement-solver, rpc, async, client-server-boundary]
---

## What we tried

Building the breadcrumb bar for the native Jac LSP client (`docs/roadmap.md` Phase 4), we needed a
pure containment-check function -- "which symbol in this already-fetched tree contains cursor
position (line, column)" -- called from `monaco_editor.jac` (a client component) on every cursor
move. The function itself (`symbol_path_at_position`) does no I/O at all: it just walks a list of
dicts already sitting in memory.

The obvious place to put it was next to the function that produces that data,
`get_document_symbols`, inside `lsp_client.jac` -- a module the placement solver correctly
identifies as server-anchored (it spawns the `jac lsp` subprocess, uses `root`/`jid`, etc.). We
wrote `symbol_path_at_position` as a plain sync `def:pub` there and imported it into
`monaco_editor.jac`.

## What happened

`jac check` rejected the call site immediately:

```
error[E1042]: Expected list[dict[str, Any]], but got Coroutine[<any>, <any>, list[dict[str, Any]]]
-- this call returns a coroutine that was not awaited

help: Add 'await' to the call, e.g. 'await foo()'. 'sv import' (server) functions are async RPC
stubs on the client and always need 'await'.
```

The function was declared as a plain, synchronous `def:pub` -- never `async` -- yet the checker
treats the call as returning a `Coroutine` and insists on `await`. Confirmed this isn't specific to
this one function: every other `def:pub` we import cross-boundary from a server-anchored module
into client code (`get_completions`, `get_hover`, `get_definition`, `get_references`,
`get_rename_edits`, `get_document_symbols`, `apply_disk_rename_edits`, all in the same
`lsp_client.jac`) is *also* always called with `await` from client code, even though several of
them are internally simple and could in principle be synchronous. We had been treating this as "of
course they're async, they're RPC calls" without separating two different facts: (1) they need
`await` because calling them *crosses a client/server boundary at all* (any such call compiles to a
`fetch`-based RPC stub, which is inherently a `Promise`), independent of (2) whether the original
function's own body does anything async. The checker's error message itself names this precisely:
"'sv import' (server) functions are async RPC stubs on the client **and always need 'await'**" --
regardless of the source declaration.

This matters because it isn't just a syntax inconvenience. `symbol_path_at_position` was about to
be called on *every cursor move* inside the editor. If we had "fixed" the type error by adding
`await` and moved on, the fix would have compiled and run -- but it would have silently turned a
purely local, already-in-memory computation into a full network round trip to jaseci's own server
on every keystroke that moves the cursor, exactly the per-keystroke RPC cost this project's own
Monaco integration has explicitly refused to pay everywhere else (`monaco_editor.jac`'s own
docstring: no `value`-controlled Monaco binding, no `onDidChangeModelContent`-triggered server
sync, diagnostics refresh only on save/completion, not per-keystroke). A plausible, compiling fix
would have reintroduced the exact bug this project has spent several PRs deliberately avoiding.

## The actual fix

Not a workaround on the call site -- a placement fix. Moved `symbol_path_at_position` (and its
small private helper, `_position_in_range`) out of `lsp_client.jac` entirely, into a new,
genuinely client-only module with zero server evidence of its own (no `root`/`jid`, no imports of
anything server-anchored): `src/editor/client/breadcrumb_symbols.jac`. Once neither the function
nor its home module has any server evidence, the placement solver keeps it client-side, and the
call from `monaco_editor.jac` compiles as an ordinary local function call -- no `await`, no RPC, no
network round trip. Pinned it to `"client"` in `[placement.pins]` anyway as insurance (the module
genuinely exists to *avoid* a per-keystroke RPC round trip, so a future placement regression here
would be a real, silent performance bug, not just cosmetic).

## Plan

The rule this project now follows: **before writing a pure/local helper next to an existing
server-anchored RPC function "because that's where the data comes from," check whether it will
ever be called from client code on a hot path (per-keystroke, per-render, per-frame).** If so, it
needs to live in a module with no server evidence, full stop -- not because the checker won't let
you call it sync (it will, once placed correctly), but because *placement*, not the function's own
`async`-ness, is what actually determines whether a cross-boundary call becomes a network request.
Upstream, the ergonomic gap is that the compiler error message, while accurate, reads like "you
forgot `await`" rather than "this call just became a network request" -- a more explicit checker
diagnostic (e.g. distinguishing "this identifier resolves to a different placement zone than its
caller" from a generic missing-await) would have surfaced the actual architectural implication
immediately instead of requiring us to reason it out by hand. Filing this as a `doc-gap`/ergonomics
finding rather than a `compiler-bug`: the current behavior (cross-zone calls are always async RPC
stubs) is a deliberate and correct design, just under-explained in a way that made a real
performance footgun easy to almost ship.
