# M7 — Terminal: real PTY sessions

**Status**: complete, 2026-09-22

A real, reconnectable shell session behind the integrated terminal, replacing the one-shot
subprocess-per-command model from M0/ADR 0026.

## Shipped

| What |
|---|
| `terminal_session_daemon.py`: a detached, plain-Python daemon owning a real `ptyprocess` PTY per session, independent of any Jac request's lifetime. |
| `terminal_service.jac`: `open_session`/`attach_session`/`send_input`/`resize_session`/`close_session`, replacing `run_in_terminal`. Output flows down via SSE (`attach_session`, confirmed real per-`yield` push); input/resize/close flow up via ordinary calls, all file-based across the daemon's session directory. |
| `terminal.jac`/`terminal.impl.jac`: hand-rolled line editing (Enter/Backspace/Ctrl+C parsing) removed — the real shell's own readline does that now. Session id persists in `sessionStorage`, reattaching the same running shell across a page refresh. |
| xterm.js addons wired in: `addon-clipboard` (OSC 52), `addon-web-links`, `addon-search` (behind a small Ctrl/Cmd+F find bar), `addon-serialize`, `addon-unicode11`, `addon-webgl` (best-effort). |
| `ptyprocess`/`pywinpty` added to `jac.toml` (`pywinpty` under `[optional-dependencies.windows]`, not unconditional — no installable wheel on Linux/macOS). |
| `terminal_service.test.jac`: id validation (including path-traversal rejection), the gate's consistency across `send_input`/`resize_session`/`close_session`, input chunking. |

## Decisions
[ADR 0078](../decisions/0078-terminal-real-pty-sessions.md) (supersedes [ADR 0026](../decisions/0026-terminal-v1-one-process-per-command.md)).

## Deviations from plan

- The obvious-looking fit, Jac's native `@restspec(protocol=APIProtocol.WEBSOCKET) async walker`,
  was ruled out empirically before any implementation: it buffers all `report`s until the walker's
  traversal completes (no per-report push) and handles inbound messages on one connection serially,
  not concurrently. Both are fatal for a live shell. Landed as SSE-down/POST-up instead — see the
  tracker entry below and ADR 0078's "Why".
- The session's live PTY can't be held inside the SSE generator's own process the way
  `dap_client.jac`'s single-call model does, because a session must outlive any one connection to
  support reconnect. Moved the live handle into a fully separate, detached daemon process instead,
  with *both* directions (not just DAP's one-way command channel) going through files.
- A real, non-obvious environment bug surfaced by actually running it, not by reasoning about the
  code: the daemon crashed with `ModuleNotFoundError: No module named 'ptyprocess'` because the
  resolved embedded-runtime Python interpreter and the `.jac/venv` where `jac install` places
  `ptyprocess` are different prefixes — fixed by forwarding this process's own `sys.path` as the
  daemon's `PYTHONPATH`, the same bridge `dap_client.jac` already needed for `debugpy`.
- Added a small Ctrl/Cmd+F find bar (not originally scoped) once `addon-search` was already being
  wired in for the "available but not yet used" cleanup — cheap enough alongside the rest of the
  addon pass not to defer.
- `send_input`/`resize_session` weren't gated on `[terminal] enabled` in an early draft — caught
  while writing the test suite, not before. `close_session` is deliberately left ungated (a kill
  switch, not new execution capability).

## Blockers logged

- `2026-09-22-websocket-walkers-batch-not-stream-and-serialize-messages` (major, workaround-found)
  — the WS-walker finding above.

## Left open

- Windows PTY support (`pywinpty`) is implemented but unverified — no Windows environment available
  here. See `known-limitations.md`.
- The find bar's Ctrl/Cmd+F keybinding wasn't independently browser-verified — `jac browse`'s
  headless automation couldn't reliably synthesize modifier-key chords (also true for Ctrl+C, a
  pre-existing xterm behavior this milestone didn't change). Code-reviewed and type-checked clean;
  structurally identical to the already-proven copy-override handler beside it. See
  `known-limitations.md`.
- `addon-serialize` is loaded but not yet used for anything — reconnect's scrollback replay is
  served from the daemon's own `output.log`, which already does the job. A future feature wanting
  richer buffer serialization (e.g. exporting terminal contents) has it available for free.
