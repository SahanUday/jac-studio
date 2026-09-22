# 0078 — Terminal moves to real, reconnectable PTY sessions over SSE-down/POST-up

- **Date**: 2026-09-22
- **Status**: accepted

## Decision

Replace the one-shot-subprocess-per-command model ([0026](0026-terminal-v1-one-process-per-command.md))
with a persistent PTY per terminal tab, outliving any single connection:

- **PTY**: `ptyprocess` (POSIX) / `pywinpty` (Windows, unverified) owns the real shell, held by a
  detached daemon process (`terminal_session_daemon.py`) — not in the Jac server's own memory.
- **Output**: a `def:pub -> Generator` SSE endpoint replays scrollback, then tails the live PTY.
- **Input/resize**: ordinary `def:pub` calls (`TIOCSWINSZ` via `ptyprocess.setwinsize`).
- **Reconnect**: client persists its session ID; a session with no attached stream is idle-reaped.

## Why

PTY output and resize/interrupt signals must flow independently of command boundaries. Jac's
native `@restspec(protocol=APIProtocol.WEBSOCKET) async walker` looked like the fit but isn't:
verified empirically (tracker `2026-09-22-websocket-walkers-batch-not-stream-and-serialize-messages`)
that it buffers all `report`s until the traversal completes and handles inbound messages
serially — both fatal for a live shell. SSE's `Generator`+`report` is verified to push each
`yield` immediately, so each direction gets the transport that actually does what it needs.

The same finding also rules out an in-process session registry: an SSE handler and an ordinary
`def:pub` call for the same session can run in genuinely different OS processes sharing no `glob`
state. Session state is therefore a directory of files (`daemon.pid`, `input.log`, `output.log`,
`heartbeat`) that both sides read/write, not an in-memory map.

## Consequences

- Real shell semantics (`cd`, env vars, `Ctrl+C` as a genuine `SIGINT`, interactive programs) —
  resolves 0026's gap rather than working around it.
- The server now owns real state (a session directory per PTY, plus idle-reap), not just a
  request handler — genuinely more to manage than 0026's one-shot model.
- Windows (`pywinpty`) is implemented but unverified — no Windows environment to test against.
- Any future feature wanting low-latency bidirectional push hits the same WS-walker limitation.
