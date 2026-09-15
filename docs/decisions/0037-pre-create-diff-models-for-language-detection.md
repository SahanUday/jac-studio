# 0037 — Pre-create both diff sides' models so a cold diff keeps its language

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

`monaco_diff_editor.jac`'s `handle_before_mount` creates both sides' models itself, with the
empty-string language spelling, before `DiffEditor`'s own resolution runs — so its internal
`getModel(uri)` check finds a correctly-tagged model.

## Why

**CORRECTION** to the earlier claim that per-side language detection from
`originalModelPath`/`modifiedModelPath` was free: that was only ever checked against a diff where
one side already had a model from an open regular tab. Verified cold (neither file open
elsewhere), `DiffEditor` falls back to a literal language string `"text"` for any side it must
create a model for — its internal `modifiedLanguage||language||"text"`, not the empty-string
auto-detect fallback the plain `Editor` uses in the same spot — so a cold-diffed file renders as
`plaintext` regardless of extension.

## Consequences

A capability confirmed on one code path is not confirmed in general; the "free" claim held only
for the warm case that happened to be tested. File:line citations into `@monaco-editor/react`'s
source are in the module's docstring. Do not remove the pre-creation as redundant setup.
