---
id: 2026-09-22-websocket-walkers-batch-not-stream-and-serialize-messages
date: 2026-09-22
category: missing-feature
severity: major
status: workaround
phase: 6
subsystem: workbench-shell
jac_version: "0.37.3"
related_vscode_ref: "src/vs/workbench/contrib/terminal"
upstream_issue: ""
tags: [websocket, restspec, streaming, terminal, pty]
---

Designing a real-PTY-backed terminal (replacing the one-shot-subprocess model from
[ADR 0026](decisions/0026-terminal-v1-one-process-per-command.md)) needs the server to push PTY
output to the browser the moment it's produced, independent of client input timing — a long-running
command must show output before the user types anything else. The `jac guide reference/plugins/
jac-scale-http` WebSockets section reads as if this is supported: "`report` values stream back" on
an `@restspec(protocol=APIProtocol.WEBSOCKET) async walker`.

Verified empirically instead of trusting that wording (throwaway spike, not committed —
`main.jac` + `probe.py` in a scratch project, `jac run --no-client` on a plain `service`-kind
project): a WS walker with `action == "start"` looping 6 times over
`await asyncio.sleep(0.3); report f"tick {i}";` does NOT deliver 6 incremental frames. The client
receives **one** message at ~1.8s containing all 6 ticks in a single `reports` array — the whole
walker traversal runs to completion and the standard walker-report-batching semantics (same as a
plain `POST /walker/<name>` call) apply. `jac guide internals/interop` confirms `/ws/<name>` really
is "the same machinery" as the HTTP walker endpoint, just kept open — not a channel with a
per-`report` flush like a `def:pub -> Generator` SSE endpoint (`jac-sv-streaming`) has.

Second, worse finding from the same spike: a second inbound message (`{"action":"ping"}`) sent on
the *same open connection* 0.7s into the first message's 1.8s-long walker run was not answered
until 1.82s — right after the first walker's traversal finished. Messages on one WS connection are
handled **serially**, not concurrently. For a terminal this would mean keystrokes sent while a long
command is still producing output would queue behind it instead of reaching the PTY's stdin
immediately.

## Plan

Neither behavior is a bug — both are the documented walker-report model reapplied consistently to
a persistent socket. The gap is real, though: there is no way for an `async walker` on `/ws/<name>`
to push data proactively (unprompted by a new inbound message), and no way to handle a second
inbound message while a `can` block from an earlier message is still running on the same
connection. Filing upstream is worth doing (either add true bidirectional/async delivery to WS
walkers, or reword the guide's "stream back" so it doesn't imply per-`report` flush), but the
workaround is straightforward and arguably the better architecture anyway: keep the two directions
on the transports that already do exactly what's needed — a `def:pub -> Generator` SSE endpoint
(confirmed real per-`yield` push, no buffering) for PTY output down to the client, and ordinary
`def:pub` calls for keystrokes/resize up to the server, with the PTY session itself persisted
server-side in an in-memory registry independent of either connection's lifecycle. See
`docs/decisions/0078-terminal-real-pty-sessions.md` for the design this shaped.
