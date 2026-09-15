# 0077 — Inline chat uses fixed model/permission-mode/effort, not a second picker set

- **Date**: 2026-09-15
- **Status**: accepted

## Decision

`inline_chat_widget.jac`'s popover sends fixed `model`/`permission_mode`/`effort` values —
`permission_mode="default"` specifically — rather than exposing the same pickers `ai_chat.jac`'s
sidebar has. It also has no file-attachment picker.

## Why

This popover is deliberately the fast, minimal "just make the edit" surface. A second full toolbar
of dropdowns would work against that. More importantly, `permission_mode="default"` keeps this
widget's own approval cards live — `"acceptEdits"`/`"auto"`/`"bypassPermissions"` would skip
`can_use_tool` for most of what an inline edit does (Edit/Write), leaving that UI silently unused
and the edit unreviewed. No attachment picker either: the selection this widget already inlines
into every prompt covers the one piece of context an inline edit needs.

## Consequences

A compact/minimal AI surface should default to the safest permission mode, not inherit whatever the
primary surface's picker last had selected — sending a fixed, safe value is the correct default
for any future minimal entry point, not an oversight to eventually "fix" by adding pickers.
