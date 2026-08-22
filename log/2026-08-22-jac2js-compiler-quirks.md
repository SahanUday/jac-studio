---
id: 2026-08-22-jac2js-compiler-quirks
date: 2026-08-22
category: compiler-bug
severity: minor
status: open
phase: 1
subsystem: tooling
jac_version: "unspecified — see jac-cl-js-interop.md, jac-cl-components.md"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac2js, client-compiler, ergonomics]
---

The `jac2js` client compiler is documented (not just anecdotally known) to have several
miscompilation classes, catalogued across `jac-cl-js-interop.md` and `jac-cl-components.md`:
`let`-scoping/TDZ bugs, string-literal newline escaping issues, `sorted(key=lambda)` rejected
client-side even though it's valid Jac, `asChild`/ref-forwarding silently producing no-ops, and
`jac check` false positives on code that is "correct at runtime." This is a lot of documented
compiler-quirk surface area for a framework whose whole pitch is Python-like ergonomics.

**Impact on jac-studio**: every client component we write (which, given the workbench-shell plan
in `architecture.md`, is most of the visible app) is exposed to this surface area. Not a blocker
for any single phase, but a steady tax on velocity throughout Phases 2–5.

**Plan**: treat the documented gotcha lists in those two skill files as a checklist during code
review of client components, not just a "known issue, move on." Log a dedicated entry per new
miscompilation actually hit during jac-studio development (with a minimal repro), rather than
lumping everything into this one general entry — this entry exists to record that the *category*
of risk was known going in, from documentation alone, before any jac-studio code was written.
