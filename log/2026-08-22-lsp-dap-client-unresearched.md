---
id: 2026-08-22-lsp-dap-client-unresearched
date: 2026-08-22
category: doc-gap
severity: major
status: resolved
phase: 4
subsystem: extensions
jac_version: ""
related_vscode_ref: "src/vscode-dts/vscode.d.ts (48 register*Provider methods), src/vs/editor/contrib/{suggest,hover,gotoSymbol,rename}"
upstream_issue: ""
tags: [lsp, dap, language-intelligence, python-interop, research-needed]
---

A second, targeted re-investigation of the real VS Code source found that our original
architecture proposal only accounted for syntax highlighting (Phase 3), not language intelligence
(autocomplete, hover, go-to-definition, rename, code actions) — a materially larger and separate
subsystem in upstream VS Code, almost always backed by a real Language Server Protocol (LSP)
server process. This sits alongside the already-known Debug Adapter Protocol (DAP) gap
(`2026-08-22-no-extension-sandbox.md` covers the sandboxing side; the DAP client itself was noted
as an open question in `architecture.md`) — both are JSON-RPC-shaped protocols with the same
"spawn a subprocess, speak a wire format" integration shape, and neither has been researched yet.

**Impact on jac-studio**: without language intelligence, jac-studio is a text editor with syntax
color, not a usable IDE — this is arguably a bigger gap to close than extension sandboxing for
making the product actually good to use day to day, even though sandboxing is the scarier
*architectural* risk.

**Plan**: research whether a Python (or npm) LSP/DAP client library is usable via Jac's interop
before committing to building either from the wire protocol up — both questions should be
answered together, not separately, since the integration shape is the same. First concrete task
for whoever picks up Phase 4/5 language-intelligence or debugging work.

## RESOLVED (2026-09-02)

Both questions this entry raised were answered, and both clients shipped as real, working,
live-verified Phase 4 features -- neither needed an external Python/npm client library:

- **LSP**: `jaclang` already ships a real, working language server, started via the first-party
  `jac lsp` CLI command (`jaclang.lsp.server.server.run_lang_server()`). No client library was
  needed at all on that side -- `lsp_client.jac` spawns it as a subprocess and speaks LSP's
  JSON-RPC-over-stdio wire format directly. Shipped across PRs #52 (completion + live diagnostics),
  #53 (hover), #54 (go-to-definition), #55 (find-references), #56 (rename, with real multi-file
  bulk-edit application), #57 (outline), and #58 (breadcrumbs).
- **DAP**: no native jaclang DAP server exists (`jac run --debug` is a bare `pdb`-based debugger,
  not a JSON-RPC/DAP server) -- but `debugpy` (Microsoft's Python DAP implementation) works
  directly against jaclang-compiled bytecode, confirmed live end-to-end (see
  `2026-08-31-jaclang-no-native-dap-server-but-debugpy-works-against-compiled-jac-source`, the
  entry this finding directly fed into). Shipped in PR #60 -- a real breakpoint/step/call-stack/
  variable-inspection debug session against a `.jac` file.

See `docs/phases/phase-4-native-feature-parity.md` for the full phase summary.
