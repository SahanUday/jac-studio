---
id: 2026-09-04-canusetoolshadowedwarning-leaked-as-chat-error
date: 2026-09-04
category: resolved
severity: minor
status: resolved
phase: 5
subsystem: extensions
jac_version: "0.37.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [ai-chat, claude-agent-sdk, claude-code-integration, real-user-qa]
---

## What happened

Real-user QA, immediately after switching the "Auto" permission mode to `bypassPermissions`
(see `2026-09-04-auto-mode-repointed-to-bypasspermissions`): a real AI Chat turn under Auto mode
completed successfully (the tool ran with no approval prompt, as intended), but the chat panel also
showed a red "ERROR" card containing a Python warning traceback:

```
/home/.../claude_agent_sdk/types.py:1918: CanUseToolShadowedWarning: can_use_tool will not be
invoked: permission_mode 'bypassPermissions' auto-approves every tool call (except explicit deny
rules) before the callback is consulted. To gate every tool call, use a PreToolUse hook instead.
_warn_if_can_use_tool_shadowed(options)
```

## Root cause

`CanUseToolShadowedWarning` is a real Python `UserWarning` subclass the installed SDK raises via
`warnings.warn(...)` whenever `can_use_tool` is registered (this launcher always registers it) under
a `permission_mode` that shadows it entirely -- `bypassPermissions` being exactly that case, by
design, not a misconfiguration. Python's default warning handler prints straight to `sys.stderr`.
`claude_code_client.jac` spawns this launcher with `stderr=asyncio.subprocess.STDOUT` (merged into
the same stream it reads line-by-line as JSON events) and, by design, treats any line that fails to
parse as JSON as proof the launcher crashed before emitting a real event -- correct for an actual
crash, but this warning is neither JSON nor a crash, so it got relayed to the client exactly like
one would be.

## Fix

`claude_code_launcher.py` now calls `warnings.filterwarnings("ignore",
category=CanUseToolShadowedWarning)` once at module scope -- literally the suppression the SDK's own
`CanUseToolShadowedWarning` docstring names as the intended way to silence it. Confirmed live via a
direct subprocess probe (not just code review): the resulting stdout stream is clean JSON only, with
zero trace of the warning, while a genuinely broken launcher invocation still raises a real exception
and still correctly surfaces as an `error` event -- this filter is scoped to the one specific,
by-design warning, not warnings in general.

## Plan

No jaseci/SDK change needed -- this is the SDK's own documented, correct suppression mechanism,
just never wired in. Worth keeping in mind for any *future* `ClaudeAgentOptions` combination this
launcher adds that similarly shadows `can_use_tool` (the SDK's own shadowing-warning helper,
`_get_can_use_tool_shadowed_warning`, also covers whole-tool `allowed_tools` entries) -- if that
combination is ever used deliberately here too, the same filter already covers it.
