---
id: 2026-08-24-test-annex-self-import-breaks-unrelated-runs
date: 2026-08-24
category: compiler-bug
severity: minor
status: workaround
phase: 2
subsystem: tooling
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [testing, imports, circular-import, annex]
---

## What we tried

Writing `src/workbench/workspace/workspace_service.test.jac` as the colocated test annex for
`workspace_service.jac`, following the same shape as every other test file in the project
(`document_service.test.jac`, `interval_tree.test.jac`, etc.) -- except this one started with an
explicit `import from src.workbench.workspace.workspace_service { open_workspace,
list_children_by_path, _reset_workspace_cache_for_tests }` at the top, by habit carried over from
`internal/workspace-graph-spike/tests/workspace_graph_tests.jac` (a *standalone* test file in a
separate `tests/` directory, which genuinely does need that import).

## What happened

`jac test src/workbench/workspace/workspace_service.test.jac` failed immediately:

```
ImportError: cannot import name 'open_workspace' from partially initialized module
'src.workbench.workspace.workspace_service' (most likely due to a circular import)
```

Worse: this wasn't scoped to running the test. A completely unrelated ad hoc script
(`jac run /tmp/probe.jac`, which only did `import from src.workbench.workspace.workspace_service
{ open_workspace }` and called it -- no test runner involved at all) *also* failed with the exact
same error, purely because the bad annex file existed on disk elsewhere in the project. Bisected
by copying the whole project to a scratch directory and deleting files one at a time: removing
every other file (`src/editor/`, `docs/`, `components/`, `styles/`, `lib/`, even `.claude/`) still
reproduced it; the failure disappeared the instant `workspace_service.test.jac`'s `import from`
line was removed (making it a bare annex with no import, matching every other `.test.jac` in the
project) -- confirmed present with the import in place, confirmed gone the moment it was removed,
with no other change.

This is already indirectly documented -- `jac-studio-translator`'s SKILL.md says "An annex sees
the base module's declarations without importing them; importing them anyway causes a
circular-import error at test time" -- but that undersells the blast radius: it isn't scoped to
"at test time" for that one file, it can break *other, unrelated* invocations elsewhere in the
same project for as long as the bad file sits on disk.

## Plan

Not filing upstream yet -- the fix is simple and already known (drop the import, the annex sees
module scope directly), and the mechanism has a plausible mundane explanation (some eager
project-wide module scan, likely for the RPC route table, imports the annex file and the real
module in an order that races the annex's own duplicate import). Worth a minimal repro upstream if
this pattern shows up again with a less obvious trigger. For this project: strengthened
`jac-language`'s gotcha list with the wider blast-radius warning (not just "wrong at test time"),
since the failure mode you actually see (an unrelated script breaking) points nowhere near the
real cause (a stray import in a test annex you may not even be running).
