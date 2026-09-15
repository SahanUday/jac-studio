# 0075 — Auto mode sends `bypassPermissions`; real `auto` confirmed inert in this CLI build

- **Date**: 2026-09-15
- **Status**: accepted; corrects two earlier reversals in the same investigation

## Decision

The permission-mode picker's "Auto" option sends the SDK value `"bypassPermissions"`, not
`"auto"`.

## Why

`"auto"` is a real, classifier-backed auto-approval mode with its own accept-edits fast-path in the
real `claude` CLI (confirmed by reading `permissions.ts`'s `hasPermissionsToUseTool`) — genuinely
different from Manual, contradicting an earlier, wrong conclusion in this same investigation that
it behaves identically to Manual. But an isolated `claude_agent_sdk.query()` probe, varying only
`permission_mode`, found `"auto"` still invokes `can_use_tool` once per call in the currently
bundled CLI build, while `"bypassPermissions"` and `"acceptEdits"` correctly skip it — most likely
because the CLI's classifier feature flag isn't active for whatever account context this launcher's
headless call authenticates through. So a real `"auto"` buys nothing over Manual *in this app,
right now*, even though the mode itself is real and correctly designed upstream.

## Consequences

"Auto" in this app's UI means "run end to end, only stop for a genuine clarifying question" —
`bypassPermissions` is the mode that actually does that (also skips Bash/MCP with no per-call
check, a larger trust step than `acceptEdits`, confirmed and flagged with the project sponsor
before wiring it in). If a future CLI build activates the classifier fast-path for this launcher's
auth context, revisit whether `"auto"` should be sent instead — this decision is about the
currently bundled CLI's actual behavior, not a claim that `"auto"` doesn't work as designed.
