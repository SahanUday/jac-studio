---
id: 2026-08-22-npm-interop-server-only-blocked
date: 2026-08-22
category: compiler-bug
severity: major
status: resolved
phase: 0
subsystem: translator
jac_version: "0.36.1 (jac dev build)"
related_vscode_ref: ""
upstream_issue: ""
tags: [npm-interop, placement, codespaces, translator, spike]
---

Phase 0 spike (per `translator-strategy.md`'s "Language: Jac-first" section): can a plain
CLI-kind Jac module (no browser, no JSX) import an arbitrary npm package — specifically the
`typescript` package, for AST-based extraction — and call it in server/native code? **No.**
Confirmed empirically, not just inferred from docs.

**Repro**: `jac create --kind cli`, `jac install --npm typescript`, then a module with
`import from "typescript" { createSourceFile, ScriptTarget }` called from a plain `def:pub`
function and a `with entry` block.

- Without a placement pin: `jac check --placements` shows the npm import, the function, and even
  the `with entry` block itself all seeded/pulled to **client** placement (0 server, 3 client) —
  because per `jac-codespaces.md`'s evidence rules, "string-path or `@jac` npm imports... are
  client evidence." Since the `cli` project kind has no client codespace/browser runtime at all,
  `jac run` silently does nothing — it compiles clean but the entry point isn't there to execute.
- With `[placement.pins]` forcing `"server"`: the pin does force placement bookkeeping to server
  (3 server, 0 client), but `jac run` then fails hard: `error[E5001]: String literal imports are
  only supported in client (cl) imports, not Python imports.` This is a categorical compiler
  restriction, not a soft default — no pin can route an npm package to server/native code.

**Also notable**: `jac install --npm typescript` unconditionally provisioned a full React/Vite
client toolchain (react, react-dom, react-router-dom, vite, @vitejs/plugin-react, zod,
@tanstack/react-form — 85 packages) even in a `cli`-kind project declaring no client codespace.
The npm dependency system isn't decoupled from the client-bundling pipeline architecturally,
independent of the E5001 restriction above.

**Impact on jac-studio**: settles `translator-strategy.md`'s open question. Extraction (parsing TS
source via the TypeScript compiler API) cannot be done in Jac via npm interop, in any project
kind that has a server/native/CLI target. The Node-subprocess fallback described in that doc as a
contingency is now the confirmed, necessary plan for extraction specifically — not a maybe.

**Plan**: update `translator-strategy.md`'s extraction step to state this as settled rather than
open. No further investigation needed here — clean, reproducible, well-understood failure mode
(E5001), not a bug to report upstream (this restriction is clearly deliberate architecture, not an
oversight — client/server isolation is presumably a real security/bundling boundary, not
negotiable). `status: resolved` since the question this spike asked has a definitive answer, even
though the answer wasn't the one we'd hoped for.
