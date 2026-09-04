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
tags: [ai-chat, claude-agent-sdk, claude-code-integration, permission-mode, real-user-qa, correction]
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

## Fix (WRONG -- see CORRECTION below before acting on anything in this section)

~~`ai_chat.jac`'s `PERMISSION_MODE_OPTIONS`'s "Auto" entry now sends `"bypassPermissions"` instead
of `"auto"` -- confirmed (same source) this is the real, external, always-on full-bypass mode
(`PermissionMode.ts`'s own `title: 'Bypass Permissions'`; referenced directly throughout
`permissions.ts` wherever the CLI needs to skip every other permission gate). The user-visible
label ("Auto") is unchanged -- only the wire-level value sent was wrong.~~

## Plan (WRONG -- see CORRECTION below)

~~No jaseci/SDK change needed -- this was a wrong assumption in this project's own code, not a bug
in `claude_agent_sdk` or the CLI.~~ (The general lesson underneath this -- verify a field's meaning
against real source before building a UI control on it -- still holds; it's just this entry's own
*application* of that lesson that was itself wrong, ironically by stopping at the first source file
found instead of the one that actually governs behavior.)

## CORRECTION, 2026-09-04, hours later: the "Fix" above was itself wrong

A real user, testing this app, directly contradicted the conclusion above from their own lived
experience: in the real Claude Code extension, Auto mode genuinely does not prompt for every tool
call. That should have been the first signal to re-check, not push back on the user.

The original "Root cause" section above only read `PermissionMode.ts`'s UI-facing config table --
one field (`external: 'default'`) -- and never checked the file that actually *enforces* permission
decisions, `permissions.ts`. Reading `hasPermissionsToUseTool` there (specifically the
`appState.toolPermissionContext.mode === 'auto'` branch) shows `"auto"` is a real, distinct mode
with its own logic: first a fast-path (skip the prompt if the same action would already be allowed
under `"acceptEdits"`, checked via `tool.checkPermissions` with the mode temporarily overridden --
this is what silently auto-allows most file edits without ever reaching a classifier), and only
then, for anything the fast-path didn't clear, an actual AI-classifier call -- both gated behind
the CLI's own `TRANSCRIPT_CLASSIFIER` feature flag. None of this resembles Manual mode's
unconditional per-call prompt at all. `"bypassPermissions"` is a different, blunter,
classifier-free mode that skips every check unconditionally -- not a faithful "Auto" per the real
extension's own semantics.

**Reverted**: `ai_chat.jac`'s `PERMISSION_MODE_OPTIONS` sends `"auto"` again.
`claude_code_launcher.py`'s docstring carries the full two-correction record (this wrong
conclusion, how it was caught, and the corrected understanding), kept visible rather than quietly
rewritten -- the wrong turn is as much the record here as the eventual right answer.

**Still genuinely open, spun out to its own entry** (this app's own `can_use_tool` callback was
still reached under `"auto"` in the live test that first surfaced this whole investigation, which
the fast-path logic above says shouldn't happen for a plain file write) --
see `2026-09-04-auto-mode-fast-path-not-observed-in-headless-sdk-invocation`.

## Plan (superseding the wrong one above)

The lesson from the *correction*, not the original wrong fix: verifying a claim against source
means finding the code that actually *enforces* the behavior, not the first plausible-looking file
that mentions the value -- a UI/config table can describe something adjacent to, but not identical
to, real runtime behavior. Worth folding into `jac-studio-implementation`'s "verify empirically"
guidance directly, since this is the same discipline that guide already asks for, just missed here
on the first pass.
