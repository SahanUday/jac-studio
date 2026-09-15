# 0052 — The contribution registry is a centralized list, not self-registration

- **Date**: 2026-09-02
- **Status**: accepted

## Decision

Record what was actually built, against what 0005 described: `command_registry.jac`'s
`BUILTIN_COMMANDS` and `activity_bar.jac`'s `VIEWS` are each a single, centralized, hardcoded
list. Every feature added in Phase 4 (search, SCM, tasks, outline, debug console) required editing
that shared list plus a wiring line in `workbench.jac`.

## Why

The roadmap's exit criterion — "a fourth built-in feature can be added purely by writing a new
contributing module, with zero changes to existing workbench code" — was **not** achieved as
literally worded. The pattern is genuinely low-friction for first-party features (`outline.jac`'s
own docstring calls it "a one-entry addition... no new plumbing", and that held every time), but
it is not the self-registering graph contribution `architecture.md` describes.

## Consequences

A manifest-driven, runtime-loaded extension cannot contribute a command or view without a
maintainer hand-editing these files — so this must be resolved, or explicitly re-scoped as the
deliberate permanent choice for first-party features, **before** Phase 6 starts. Do not read
architecture docs describing "Extension nodes Contribute Command/View/Menu nodes" as a
description of existing code.
