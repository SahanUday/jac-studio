# 0016 — Merge circularly-importing modules instead of mirroring the TS file split

- **Date**: 2026-08-23
- **Status**: accepted

## Decision

When a translated module's upstream file split would produce a circular Jac import, merge the
files. `rbTreeBase.ts` landed inside `piece_tree_base.jac` rather than as its own module.

## Why

Circular Jac-file imports silently degrade native compilation: `jac check` passes with only a
warning, but a `Type is Unknown` note shows the compiler falling back to
interpreted/server-codespace compilation for the affected declarations — confirmed with a minimal
repro, logged as `2026-08-23-circular-import-degrades-native-lowering` (still open). The TS split
was an ES-module convenience, not inherent to the algorithm.

## Consequences

Translator manifest entries may legitimately not map 1:1 onto upstream files. A clean-up pass
that "restores the original module boundaries" would silently lose native lowering again, with no
test failure to show for it.
