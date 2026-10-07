---
id: 2026-10-07-jac-check-accepts-unexported-glob-import-client-build-rejects
date: 2026-10-07
category: ergonomics
severity: minor
status: open
phase: 11
subsystem: tooling
jac_version: "0.37.24 (jaseci main @033579290, dev build)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac-check, client-build, glob, e7005]
---

A bare `glob X` in one module imported by another (`import from a.b { X }`) passes `jac check` and
`jac test`, and only fails when the client bundle is built: `E7005: ... runtime import(s) X are not
exported by ...; only exposed declarations (:protect or :pub) ... cross into the bundle`. The dev
server then exits during startup, so the mistake surfaces only at the first live run. Hit twice in
one sitting (`THEME_NAME`, then `MENUS` and `EDITOR_COMMANDS`).

Repro: module `a.jac` with `glob X: int = 1;`, client module `b.jac` with `import from a { X }` and
a component that reads `X`; `jac check` is clean, `jac run --dev` dies with E7005.

**Plan**: Not yet filed upstream; the natural fix is for `jac check` to report the same
not-exported diagnostic the client build already computes, since the information is available
statically. Until then the workaround is the correct practice regardless (write `glob:pub` for
anything another module imports), recorded as a gotcha in
`.claude/skills/jac-language/references/gotchas.md`. File upstream with a minimal two-file repro if
it recurs or if the team wants it tracked.
