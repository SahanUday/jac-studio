---
id: 2026-08-25-root-test-sweep-crosses-internal-subproject-boundary
date: 2026-08-25
category: ergonomics
severity: minor
status: workaround
phase: 2
subsystem: tooling
jac_version: "0.36.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac-test, cli, internal-subproject, discovery]
---

## What we tried

After archiving the native editor engine to `internal/native-editor-archive/` (its own
self-contained project: own `jac.toml`, own `[test] directory = "src"`, own colocated
`.test.jac`-named files, the same annex convention the live `src/editor/` tree already used), ran
this project's standard root-level verification command, `jac test .`, expecting it to keep
scoping to the root `jac.toml`'s own `[test] directory = "src"` the way it always had.

## What happened

```
ModuleNotFoundError: No module named 'src.editor.core'
  File ".../internal/native-editor-archive/src/editor/model/text_model_search.jac", line 37
    import from src.editor.core.range { Range }
```

`jac test .`, given an explicit path argument, recursively discovers every `.test.jac` file under
that path -- including ones inside a completely separate nested project with its own `jac.toml` --
and tries to import them using the *root* project's module resolution, not the nested project's
own. `src.editor.core.range` only resolves relative to the archive's own `src/`, not the root's
(which no longer has `src/editor/core/` at all after the move), so the import fails.

Confirmed the `[test] directory = "src"` config is not actually ignored -- it's specifically the
explicit `.` path argument that bypasses it: `jac test` (bare, no path) and `jac test src` (the
configured directory named explicitly) both correctly scope to just `src/` and never touch
`internal/` (12 passed, matching `document_service.test.jac` + `workspace_service.test.jac`'s
combined count). Only `jac test .` triggers the wider sweep.

This also retroactively explains a pre-existing project convention rather than introducing a new
one: `internal/workspace-graph-spike/` and `internal/service-registry-spike/` both use
`tests/*_tests.jac` (a standalone-test naming/location, needing an explicit import of the module
under test) instead of colocated `.test.jac` annexes -- which happens to be exactly the naming
pattern that never gets swept up by a root-level `jac test .`. That convention already existed
before this was understood to be *why* it mattered here.

## Plan

Workaround, not requesting an upstream fix yet -- the behavior is plausibly intentional (an
explicit path argument doing a full recursive walk is a defensible reading of "test this path"),
and the fix is cheap and now documented: use `jac test` or `jac test src` from the jac-studio
project root, never `jac test .`, for as long as anything under `internal/` carries a `.test.jac`
file. Logged so this doesn't have to be rediscovered the next time an `internal/` subtree grows
one -- see the `jac-language` skill's gotcha list for the operational note.
