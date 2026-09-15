# 0021 — Set `keepCurrentModel` so a shared Monaco model survives a tab close

- **Date**: 2026-08-25
- **Status**: accepted

## Decision

`monaco_editor.jac` passes `keepCurrentModel={True}`. A closed tab's model is then never
explicitly disposed — an accepted leak.

## Why

`@monaco-editor/react`'s `path` prop shares one underlying text model across every `<Editor>`
mounted with the same path (`monaco.editor.getModel(uri) || createModel(...)`, confirmed by
reading the package's source) — which is exactly what makes editor-group splitting work. But its
*default* unmount behavior disposes that shared model (`keepCurrentModel` defaults to `false`,
assuming 1:1 ownership), so closing the tab in one group blanked the other group's still-mounted
editor. Reproduced live, not hypothetical.

## Consequences

Accepts unreclaimed models for the same reason orphaned `Folder`/`File` nodes are accepted: a
local, single-user dev tool, not a long-running service. Do not "fix the leak" by dropping the
prop. `DiffEditor` does **not** share this prop name — see 0036, where assuming it did crashed.
