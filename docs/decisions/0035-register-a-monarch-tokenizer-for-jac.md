# 0035 — Register a deliberately-scoped Monarch tokenizer for `.jac`

- **Date**: 2026-08-28
- **Status**: accepted

## Decision

`src/editor/client/jac_language.jac` registers a Jac language with Monaco
(`register`/`setMonarchTokensProvider`/`setLanguageConfiguration`, associated with `.jac`),
covering keywords, `#` comments, single/double/triple-quoted strings, backtick-escaped
identifiers, `->` and `::`. Registered via `beforeMount` (confirmed from the package's source to
run before model creation), guarded by a module-level flag against re-registration. `.toml` is
left as `plaintext`.

## Why

Monaco has no idea what a `.jac` extension is, so every `.jac` file — including jac-studio's own
source — resolved to `plaintext`. For "VS Code reimplemented in Jac", that left the flagship
highlighting feature invisible for exactly the files its users open most.

## Consequences

Explicitly not a claim of full grammar fidelity — it covers what `jac-core-cheatsheet` and this
project's own files actually use. The published `jaseci-labs.jaclang-extension` ships a 4,937-line
TextMate grammar that is genuinely richer; this stays the working baseline until the deferred
`.vsix` question (0046) is ever answered. `.toml` was judged not worth the same investment.
