"""TerminalService: real, reconnectable PTY sessions behind the integrated terminal.
Deny-by-default, gated by `[terminal] enabled` in `jac.toml`. See ADR 0025, ADR 0078.
The PTY itself lives in `terminal_session_daemon.py`, a detached subprocess -- an SSE generator
here runs in a genuinely separate OS process from ordinary calls and shares no `glob` with them
(tracker 2026-09-22-websocket-walkers-batch-not-stream-and-serialize-messages), so every call in
this file talks to the daemon only through files under its session directory, never live state."""

import asyncio;
import glob as glob_module;
import json;
import os;
import re;
import sys;
import time;
import from typing { AsyncGenerator, Generator }
import from jaclang.project.config { JacConfig }

glob _SESSION_ID_PATTERN: re.Pattern[str] = re.compile(r"^[a-zA-Z0-9_-]{8,64}$");
glob _SESSIONS_ROOT: str = "/tmp/jac_studio_terminal_sessions";
glob _HEARTBEAT_INTERVAL_SECONDS: float = 3.0;
glob _LIVENESS_CHECK_INTERVAL_SECONDS: float = 1.0;
glob _INPUT_CHUNK_BYTES: int = 4000;

def _terminal_enabled -> bool {
    cfg = JacConfig.discover();
    if not cfg {
        return False;
    }
    section = cfg.get_section("terminal");
    if not section {
        return False;
    }
    return bool(section.get("enabled", False));
}

"""Client-supplied path component -- reject anything that isn't a plain id before it touches a
filesystem path, or a crafted session_id becomes a path-traversal write outside `_SESSIONS_ROOT`."""
def _valid_session_id(session_id: str) -> bool {
    return bool(_SESSION_ID_PATTERN.`match(session_id));
}

def _session_dir(session_id: str) -> str {
    return os.path.join(_SESSIONS_ROOT, session_id);
}

"""Same resolution dap_client.jac uses: inside `jac run`, `sys.executable` is the zig `jac`
wrapper, not an interpreter that can run a plain .py script."""
def _resolve_embedded_python -> str | None {
    pattern = os.path.join(sys.prefix, "bin", "python3*");
    candidates = sorted(glob_module.`glob(pattern));
    return candidates[0] if candidates else None;
}

def _daemon_script_path -> str {
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "terminal_session_daemon.py");
}

"""`ptyprocess` lands in `.jac/venv` via `jac install`, not the runtime cache the resolved
interpreter itself lives in (same split dap_client.jac's debugpy check documents) -- the spawned
daemon only sees it if this process's own `sys.path` is forwarded as its PYTHONPATH."""
def _build_pythonpath(path_entries: list[str]) -> str {
    entries = [p for p in path_entries if p];
    return os.pathsep.join(entries);
}

def _daemon_pid(session_dir: str) -> int | None {
    pid_path = os.path.join(session_dir, "daemon.pid");
    if not os.path.exists(pid_path) {
        return None;
    }
    try {
        with open(pid_path, "r") as f {
            return int(f.read().strip());
        }
    } except Exception {
        return None;
    }
}

def _daemon_alive(session_dir: str) -> bool {
    pid = _daemon_pid(session_dir);
    if pid is None {
        return False;
    }
    try {
        os.kill(pid, 0);
        return True;
    } except (ProcessLookupError, PermissionError) {
        return False;
    }
}

def _append_command(session_dir: str, payload: dict[str, str | int]) {
    line = (json.dumps(payload) + "\n").encode("utf-8");
    path = os.path.join(session_dir, "input.log");
    fd = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600);
    try {
        os.write(fd, line);
    } finally {
        os.close(fd);
    }
}

"""Ensures a session's daemon is running; idempotent -- a re-mounted terminal panel or a page
reload calling this again against an already-live session is a no-op, not a duplicate spawn."""
async def:pub open_session(session_id: str, cwd: str, cols: int, rows: int) -> dict[str, str] {
    if not _terminal_enabled() {
        return {"status": "disabled"};
    }
    if not _valid_session_id(session_id) {
        return {"status": "invalid_session_id"};
    }
    session_dir = _session_dir(session_id);
    if _daemon_alive(session_dir) {
        return {"status": "attached"};
    }
    python_bin = _resolve_embedded_python();
    if python_bin is None {
        return {"status": "error", "message": "No Python interpreter found for the embedded Jac runtime."};
    }
    os.makedirs(session_dir, exist_ok=True);
    env = dict(os.environ);
    env["PYTHONPATH"] = _build_pythonpath(sys.path);
    err_log = open(os.path.join(session_dir, "daemon.err"), "ab");
    try {
        await asyncio.create_subprocess_exec(
            python_bin, _daemon_script_path(),
            "--session-dir", session_dir,
            "--cwd", cwd if cwd else os.getcwd(),
            "--cols", str(cols), "--rows", str(rows),
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=err_log,
            env=env,
            start_new_session=True
        );
    } except Exception as e {
        return {"status": "error", "message": f"Failed to start the terminal session: {e}"};
    } finally {
        err_log.close();
    }
    return {"status": "started"};
}

