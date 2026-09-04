---
id: 2026-09-04-auto-mode-fast-path-not-observed-in-headless-sdk-invocation
date: 2026-09-04
category: missing-feature
severity: minor
status: resolved
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

## Resolution (2026-09-04, same day, a few hours later)

Tried step 1's static-analysis idea first, on the actual bundled CLI binary rather than debug
logging: `claude_agent_sdk`'s own `_bundled/claude` (confirmed via `_find_bundled_cli()` in the
SDK's `subprocess_cli.py` that this is genuinely what gets spawned -- no `claude` exists on this
machine's `PATH` for it to fall back to). Came back ambiguous: `strings` against the binary shows
zero occurrences of the literal `"TRANSCRIPT_CLASSIFIER"` flag name, but `.mode==="auto"`
comparisons *do* appear -- inconclusive on its own, since minification can rename/strip a flag's
name without necessarily removing the code around it.

Rather than draw a third conclusion from inference (the second one, in the sibling entry, was
already wrong once), ran a real, isolated, controlled test instead -- the actual "verify
empirically" standard this project holds itself to, applied properly this time. A bare
`claude_agent_sdk.query()` script, no jac-studio code involved at all, `can_use_tool` instrumented
to just count invocations, same "create a new file" prompt, three runs differing only in
`permission_mode`:

```
mode='acceptEdits':      can_use_tool called 0 times
mode='bypassPermissions': can_use_tool called 0 times (SDK's own CanUseToolShadowedWarning fires too)
mode='auto':              can_use_tool called 1 time
```

This conclusively isolates the gap to `"auto"` mode specifically, in this exact installed CLI
build. `"acceptEdits"` and `"bypassPermissions"` both correctly skip the callback through the
identical SDK invocation shape `"auto"` uses -- ruling out "headless SDK usage can't do fast-paths
in general" (the original theory in this entry) and ruling out any bug in this codebase's own
`can_use_tool` wiring, prompt, or auth. `"auto"` mode's fast-path/classifier is simply inert in the
currently-bundled CLI build, for reasons outside this project's control (most plausibly a feature
still being rolled out and gated off for whatever build/account context `claude-agent-sdk` bundles
right now).

**Closing as resolved, not because the underlying gap is fixed (it isn't, and can't be from this
codebase), but because the investigation itself is genuinely done**: `"auto"` is confirmed to be
the correct value to send (per the sibling entry's correction), and this entry's own open question
-- whether jac-studio's integration is somehow suppressing the fast-path -- is answered: no, it
isn't. A future `claude-agent-sdk` release bundling a CLI build with this feature active would
likely just start working without any change needed here.
