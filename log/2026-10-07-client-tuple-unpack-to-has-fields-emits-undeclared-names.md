---
id: 2026-10-07-client-tuple-unpack-to-has-fields-emits-undeclared-names
date: 2026-10-07
category: compiler-bug
severity: major
status: upstream-tracked
phase: 11
subsystem: workbench-shell
jac_version: "0.37.24 (jaseci main @033579290, dev build)"
related_vscode_ref: ""
upstream_issue: "jaseci-labs/jac#9856"
tags: [jac2js, client, has-state, tuple-unpack, session-restore]
---

In a client component, `(a, b) = f();` where `a` and `b` are `has` fields compiles to the plain JS
`[a, b] = f();` over names that are never declared (the state lives in `__jacS_<name>` cells), so it
throws `ReferenceError` at runtime. A single-field assignment is lowered correctly. `jac check` and
`jac test` never see it.

It had silently broken session restore since the tuple form was introduced in `workbench.jac`'s
entry ability: the throw aborted the rest of the ability on every page load, so saved tabs were
never restored. Found by a `cursor_positions is not defined` console error and confirmed in the
compiled `workbench.js`. Repro: a 15-line component with two `has` fields; `jac tool ir es repro.jac`
shows both shapes (full repro in the upstream issue).

Cause: `EsastGenPass.exit_assignment` only emits a state setter for a single `uni.Name` target; a
`TupleVal`/`ListVal` target falls through to the generic `ArrayPattern` path.

**Plan**: Filed upstream ([jaseci-labs/jac#9856](https://github.com/jaseci-labs/jac/issues/9856))
with the root cause and a fix: when every target is a reactive field, bind the right-hand side once
and call each setter. The fix and two regression tests (red without it, green with it; the 291-test
ES backend directory passes) sit on the local jaseci branch `fix/client-tuple-unpack-state`
(65fff7666). jac-studio's `workbench.jac` keeps its tuple form and is validated against
that patched compiler; no source rewrite was used. Mixed reactive/local targets and star targets
are not covered by the patch. Once a release ships the fix, the patched compiler is no longer needed.
