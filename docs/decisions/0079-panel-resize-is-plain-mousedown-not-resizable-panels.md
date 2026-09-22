# 0079 — Bottom panel resize is a plain mousedown drag, not `react-resizable-panels`

- **Date**: 2026-09-22
- **Status**: accepted

## Decision

The bottom panel's (terminal/output/problems/debug) height drag uses plain
mousedown/mousemove/mouseup DOM events and a `has bottom_panel_height` field, not the
`react-resizable-panels` library already used for the sidebar and editor-group splits.

## Why

The bottom panel's four content views are already independently toggled via `display:none` CSS
(the established mount-once, hide-via-CSS pattern every panel in this codebase uses, so state
isn't lost on switch). Folding panel-open/closed into `react-resizable-panels`' own collapse/expand
state would mean two competing visibility mechanisms on the same element; the plain DOM-event
approach composes with the existing CSS-toggle pattern instead of fighting it.

## Consequences

Sidebar/editor splits and the bottom panel now use two different resize mechanisms. Any future
resizable region should default to `react-resizable-panels` (already proven) unless it has this
same conflict with the mount-once/CSS-toggle convention.
