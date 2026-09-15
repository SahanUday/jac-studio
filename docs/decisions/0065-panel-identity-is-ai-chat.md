# 0065 — The panel's identity is "AI Chat", with the provider as a caption

- **Date**: 2026-09-05
- **Status**: accepted

## Decision

"AI Chat" is the headline across the sidebar header, approval card, code-action menu items and
inline chat, with a small "via Claude Code" caption. Deliberately not a full provider-selector UI.

## Why

From the sponsor's own first hands-on QA pass after closure. Naming the surface after one vendor
bakes today's single integration into the product's identity, while only one real provider exists
to select between — a selector would be UI for a choice nobody can make yet.

## Consequences

Adding a second provider (0062) becomes a caption and a selector, not a rename of every surface.
See `ai_chat.jac`'s docstring for the reasoning. Related QA-round decisions kept alongside it: the
sidebar is resizable, and maximizing AI Chat is a CSS overlay on the *same mounted instance*
(0066).
