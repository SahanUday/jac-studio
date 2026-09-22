# ptyprocess — `ptyprocess` >=0.7.0 (POSIX); `pywinpty` >=2.0.0 (Windows, unverified)

What we use it for: the real pseudoterminal backing each terminal session -- spawn, read, write,
resize, terminate. See [ADR 0078](../decisions/0078-terminal-real-pty-sessions.md).
Where it's wired in: `src/workbench/terminal/terminal_session_daemon.py`, a plain Python script
run as a detached subprocess (same reasoning as `dap_launcher.py`/`claude_code_launcher.py`: this
needs to outlive any single Jac request, so it can't be `.jac`-compiled server code).

## Capabilities we use

| Capability | API | Where |
|---|---|---|
| Spawn a shell in a PTY | `PtyProcessUnicode.spawn([shell], cwd=, dimensions=(rows, cols))` | `_spawn_pty` |
| Read output | `proc.read(size)`, multiplexed via `select.select([proc.fd], ...)` | main daemon loop |
| Write input | `proc.write(str)` | main daemon loop, dispatching `input` commands |
| Resize | `proc.setwinsize(rows, cols)` | main daemon loop, dispatching `resize` commands |
| Liveness / exit | `proc.isalive()` | main daemon loop |
| Terminate | `proc.terminate(force=True)`, `proc.close(force=True)` | idle timeout, explicit `close` command, and the `finally` cleanup |

## Available but not yet used

| Capability | API | Possible use |
|---|---|---|
| Raw byte mode | `PtyProcess` (vs. `PtyProcessUnicode`) | Only needed if a future feature must see raw bytes instead of decoded text (e.g. binary-safe passthrough) |

## Limits and gotchas

- **Windows needs `pywinpty`, not `ptyprocess`** -- `ptyprocess` is POSIX-only. The daemon's
  `_spawn_pty` branches on `sys.platform == "win32"` to import `winpty.PtyProcess` instead, but
  this machine has no Windows environment to test against. Treat the Windows branch as unproven
  until it's actually run there; don't cite it as working. `pywinpty` is declared under
  `[optional-dependencies.windows]` in `jac.toml`, not the unconditional `[dependencies]` list --
  it has no installable wheel on Linux/macOS and would break `jac install` there if made mandatory.
- **The daemon is deliberately not `.jac`-compiled Jac code.** It has no jaclang dependency at all
  (unlike `dap_launcher.py`, which does), so it doesn't need the `PYTHONPATH` bridging that
  `dap_client.jac`'s `_resolve_embedded_python()` needs for `jaclang` imports -- but it *does* still
  need `PYTHONPATH` set from the parent's `sys.path` to find `ptyprocess` itself, which `jac
  install` places in `.jac/venv`, not the embedded runtime's own interpreter prefix that
  `_resolve_embedded_python()` resolves. Confirmed live: omitting this makes the daemon crash with
  `ModuleNotFoundError: No module named 'ptyprocess'` on its very first line of real work.
- **The daemon must be detached from the spawning request**, not just backgrounded --
  `start_new_session=True` on `asyncio.create_subprocess_exec`, stdio redirected away from pipes.
  A session's whole reason to exist (reconnect across a browser refresh) depends on the PTY
  surviving independently of whichever Jac process spawned it.
- **`select.select` on the PTY's fd, not a blocking `read()` in a thread** -- a fd that's hit EOF
  (child exited) still reports readable repeatedly; the loop's `isalive()` check right after the
  read is what actually terminates it, confirmed live with a quick-exiting child (2 loop
  iterations, no busy-loop).
