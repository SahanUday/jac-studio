# 0027 — Build the keybinding "when clause" context system up front, in Phase 2

- **Date**: 2026-08-25
- **Status**: accepted

## Decision

Ship a context-evaluation layer on top of the command registry in the workbench-shell MVP: a
capture-phase `document` keydown listener matches a combo against each `Command`'s
`{"key", "when"}` pairs and evaluates a single optionally-`!`-negated context-key name against a
flat `context: dict[str, bool]` populated by leaf components.

## Why

Cheap to build before anything depends on it, expensive to retrofit once multiple features want
the same key. Demonstrated with a real, not contrived, case: `Escape` closes the terminal only
when it has focus.

## Consequences

Scoped keybindings are available to every later feature by default. The evaluator is deliberately
minimal (one negatable key, not upstream's full expression grammar) — extending it is expected
work, but the ownership shape (leaf components report context, `workbench.jac` owns the dict) is
the established pattern. Note this mechanism governs *workbench* keybindings; Monaco's own
per-editor keybinding routing is separately broken (0059).
