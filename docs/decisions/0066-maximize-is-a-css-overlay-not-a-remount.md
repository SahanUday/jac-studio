# 0066 — Maximizing AI Chat is a CSS overlay on the same mounted instance

- **Date**: 2026-09-05
- **Status**: accepted

## Decision

The "maximize" toggle expands the already-mounted AI Chat component to fill the workbench area
via CSS. It is not a second mount point, a real tab, or a portal.

## Why

A real tab or portal would unmount and remount the component — losing the live conversation,
which is client-held state with nothing to restore it from.

## Consequences

Any future re-homing of this panel (a real editor tab, an auxiliary bar, a detached window) must
preserve the single mount, or first give the conversation somewhere durable to live. The same
constraint applies to the inline chat popover's independent session (0058).
