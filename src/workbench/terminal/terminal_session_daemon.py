"""Owns one real PTY session for the integrated terminal, run detached from any Jac request
process -- a session must outlive any single SSE connection to support reconnect. Talks to
terminal_service.jac only through files under --session-dir (see
docs/decisions/0078-terminal-real-pty-sessions.md): no `glob` state crosses the SSE-generator
process boundary (tracker
2026-09-22-websocket-walkers-batch-not-stream-and-serialize-messages cites the underlying
2026-09-01 isolation finding), so this is the same file-based-channel pattern dap_client.jac's
`_DAP_COMMAND_FILE` uses, generalized to carry PTY output as well as input.

Usage: terminal_session_daemon.py --session-dir DIR --cwd DIR --cols N --rows N
       [--shell PATH] [--idle-timeout SECONDS]
"""

import argparse
import json
import os
import select
import sys
import time

OUTPUT_CAP_BYTES = 512 * 1024
OUTPUT_KEEP_TAIL_BYTES = 256 * 1024
POLL_INTERVAL_SECONDS = 0.03
IDLE_CHECK_INTERVAL_SECONDS = 5.0


def _default_shell() -> str:
    return os.environ.get("SHELL") or "/bin/bash"


def _spawn_pty(shell: str, cwd: str, cols: int, rows: int):
    if sys.platform == "win32":
        # pywinpty -- unverified, no Windows environment to test against (see ADR 0078).
        from winpty import PtyProcess as WinPtyProcess

        return WinPtyProcess.spawn(shell, cwd=cwd, dimensions=(rows, cols))
    import ptyprocess

    return ptyprocess.PtyProcessUnicode.spawn([shell], cwd=cwd, dimensions=(rows, cols))


def _write_meta(session_dir: str, cols: int, rows: int, cwd: str) -> None:
    payload = {"cols": cols, "rows": rows, "cwd": cwd, "started_at": time.time(), "pid": os.getpid()}
    with open(os.path.join(session_dir, "meta.json"), "w") as f:
        json.dump(payload, f)


def _touch(path: str) -> None:
    with open(path, "a"):
        os.utime(path, None)


def _rotate_if_needed(path: str) -> None:
    """Atomic replace, not truncate-in-place: a reader mid-poll must see either the old
    file or the new one, never a half-written one -- see attach_session's inode check."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return
    if size <= OUTPUT_CAP_BYTES:
        return
    with open(path, "rb") as f:
        f.seek(-OUTPUT_KEEP_TAIL_BYTES, os.SEEK_END)
        tail = f.read()
    tmp_path = path + ".tmp"
    with open(tmp_path, "wb") as f:
        f.write(tail)
    os.replace(tmp_path, path)


def _append_output(session_dir: str, text: str) -> None:
    path = os.path.join(session_dir, "output.log")
    with open(path, "ab") as f:
        f.write(text.encode("utf-8", errors="replace"))
    _rotate_if_needed(path)


def _read_new_input_commands(input_path: str, offset: int) -> tuple[list[dict], int]:
    if not os.path.exists(input_path):
        return [], offset
    with open(input_path, "rb") as f:
        f.seek(offset)
        chunk = f.read()
        new_offset = f.tell()
    commands = []
    for line in chunk.split(b"\n"):
        if not line.strip():
            continue
        try:
            commands.append(json.loads(line))
        except ValueError:
            continue
    return commands, new_offset


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session-dir", required=True)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--cols", type=int, default=80)
    parser.add_argument("--rows", type=int, default=24)
    parser.add_argument("--shell", default="")
    parser.add_argument("--idle-timeout", type=float, default=1800.0)
    args = parser.parse_args()

    session_dir = args.session_dir
    os.makedirs(session_dir, exist_ok=True)
    pid_path = os.path.join(session_dir, "daemon.pid")
    with open(pid_path, "w") as f:
        f.write(str(os.getpid()))
    heartbeat_path = os.path.join(session_dir, "heartbeat")
    _touch(heartbeat_path)
    _write_meta(session_dir, args.cols, args.rows, args.cwd)

    proc = _spawn_pty(args.shell or _default_shell(), args.cwd, args.cols, args.rows)

    input_path = os.path.join(session_dir, "input.log")
    open(input_path, "a").close()
    input_offset = 0
    last_idle_check = time.monotonic()

    try:
        while True:
            readable, _, _ = select.select([proc.fd], [], [], POLL_INTERVAL_SECONDS)
            if readable:
                try:
                    chunk = proc.read(65536)
                except EOFError:
                    chunk = ""
                if chunk:
                    _append_output(session_dir, chunk)

            if not proc.isalive():
                _append_output(session_dir, "\r\n[session ended]\r\n")
                break

            commands, input_offset = _read_new_input_commands(input_path, input_offset)
            for cmd in commands:
                kind = cmd.get("type")
                if kind == "input":
                    proc.write(cmd.get("data", ""))
                elif kind == "resize":
                    proc.setwinsize(cmd.get("rows", args.rows), cmd.get("cols", args.cols))
                elif kind == "close":
                    proc.terminate(force=True)

            now = time.monotonic()
            if now - last_idle_check >= IDLE_CHECK_INTERVAL_SECONDS:
                last_idle_check = now
                try:
                    idle_for = time.time() - os.path.getmtime(heartbeat_path)
                except OSError:
                    idle_for = 0.0
                if idle_for > args.idle_timeout:
                    proc.terminate(force=True)
                    break
    finally:
        try:
            proc.close(force=True)
        except Exception:
            pass
        try:
            os.remove(pid_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
