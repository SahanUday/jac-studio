# 0020 — The editor engine is the real `monaco-editor` npm package

- **Date**: 2026-08-25
- **Status**: accepted

## Decision

Embed the real `monaco-editor` npm package via a thin Jac client wrapper
(`src/editor/client/monaco_editor.jac`) as v1's editor engine, reversing 0018. Archive the
from-scratch engine at `internal/native-editor-archive/` (`git mv`'d, history intact).

## Why

A reuse-over-reinvention call, recorded as `2026-08-25-editor-core-decision-reversed-to-monaco`.
Once `monaco-editor` is an ordinary npm dependency, maintaining a second competing engine has no
v1 payoff: Monaco already owns the text model, cursor/selection/IME, virtualized rendering,
undo/redo, and a bundled tokenizer/language layer making syntax highlighting and the diff editor
largely free (0034, 0036).

## Consequences

jac-studio now owns only the mounting/lifecycle wrapper, load/save at the document boundary (no
per-keystroke RPC), and the surrounding workbench state. Embedding a third-party imperative
library from a Jac `app` component is a new pattern to validate, not assume. A licensing
constraint or desktop story could revive the archive — that option was kept deliberately.
