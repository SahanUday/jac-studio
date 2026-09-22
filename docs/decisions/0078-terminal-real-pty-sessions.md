# 0078 — Terminal moves to real, reconnectable PTY sessions over SSE-down/POST-up

- **Date**: 2026-09-22
- **Status**: accepted

## Decision

Replace the one-shot-subprocess-per-command model ([0026](0026-terminal-v1-one-process-per-command.md))
with a persistent PTY per terminal tab, managed server-side by a session registry keyed by session
ID, independent of any one connection's lifecycle:

- **PTY**: `ptyprocess` (POSIX) / `pywinpty` (Windows, unverified — no Windows dev environment here)
  spawns and owns the real shell process. One session per tab, not per command.
- **Server → client (output)**: a `def:pub -> Generator` SSE endpoint attaches to a session, replays
  its scrollback ring buffer, then tails live PTY output as it's produced.
- **Client → server (input/resize)**: ordinary `def:pub` calls — one for keystroke data, one for
  terminal resize (`TIOCSWINSZ` via `ptyprocess.setwinsize`).
- **Reconnect**: the client persists its session ID (survives refresh); the SSE stream reattaches to
  the same still-running PTY. A session with no attached stream is reaped after an idle timeout.

## Why

Bidirectional traffic is a hard requirement — PTY output and resize/interrupt signals must flow
independently of command boundaries. The obvious fit, Jac's native `@restspec(protocol=
APIProtocol.WEBSOCKET) async walker`, does not support it: verified empirically (tracker entry
`2026-09-22-websocket-walkers-batch-not-stream-and-serialize-messages`) that a WS walker buffers
all `report`s until its traversal completes (no per-report push) and handles inbound messages on
one connection serially, not concurrently. Both properties are fatal for a live shell — output
would only ever surface in reply to the next keystroke, and a keystroke sent mid-command would
queue behind whatever the shell is still doing. SSE's `Generator`+`report`, by contrast, is verified
to push each `yield` immediately (`jac-sv-streaming`, and already relied on by the terminal's
current SSE use) — so the split keeps each direction on the transport that actually does what's
needed, rather than forcing both onto the one that doesn't.

## Consequences

- Real shell semantics: `cd`, exported env vars, `Ctrl+C` as a genuine `SIGINT`, and interactive
  programs (an editor, a REPL, `ssh`) all work, because the shell is real and persistent — this
  resolves 0026's stated gap rather than working around it.
- A session outlives any single SSE/HTTP connection: the server owns an in-memory registry
  (session ID → PTY handle + scrollback buffer) and an idle-reap policy, not just a request handler.
  This is materially more state to manage than 0026's one-shot model.
- Windows PTY support (`pywinpty`) is implemented but unverified — this machine has no Windows
  environment to test against. Treat it as unproven until run on Windows; don't cite it as working.
- Any future work wanting true low-latency bidirectional push (not just this terminal) hits the
  same WS-walker limitation and should either reuse this SSE-down/POST-up shape or wait on the
  upstream fix noted in the tracker entry.