"""SSE endpoint: replays the session's buffered output, then tails it live. Ends the stream once
the daemon has exited and nothing new remains -- otherwise identical to a normal `tail -f`."""
async def:pub attach_session(session_id: str) -> Generator[str, None, None] {
    async def stream -> AsyncGenerator[str, None] {
        if not _terminal_enabled() {
            yield "Terminal is disabled. Set [terminal] enabled = true in jac.toml to turn it on.\n";
            return;
        }
        if not _valid_session_id(session_id) {
            return;
        }
        session_dir = _session_dir(session_id);
        heartbeat_path = os.path.join(session_dir, "heartbeat");
        output_path = os.path.join(session_dir, "output.log");

        offset = 0;
        inode = None;
        if os.path.exists(output_path) {
            st = os.stat(output_path);
            inode = st.st_ino;
            with open(output_path, "rb") as f {
                initial = f.read();
                offset = f.tell();
            }
            if initial {
                yield initial.decode("utf-8", errors="replace");
            }
        }

        last_heartbeat = 0.0;
        last_liveness_check = 0.0;
        while True {
            await asyncio.sleep(0.05);
            now = time.monotonic();
            if now - last_heartbeat >= _HEARTBEAT_INTERVAL_SECONDS {
                last_heartbeat = now;
                try {
                    with open(heartbeat_path, "a") {
                        os.utime(heartbeat_path, None);
                    }
                } except Exception {}
            }

            chunk = b"";
            if os.path.exists(output_path) {
                st = os.stat(output_path);
                if inode is not None and st.st_ino != inode {
                    offset = 0;
                }
                inode = st.st_ino;
                if st.st_size > offset {
                    with open(output_path, "rb") as f {
                        f.seek(offset);
                        chunk = f.read();
                        offset = f.tell();
                    }
                }
            }
            if chunk {
                yield chunk.decode("utf-8", errors="replace");
                continue;
            }

            if now - last_liveness_check >= _LIVENESS_CHECK_INTERVAL_SECONDS {
                last_liveness_check = now;
                if not _daemon_alive(session_dir) {
                    return;
                }
            }
        }
    }
    report stream();
}

"""Split so a single large paste can't exceed the atomic-append guarantee `_append_command`
relies on (POSIX `PIPE_BUF`, ~4KB) -- each piece is its own complete JSON line."""
def _write_input_chunks(session_dir: str, data: str) {
    start = 0;
    while start < len(data) {
        piece = data[start:start + _INPUT_CHUNK_BYTES];
        _append_command(session_dir, {"type": "input", "data": piece});
        start += _INPUT_CHUNK_BYTES;
    }
}

async def:pub send_input(session_id: str, data: str) -> None {
    if not _terminal_enabled() or not _valid_session_id(session_id) {
        return;
    }
    session_dir = _session_dir(session_id);
    if not os.path.isdir(session_dir) {
        return;
    }
    _write_input_chunks(session_dir, data);
}

async def:pub resize_session(session_id: str, cols: int, rows: int) -> None {
    if not _terminal_enabled() or not _valid_session_id(session_id) {
        return;
    }
    session_dir = _session_dir(session_id);
    if not os.path.isdir(session_dir) {
        return;
    }
    _append_command(session_dir, {"type": "resize", "cols": cols, "rows": rows});
}

"""Not gated on `_terminal_enabled()`, unlike the other session calls -- closing an already-running
session is a kill switch, not new execution capability, and should still work if the config
flips off mid-session."""
async def:pub close_session(session_id: str) -> None {
    if not _valid_session_id(session_id) {
        return;
    }
    session_dir = _session_dir(session_id);
    if not os.path.isdir(session_dir) {
        return;
    }
    _append_command(session_dir, {"type": "close"});
}
