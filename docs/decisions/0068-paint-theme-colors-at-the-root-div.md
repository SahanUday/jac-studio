# 0068 — Paint background/color from CSS vars at the one root div

- **Date**: 2026-09-04
- **Status**: accepted

## Decision

The root `<div className={theme}>` in `main.jac` sets `style={{"background": "var(--background)",
"color": "var(--foreground)", "height": "100vh"}}` directly, in addition to carrying the
`dark`/`light` class.

## Why

`.dark`/`.light` set `--background`/`--foreground` as CSS custom properties, which cascade — but
neither is an inherited *rendering* property, so nothing actually painted them anywhere by default.
Every dark surface before this fix was a component hand-setting its own hex color; any gap between
components fell through to `<body>`'s still-light background. Real-user QA found two live instances
(the sidebar's `ResizablePanel`, and a ~25px white band at an editor group split, confirmed via
`getComputedStyle`/`elementsFromPoint`, not guessed).

## Consequences

Fixes the whole bug class at its source instead of patching each container as a white gap is found.
Any new top-level container still needs its own background if it sits outside this div's normal
paint order (e.g. a portal), but the common case — a plain descendant with no explicit background —
is now safe by default.
