# 0032 — Match VS Code's default visual identity natively (Dark+/Light+)

- **Date**: 2026-08-28
- **Status**: superseded by [0033](0033-target-dark-2026-and-real-codicons.md)

## Decision

jac-studio should look like VS Code out of the box — the zero-extensions vscode.dev experience —
not shadcn's own aesthetic. Reach it by deriving VS Code's Dark+/Light+ colors into `jac
retheme`'s own OKLCH tokens and swapping to Codicons-style iconography, not by importing VS
Code's theme JSON format or building a compatibility shim.

## Why

Principle-1 consistency (0001): the baseline look is achievable with the theming machinery that
already styles every shadcn-in-Jac primitive; only the token values are missing.

## Consequences

Superseded on one factual point only — "Dark+/Light+" was not VS Code's current default (0033).
The native-tokens-not-a-shim stance carries forward unchanged, and is deliberately separate from
the still-open question of whether jac-studio ever installs third-party `.vsix` theme extensions.
Monaco's own `vs-dark`/`vs-light` already match upstream's editor colors; this decision is about
the chrome around Monaco.
