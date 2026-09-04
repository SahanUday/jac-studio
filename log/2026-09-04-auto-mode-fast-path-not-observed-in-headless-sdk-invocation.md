---
id: 2026-09-04-auto-mode-fast-path-not-observed-in-headless-sdk-invocation
date: 2026-09-04
category: missing-feature
severity: minor
status: open
phase: 5
subsystem: extensions
jac_version: "0.37.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [ai-chat, claude-agent-sdk, claude-code-integration, permission-mode, real-user-qa, open-question]
---

## What happened

Spun out of `2026-09-04-auto-permission-mode-silently-behaved-like-manual`'s correction (see that
entry for the full "auto" mode investigation). While confirming `permission_mode="auto"` is a real,
classifier-backed auto-approval mode (not equivalent to Manual), the live test that originally
surfaced the whole investigation still showed this app's own `can_use_tool` callback
(`claude_code_launcher.py`'s `_can_use_tool`) being invoked for a plain `Write` tool call under
`"auto"` mode -- a real approval card appeared and had to be explicitly allowed.

Per the real `claude` CLI's own enforcement code (`permissions.ts`'s `hasPermissionsToUseTool`),
this shouldn't happen: `"auto"` mode's own fast-path checks whether the same action would already
be allowed under `"acceptEdits"` mode (via `tool.checkPermissions` with the mode temporarily
overridden) *before* ever reaching a prompt -- and a plain file write inside the open workspace is
exactly the kind of action `"acceptEdits"` mode allows without asking. So either that fast-path
isn't running at all in this launcher's invocation path, or it ran and still returned "ask" for a
reason not yet identified.

## Investigation so far

The installed Python SDK's own shadowing-warning logic
(`_get_can_use_tool_shadowed_warning` in `claude_agent_sdk/types.py`) only special-cases
`"bypassPermissions"` and whole-tool `allowed_tools` entries as things that auto-approve *before*
`can_use_tool` is consulted. It says nothing about `"auto"` mode's own fast-path/classifier at all
-- consistent with (but not proof of) that logic either not running, or not being reachable, in
this headless, SDK-driven (`claude_agent_sdk.query()`) invocation path, as opposed to the real
CLI's normal interactive terminal usage.

**Most likely explanation, not yet confirmed live**: `permissions.ts` gates the entire fast-path/
classifier branch behind `feature('TRANSCRIPT_CLASSIFIER')`, a feature flag. This launcher's
`query()` call may authenticate through a different mechanism (a bare `ANTHROPIC_API_KEY`, most
likely, since that's the only auth this project's own setup documents) than the interactive
`claude` CLI session the reporting user's own past "Auto mode doesn't prompt" experience comes from
(a full, subscription-linked, logged-in session) -- if that flag is off for whatever account
context this launcher runs under, the fast-path/classifier code simply never engages here,
independent of anything in this codebase.

Not confirmed either way -- no live probe has actually distinguished "flag is off for this auth
context" from "some other precondition in the fast-path isn't met for a `Write` call specifically"
(the fast-path's own comment notes `Agent`/`REPL` tools are deliberately excluded from it for a
different reason; `Write` doesn't appear to be excluded the same way, but this hasn't been
independently verified against the actual `Write` tool's own `checkPermissions` implementation).

## Plan

Two possible next steps, neither attempted yet:
1. Add temporary debug logging in `claude_code_launcher.py`'s `_can_use_tool` (or find an SDK-level
   trace/verbose flag) to see whether the underlying CLI subprocess logs anything about
   `TRANSCRIPT_CLASSIFIER` or the auto-mode fast-path being skipped, which would confirm the
   feature-flag theory directly rather than by inference.
2. If confirmed to be feature-flag-gated by auth context, there is likely nothing to fix at the
   jac-studio level -- this would be an inherent limitation of driving the CLI via a bare API key
   rather than an interactive, subscription-linked session, and worth documenting as a known,
   accepted gap in `ai_chat.jac`'s own docstring (the "Auto" option requests the real mode, but its
   fast-path speed-up may not always engage depending on how the underlying session is
   authenticated) rather than something this project can independently close.

Until either step happens, `"auto"` mode remains correctly wired (the right value is sent, and it
is confirmed to behave differently from Manual whenever the fast-path/classifier *does* engage --
not independently reproduced yet in this app specifically), but a user may still see more approval
prompts under "Auto" here than they're used to from the real extension.
