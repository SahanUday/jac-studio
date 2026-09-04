---
id: 2026-09-04-auto-mode-repointed-to-bypasspermissions
date: 2026-09-04
category: resolved
severity: note
status: resolved
phase: 5
subsystem: extensions
jac_version: "0.37.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [ai-chat, claude-agent-sdk, claude-code-integration, permission-mode, real-user-qa, product-decision]
---

## What happened

Follow-on to `2026-09-04-auto-mode-fast-path-not-observed-in-headless-sdk-invocation` (closed
earlier the same day): once it was confirmed live that `"auto"` mode's classifier fast-path is
inert in the currently-bundled CLI -- meaning `"auto"` behaves identically to `"default"`/Manual in
this app right now -- the user, told this plainly, asked for what they actually wanted instead of
a technically-faithful but practically-useless "Auto" option: give the agent a complete instruction
and let it run end to end, only interrupting the user for a genuine clarifying question (ordinary
chat text, not a permission gate), rather than a prompt on every tool call.

## Decision

`ai_chat.jac`'s `PERMISSION_MODE_OPTIONS` "Auto" entry now sends `"bypassPermissions"` instead of
`"auto"` -- the real SDK mode that unconditionally skips every tool-approval check (confirmed live
in the sibling entry's own probe: 0 `can_use_tool` invocations). Re-verified specifically for this
decision with a fresh isolated probe combining a file write *and* a Bash command in one turn: both
ran with zero approval interruptions, matching the requested behavior exactly.

**Flagged explicitly to the user before shipping, and confirmed, not assumed**: this is a
materially bigger trust step than `"acceptEdits"` (which only covers file writes) --
`"bypassPermissions"` also skips Bash and every MCP tool call, with no per-call check of any kind.
The user was told this in plain terms and explicitly opted in.

This is a different, later decision than the two same-day corrections in
`2026-09-04-auto-permission-mode-silently-behaved-like-manual` -- those were about getting the
*value's own semantics* right (what does `"auto"` actually mean); this one is a deliberate product
choice made *after* that was fully resolved, trading label-fidelity to the real extension's Auto
mode (which this app can't currently deliver anyway) for an option that actually does something
useful today.

## Plan

No further action needed -- this is the correct, permanent choice given the current constraint
(`2026-09-04-auto-mode-fast-path-not-observed-in-headless-sdk-invocation`'s own finding). If a
future `claude-agent-sdk` release bundles a CLI build where `"auto"`'s classifier fast-path is
active, worth revisiting whether the real, classifier-mediated `"auto"` becomes preferable to the
current blunt full-bypass -- a UI decision to make at that point, not now.
