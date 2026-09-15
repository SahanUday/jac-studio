# 0067 — Reuse proven libraries for solved problems

- **Date**: 2026-09-15
- **Status**: accepted; supersedes [0011](0011-jac-first-tooling-with-named-exceptions.md). [0001](0001-rewrite-dont-mirror.md) still stands.

## Decision

A problem commercial editors have already solved gets a proven library, wrapped thinly in Jac.
Jac-native work is reserved for architecture, Jac-specific workflows and the AI layer. Adopting a
library means writing `docs/libraries/<name>.md` when it is wired in.

## Why

The original stance was "everything in Jac unless genuinely blocked." Building the editor core
natively worked ([0018](0018-editor-core-continues-native.md)) and was still the wrong trade — it
was reversed for real Monaco ([0020](0020-editor-engine-is-real-monaco.md)), and the effort it
consumed wasn't going into what differentiates the product. The goal is VS Code's capability and
UX, AI-first; re-deriving solved components delays that without adding value.

## Consequences

- Decision order for a component: reuse a library → redesign around a Jac primitive → translate →
  build fresh.
- Library choice stops at libraries: frameworks that own the whole shell (Eclipse Theia) are
  rejected, since jac-studio would stop being a Jac application. See `docs/technology-choices.md`.
- Real Jac limitations still go to the challenge tracker; convenience alone is not a limitation.
