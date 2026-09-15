# 0073 — Route the sidebar width override through `style`, not `className`

- **Date**: 2026-09-15
- **Status**: accepted

## Decision

The sidebar's width override is passed via the `style` prop, not `className`.

## Why

Dragging the sidebar wider than its content showed real white space instead of the dark theme —
shadcn's `Sidebar` primitive hardcodes a 16rem width regardless of its resizable container. A first
fix added a width override via `className="w-full min-w-0"`, but the primitive's own
`collapsible="none"` branch spreads all incoming props (including `className`) *after* its own
computed className, and a JSX prop specified twice keeps the last one — silently discarding the
primitive's own `bg-sidebar`/`text-sidebar-foreground` classes along with the width fix, causing a
second, different near-invisible-text bug. `style` isn't subject to the same prop-spread clobbering.

## Consequences

Any future override of a shadcn primitive's own Tailwind classes on a component that spreads props
after computing its className should default to `style`, not `className`, unless the primitive's
prop-merging behavior for that specific slot is checked first.
