---
id: 2026-08-22-no-extension-sandbox
date: 2026-08-22
category: missing-feature
severity: blocker
status: open
phase: 6
subsystem: extensions
jac_version: "unspecified — see jac-native-wasm.md"
related_vscode_ref: "src/vs/workbench/services/extensions/, src/vs/workbench/api/common/extHost.protocol.ts"
upstream_issue: ""
tags: [extensions, wasm, sandboxing, security]
---

VS Code's hard architectural guarantee — extension code never runs in the workbench's own
process/thread — has no ready-made Jac equivalent. Jac's native+WASM compilation path
(`jac-native-wasm.md`) provides a compile *target* (a Jac module can become `.wasm`) but not a
plugin *sandbox*: no built-in capability/permission model for running untrusted third-party code,
no equivalent of VS Code's `extHost`/`mainThread` process-boundary split. Confirmed independently
by both the docs research and the examples research — no skill file and no example app
demonstrates anything like a plugin sandbox.

**Impact on jac-studio**: this is the single biggest open R&D risk in the whole project, larger
than the text-editor core. It gates the entire third-party extension ecosystem story.

**Plan**: per `architecture.md`'s phased trust model, defer this entirely to Phase 6 and treat it
as its own research track — do not let it block Phases 1–5, and do not attempt it before the
extension-API surface (Phases 4–5) has been validated against real usage. Likely approach: build a
capability/permission layer on top of the raw WASM ABI ourselves. Revisit this entry once Phase 6
research actually begins; until then it's a known, accepted, load-bearing gap.
