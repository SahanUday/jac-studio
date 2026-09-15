# 0005 — Compose the workbench from shadcn-in-Jac primitives

- **Date**: 2026-08-22
- **Status**: accepted

## Decision

Build the workbench shell by composing the existing shadcn-in-Jac primitive set (`Sidebar`,
`Resizable`, `Tabs`, `Command`, `ContextMenu`, `Tooltip`, `ScrollArea`) rather than hand-rolling
a UI toolkit, and follow VS Code's self-registering contribution model per feature.

## Why

Upstream's 1.42M-line `workbench` layer is where Jac's built-in component library does the most
work for us relative to upstream's line count; most workbench parts map almost directly onto an
existing primitive.

## Consequences

The workbench phase is a composition/layout effort, not toolkit-building — for the *majority* of
parts. Real exceptions exist and must be hand-built: the file tree, the activity bar (0040), the
title bar, and notifications. The "self-registering" half of this decision was not what actually
got built; see 0052 before assuming the contribution model is real.
