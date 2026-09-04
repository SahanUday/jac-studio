---
id: 2026-09-04-auto-permission-mode-silently-behaved-like-manual
date: 2026-09-04
category: resolved
severity: major
status: resolved
phase: 5
subsystem: extensions
jac_version: "0.37.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [ai-chat, claude-agent-sdk, claude-code-integration, permission-mode, real-user-qa]
---

## What happened

Real-user QA: with the AI Chat's permission-mode picker set to "Auto" (added earlier the same day,
modeled on the real Claude Code extension's "Manual / Edit automatically / Plan / Auto" switcher),
a prompt still triggered a tool-approval card requiring manual Allow/Deny -- the exact behavior
"Auto" is supposed to skip. Confirmed live via the server's own request log that the client was
sending the right thing end to end: `start_chat_turn` received `'permission_mode': 'auto'`
correctly, and the launcher passed it straight through to `ClaudeAgentOptions.permission_mode`, and
the approval card still appeared and had to be explicitly allowed via `approve_tool_call`.

## Root cause

`"auto"` is a real, accepted value in the installed SDK's `PermissionMode` type literal (`Literal["default",
"acceptEdits", "plan", "bypassPermissions", "dontAsk", "auto"]`) -- which is exactly why sending it
never raised an error or got rejected. The original picker code (added same day, fourth QA pass)
assumed, without checking, that `"auto"` was "the SDK's own broadest bypass" -- a plausible-sounding
guess from the name alone, never verified against the actual CLI source.

Traced into the real `claude` CLI's own TypeScript source (`utils/permissions/PermissionMode.ts`,
the same checkout used for two earlier findings this same day):

```ts
export function isExternalPermissionMode(mode: PermissionMode): mode is ExternalPermissionMode {
  if (process.env.USER_TYPE !== 'ant') {
    return true
  }
  return mode !== 'auto' && mode !== 'bubble'
}
```

-- "External users can't have auto." It's gated behind a `TRANSCRIPT_CLASSIFIER` feature flag and
`USER_TYPE === 'ant'` (Anthropic-internal), and its own `PERMISSION_MODE_CONFIG` entry, even when
active, maps `external: 'default'` -- the identical externally-visible behavior as Manual mode. So
this app's "Auto" option had been silently behaving exactly like "Manual" since it was first added;
the reported symptom (approval card still appears) is the correct, expected result of that mapping,
not a flaky/intermittent bug.

## Fix

`ai_chat.jac`'s `PERMISSION_MODE_OPTIONS`'s "Auto" entry now sends `"bypassPermissions"` instead of
`"auto"` -- confirmed (same source) this is the real, external, always-on full-bypass mode
(`PermissionMode.ts`'s own `title: 'Bypass Permissions'`; referenced directly throughout
`permissions.ts` wherever the CLI needs to skip every other permission gate). The user-visible
label ("Auto") is unchanged -- only the wire-level value sent was wrong. `claude_code_launcher.py`'s
docstring, which stated the original wrong claim, corrected in place with a visible **CORRECTION**
section per this project's own tracker/docstring convention, rather than silently rewritten.

## Plan

No jaseci/SDK change needed -- this was a wrong assumption in this project's own code, not a bug in
`claude_agent_sdk` or the CLI. The general lesson (already being applied this same day to the
`system_prompt` finding too): any `ClaudeAgentOptions` field whose *name* suggests a specific
behavior should be verified against the real CLI/SDK source before shipping a UI control built on
that assumption, not inferred from the string alone -- this project has now hit that exact trap
twice in one day (`system_prompt=None` "must mean default", `"auto"` "must mean broadest bypass").
Worth a one-line callout in `docs/architecture.md`'s "AI coding tool integrations" section the same
way the `system_prompt` finding already suggested.
