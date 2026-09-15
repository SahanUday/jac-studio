# 0045 — Build a native LSP client as core workbench infrastructure, against `jac lsp`

- **Date**: 2026-08-31
- **Status**: accepted

## Decision

Spawn `jac lsp` as a subprocess and speak LSP JSON-RPC-over-stdio from a generic client module
built as core workbench infrastructure — no `vscode`-API shim, no `.vsix` loading, no extension
host. Bulk-edit application and the outline/breadcrumbs views are part of the same deliverable.

## Why

The old open question ("is a usable LSP client library reachable via interop?") was aimed at the
wrong half of the problem: jaclang already ships a real language server. `jac lsp` is a
first-party CLI command (`jaclang/cli/commands/tools.jac`) starting
`jaclang.lsp.server.server.run_lang_server()`, implementing completion, hover, definition,
references, rename, document symbols, semantic tokens and formatting against real Jac source —
the same server the published VS Code extension merely wraps.

## Consequences

Design the provider interface generically enough that a second server (e.g. `pyright`) is a
second client instance, not a rewrite — but ship Jac first. "A rename provider that can't apply
its own result isn't done." Call hierarchy is explicitly out of scope: `jac lsp` has no
call-hierarchy handler to wire against. Closed `2026-08-22-lsp-dap-client-unresearched`.
