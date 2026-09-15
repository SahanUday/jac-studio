# 0036 — `DiffEditor` needs `keepCurrentOriginalModel`/`keepCurrentModifiedModel`

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

`monaco_diff_editor.jac` sets both `keepCurrentOriginalModel` and `keepCurrentModifiedModel`
(both default `false`, both needed). `keepCurrentModel` is not a `DiffEditor` prop at all.

## Why

`DiffEditor` reuses an open tab's existing shared model via the same
`getModel(uri) || createModel(...)` sharing 0021 describes — but the disposal-avoidance fix does
not carry over by name. Passing the plain `Editor`'s `keepCurrentModel` compiles and runs with
zero warning, silently ignored, and closing a diff tab disposed a model a regular tab was still
rendering: `Uncaught Error: TextModel got disposed before DiffEditorWidget model got reset`,
reproduced live before the fix. The real pair was found by reading the package's own source.

## Consequences

Props that look like they should be shared across `@monaco-editor/react`'s components are not,
and the failure mode is silence, not a warning. Read the package source rather than trusting the
docs or symmetry — the same discipline found 0037 and 0038.
