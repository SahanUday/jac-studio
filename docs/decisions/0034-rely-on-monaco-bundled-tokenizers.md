# 0034 — Rely on Monaco's bundled tokenizers for common languages

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

Take syntax highlighting for Python, JavaScript, CSS, JSON and Markdown from `monaco-editor`'s
own bundled language services. Drop the earlier plan to reach a TextMate tokenizer through
Python/npm interop for those languages.

## Why

Confirmed live rather than assumed free: `jac browse` plus `monaco.editor.colorize` and
`monaco.editor.tokenize` produced real multi-class token output, not just a language-id label
with no visible effect.

## Consequences

Removes an interop research question from the roadmap. It does **not** cover this project's own
dominant file type — `monaco.languages.getLanguages()` includes neither `jac` nor `toml` (0035) —
and it does not extend to the diff editor's cold path (0037).
