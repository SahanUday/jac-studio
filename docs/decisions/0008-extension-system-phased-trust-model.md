# 0008 — Extension system: phased trust model A → B → C

- **Date**: 2026-08-22
- **Status**: accepted

## Decision

Phase A: "extensions" are trusted, in-process Jac modules loaded at build time. Phase B: separate
packages with a manifest, loaded dynamically, still trusted. Phase C: real sandboxing of
untrusted code, likely via Jac's native+WASM path. Do not start C before A and B have validated
the contribution-registry and API surface against real usage.

## Why

VS Code's hard guarantee — extension code never runs in the workbench's own process — has no
ready-made Jac equivalent; confirmed independently by the docs and examples research (no skill
file, no example app demonstrates a plugin sandbox). Phase C is R&D, not integration work.

## Consequences

Sandboxing a design that later turns out wrong would waste the hardest work in the project. This
is the technical phasing only — 0044 later reordered which milestone we drive toward without
changing it. Phase C should be scoped as its own multi-milestone research track, never a line
item inside another phase.
