---
id: 2026-10-07-client-runtime-lacks-str-isupper
date: 2026-10-07
category: missing-feature
severity: minor
status: open
phase: 11
subsystem: tooling
jac_version: "0.37.24 (jaseci main @033579290, dev build)"
related_vscode_ref: ""
upstream_issue: ""
tags: [client, jac2js, str-methods, test-modes]
---

`str.isupper()` works in server Python but not in client code compiled by jac2js: it throws
`AttributeError: 'str' object has no attribute 'isupper'` at runtime. `jac check` accepts it. Worse,
the failure depends on how the module is run: `jac test <module>.jac` executes a pure module as
Python and passes, while `jac test src` runs the same module as JS (because it is pinned `client` in
`jac.toml`) and fails, so a green single-file run hides a real client bug.

Repro: a client-pinned module with `def f(ch: str) -> bool { return ch.isupper(); }` and a test
calling `f("A")`; passes alone, fails in the project-wide run. Seen while writing a camelCase-to-title
helper for the settings editor.

**Plan**: Not filed upstream. The workaround is the correct practice either way (compare `ch.lower()
!= ch`, and always run the whole suite, not just the new file, for client-pinned modules), recorded
in `.claude/skills/jac-language/references/gotchas.md`. Worth an upstream issue to either implement
the missing `str` methods in the client runtime or make `jac check` flag them; I have not checked
which other `str` methods are missing.
