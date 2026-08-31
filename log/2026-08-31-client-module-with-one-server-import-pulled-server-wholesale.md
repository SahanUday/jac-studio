---
id: 2026-08-31-client-module-with-one-server-import-pulled-server-wholesale
date: 2026-08-31
category: compiler-bug
severity: major
status: workaround-found
phase: 4
subsystem: workbench-shell
jac_version: "0.36.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jaseci, placement-solver, codespaces, client-server, monaco]
---

## What happened

`src/editor/client/jac_completion_provider.jac` is genuinely client-only code -- its entire job is
calling `monaco.languages.registerCompletionItemProvider(...)` against the real browser `monaco`
global. It also imports one server `def:pub` function (`lsp_client.get_completions`) for the single
RPC boundary it actually needs. Live (`jac browse`), calling `register_jac_completion_provider`
from `monaco_editor.jac`'s `beforeMount` immediately threw:

```
Exception: Function register_jac_completion_provider failed:
{"error": {"code": "EXECUTION_ERROR", "message": "'dict' object has no attribute 'languages'"}}
```

...and the browser's network tab showed the call going out as `POST /function/
register_jac_completion_provider` -- the placement solver had placed the **entire module**
server-side, not just lowered the one `get_completions` call into an RPC boundary. Server-side,
`monaco` (the function's own first parameter) arrives as some placeholder object with no
`.languages` attribute, since there is no real Monaco instance on the server at all.

## Root cause (inferred from behavior, not from reading the solver's own source)

This is the **inverse** of the already-documented `2026-08-31-anchor-free-root-using-module-pulled-
client-wholesale` finding. That one: a module with genuine server-only behavior (`jid(root)`) but
*no* Python import or graph archetype for the solver's evidence rules to detect got pulled entirely
client-side. This one: a module that's otherwise unambiguously client-only (no `jid`/`root`/graph
access anywhere, its whole body is DOM/Monaco-global manipulation) gets pulled entirely
**server**-side, apparently because it imports one server `def:pub` function. The solver's evidence
rules seem to treat "imports something server-side" as evidence for the *whole module's* placement,
rather than recognizing that a client module calling one server function is exactly the normal
shape of an RPC boundary (the same shape `document_service.open_document`/`save_document` already
work correctly when imported from client components like `monaco_editor.jac`) -- so something about
*this specific* module's mix of evidence tips the solver's placement decision the wrong way, though
the precise trigger (maybe: no other server-clinching evidence *against* server placement, versus
`monaco_editor.jac`'s own module having enough independent client-side evidence to anchor it) isn't
fully isolated.

## Workaround

`[placement.pins]` in `jac.toml`, the same mechanism the earlier (inverse) finding already
established:

```toml
[placement.pins]
"src.editor.client.jac_completion_provider" = "client"
```

Verified live against the same repro: `register_jac_completion_provider(monaco)` now genuinely
runs client-side, and real completions render correctly in Monaco's suggest widget.

## Plan

Both this and the earlier `anchor-free`/wholesale-placement finding are evidence that the
placement solver's per-module (rather than per-*symbol*) granularity is a recurring source of
friction whenever a module *legitimately* needs to reference both sides of the client/server
boundary -- which is exactly what a client component wrapping one RPC call needs to do, a totally
ordinary shape, not an edge case. Worth flagging to the jaseci team as a pattern (two real,
opposite-direction instances of the same underlying granularity gap within one project, in one
week) rather than two isolated one-off pins. Any future client component that imports even one
server `def:pub` function should be checked for this the same way (`jac browse`, watch the network
tab for the call landing on `/function/<name>` when it shouldn't) before assuming a pin isn't
needed.
