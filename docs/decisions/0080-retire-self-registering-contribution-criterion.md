# 0080 — Retire the self-registering-contribution exit criterion

- **Date**: 2026-09-27
- **Status**: accepted

## Decision

The M4 exit criterion "a fourth built-in feature can be added purely by writing a new contributing
module, with zero changes to existing workbench code" is retired. The centralized list
([0052](0052-contribution-registry-is-a-centralized-list.md)) is the deliberate, permanent
contribution mechanism for first-party features. Genuine self-registration is deferred to M12,
built against a real third-party manifest/extension consumer, not built speculatively now.

## Why

No extension can load at runtime today — M12 ("Extensions: dynamic loading") hasn't started, so
there is no consumer that needs a command/view to self-register. Building the graph-contribution
model `architecture.md` originally sketched, ahead of that consumer, is exactly the premature
abstraction this codebase's own working agreement rules out (`CLAUDE.md`: "Don't add features...
beyond what the task requires"). 0052 already found the centralized list "genuinely low-friction"
for every first-party feature added in Phase 4.

## Consequences

- `command_registry.jac`'s `BUILTIN_COMMANDS` and `activity_bar.jac`'s `VIEWS` stay hardcoded lists;
  a new first-party feature keeps editing them plus one wiring line in `workbench.jac`, same as
  today.
- M12 designs self-registration against a real manifest format and a real loader, informed by
  what that extension system actually needs — not against this now-retired criterion.
- `architecture.md`'s "Extension nodes Contribute Command/View/Menu nodes" language describes a
  future M12 design, not current or planned-before-M12 code; 0052 already flagged this.
