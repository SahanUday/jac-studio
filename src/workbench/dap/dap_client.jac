"""DAP client for `.jac` files. jaclang ships no DAP server, but debugpy works directly against
compiled `.jac` bytecode -- `co_filename`/line table already map 1:1 to `.jac` source (tracker
2026-08-31-jaclang-no-native-dap-server-but-debugpy-works-against-compiled-jac-source).
Must spawn the embedded runtime's own `python3*`: inside `jac run`, `sys.executable` is the zig
`jac` wrapper, not an interpreter. Gated on `[terminal] enabled`."""

import asyncio;
import glob as glob_module;
import json;
import os;
import socket;
import sys;
import time;
import from typing { AsyncGenerator, Generator }
import from jaclang.project.config { JacConfig }
import from src.workbench.workspace.workspace_service { get_current_workspace }
import from src.workbench.lsp.lsp_client { _encode_message, _read_message }

glob _DAP_REQUEST_TIMEOUT_SECONDS: float = 10.0;
glob _DAP_CONNECT_TIMEOUT_SECONDS: float = 15.0;

def _dap_enabled -> bool {
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

"""Lexicographically first, so the choice among several candidates is deterministic."""
def:pub _pick_python_binary(candidates: list[str]) -> str | None {
    if len(candidates) == 0 {
        return None;
    }
    return sorted(candidates)[0];
}

def _resolve_embedded_python -> str | None {
    pattern = os.path.join(sys.prefix, "bin", "python3*");
    return _pick_python_binary(glob_module.`glob(pattern));
}

"""The spawned launcher cannot `import jaclang` without inheriting this process's own `sys.path`."""
def:pub _build_pythonpath(path_entries: list[str]) -> str {
    entries = [p for p in path_entries if p];
    return os.pathsep.join(entries);
}

def _launcher_shim_path -> str {
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "dap_launcher.py");
}

def _find_free_port -> int {
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    sock.bind(("127.0.0.1", 0));
    port = sock.getsockname()[1];
    sock.close();
    return port as int;
}

obj DapProcess {
    has process: any = None;
    has reader: any = None;
    has writer: any = None;
    has reader_task: any = None;
    has watcher_task: any = None;
    has pending: dict[int, any] = {};
    has next_seq: int = 1;
    has event_queue: any = None;
    has initialized_event: any = None;
    has stopped_thread_id: int | None = None;
    has debug_path: str = "";
}

"""Gutter-restore only; a plain `glob` is safe because `start_debug_session` never reads it."""
glob _dap_breakpoints: dict[str, list[int]] = {};

"""Cross-process command channel. `start_debug_session` (SSE generator) runs in a genuinely
separate OS process from the RPC control calls and shares no `glob` with them (tracker
2026-08-31-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state), so the control
calls write `{"seq", "cmd"}` here and `_watch_dap_commands` polls it from inside the process that
holds the live handle. `/tmp` is hardcoded, not `tempfile.gettempdir()` -- the two processes
disagreed on where that resolved, so a command written by one was never at the path the other
polled."""
glob _DAP_COMMAND_FILE: str = "/tmp/jac_studio_dap_command.json";

def:pub _reset_dap_for_tests {
    _dap_breakpoints.clear();
}

def _write_dap_command(cmd: str) -> None {
    try {
        seq = 0;
        if os.path.exists(_DAP_COMMAND_FILE) {
            with open(_DAP_COMMAND_FILE, "r") as f {
                existing = json.load(f);
                seq = existing.get("seq", 0);
            }
        }
        payload = {"seq": seq + 1, "cmd": cmd};
        tmp_path = _DAP_COMMAND_FILE + ".tmp";
        with open(tmp_path, "w") as f {
            json.dump(payload, f);
        }
        os.replace(tmp_path, _DAP_COMMAND_FILE);
    } except Exception {}
}

def _read_dap_command -> dict[str, any] | None {
    if not os.path.exists(_DAP_COMMAND_FILE) {
        return None;
    }
    try {
        with open(_DAP_COMMAND_FILE, "r") as f {
            return json.load(f);
        }
    } except Exception {
        return None;
    }
}

def _reset_dap_command_file -> None {
    try {
        if os.path.exists(_DAP_COMMAND_FILE) {
            os.remove(_DAP_COMMAND_FILE);
        }
    } except Exception {}
}

"""`last_seq` starts at whatever the file already held, not 0, so a stale command from a previous
session is never replayed into a fresh one."""
async def _watch_dap_commands(handle: DapProcess) -> None {
    starting = _read_dap_command();
    last_seq = starting.get("seq", 0) if starting is not None else 0;
    while True {
        await asyncio.sleep(0.2);
        if handle.process is None or handle.process.returncode is not None {
            break;
        }
        cmd_data = _read_dap_command();
        if cmd_data is None {
            continue;
        }
        seq = cmd_data.get("seq", 0);
        if seq <= last_seq {
            continue;
        }
        last_seq = seq;
        cmd = cmd_data.get("cmd", "");
        if cmd == "disconnect" {
            try {
                await _send_dap_request(handle, "disconnect", {"terminateDebuggee": True});
            } except Exception {}
            if handle.process is not None and handle.process.returncode is None {
                try {
                    handle.process.kill();
                } except Exception {}
            }
            break;
        }
        if handle.stopped_thread_id is not None {
            await _send_dap_request(handle, cmd, {"threadId": handle.stopped_thread_id});
        }
    }
}

"""Writes a request without awaiting its response -- `attach` must be fired this way: pydevd sends
`initialized` while *handling* `attach` and only answers `attach` after `configurationDone`, so
awaiting it deadlocks (debugpy's own `adapter/clients.py` says so)."""
async def _write_dap_request(handle: DapProcess, command: str, arguments: dict[str, any]) -> (int, any) {
    seq = handle.next_seq;
    handle.next_seq += 1;
    future = asyncio.get_event_loop().create_future();
    handle.pending[seq] = future;
    payload = {"seq": seq, "type": "request", "command": command, "arguments": arguments};
    handle.writer.write(_encode_message(payload));
    await handle.writer.drain();
    return (seq, future);
}

async def _send_dap_request(handle: DapProcess, command: str, arguments: dict[str, any]) -> dict[str, any] | None {
    (seq, future) = await _write_dap_request(handle, command, arguments);
    try {
        result = await asyncio.wait_for(future, timeout=_DAP_REQUEST_TIMEOUT_SECONDS);
    } except Exception {
        del handle.pending[seq];
        return None;
    }
    return result;
}

"""Responses resolve their pending future by `request_seq`; `initialized` sets its own event
(handshake-internal), every other event goes on `event_queue`."""
async def _read_loop(handle: DapProcess) {
    while True {
        try {
            msg = await _read_message(handle.reader);
        } except Exception {
            break;
        }
        if msg is None {
            break;
        }
        msg_type = msg.get("type");
        if msg_type == "response" {
            req_seq = msg.get("request_seq") as int;
            future = handle.pending.get(req_seq);
            if future is not None and not future.done() {
                future.set_result(msg);
            }
            continue;
        }
        if msg_type == "event" {
            event_name = msg.get("event");
            if event_name == "initialized" {
                handle.initialized_event.set();
                continue;
            }
            await handle.event_queue.put(msg);
            if event_name == "terminated" or event_name == "exited" {
                break;
            }
        }
    }
    await handle.event_queue.put({"type": "event", "event": "__reader_closed__", "body": {}});
}

"""The debuggee's own stdout -- a different channel from the DAP events `_read_loop` handles,
queued as a synthetic `output` event rather than relying on the adapter to forward it."""
async def _drain_process_output(handle: DapProcess) {
    stdout = handle.process.stdout;
    while True {
        line = await stdout.readline();
        if not line {
            break;
        }
        text = line.decode("utf-8", errors="replace");
        if text != "" {
            await handle.event_queue.put({"type": "event", "event": "output", "body": {"output": text}});
        }
    }
}

def:pub _dap_stack_frames_from_response(response: any) -> list[dict[str, any]] {
    if not isinstance(response, dict) or not response.get("success") {
        return [];
    }
    frames = [];
    for f in response.get("body", {}).get("stackFrames", []) {
        frames.append({
            "id": f.get("id", 0),
            "name": f.get("name", ""),
            "line": f.get("line", 0),
            "path": f.get("source", {}).get("path", "")
        });
    }
    return frames;
}

"""`None` when the frame has no scope at all."""
def:pub _dap_top_scope_variables_reference(response: any) -> int | None {
    if not isinstance(response, dict) or not response.get("success") {
        return None;
    }
    scopes = response.get("body", {}).get("scopes", []);
    if len(scopes) == 0 {
        return None;
    }
    return scopes[0].get("variablesReference");
}

def:pub _dap_variables_from_response(response: any) -> list[dict[str, any]] {
    if not isinstance(response, dict) or not response.get("success") {
        return [];
    }
    variables = [];
    for v in response.get("body", {}).get("variables", []) {
        variables.append({"name": v.get("name", ""), "value": v.get("value", ""), "type": v.get("type", "")});
    }
    return variables;
}

"""Preflight: debugpy lands in `.jac/venv` via `jac install`, not the runtime cache, and a missing
one makes the real spawn crash before binding its port -- indistinguishable from a slow adapter
until the 15s connect timeout expires."""
async def _check_debugpy_available(python_bin: str, env: dict[str, str]) -> bool {
    try {
        proc = await asyncio.create_subprocess_exec(
            python_bin, "-c", "import debugpy",
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
            env=env
        );
    } except Exception {
        return False;
    }
    try {
        returncode = await asyncio.wait_for(proc.`wait(), timeout=5.0);
        return returncode == 0;
    } except Exception {
        try {
            proc.kill();
        } except Exception {}
        return False;
    }
}

"""Spawns debugpy and drives the handshake through `configurationDone`; returns `(None, reason)`
rather than raising, and every branch must carry a specific reason back."""
async def _spawn_session(path: str, lines: list[int]) -> (DapProcess | None, str) {
    python_bin = _resolve_embedded_python();
    if python_bin is None {
        return (None, "No Python interpreter found for the embedded Jac runtime.");
    }
    port = _find_free_port();
    pythonpath = _build_pythonpath(sys.path);
    launcher = _launcher_shim_path();
    ws = get_current_workspace();
    cwd = ws["root_path"] if ws is not None else None;

    env = dict(os.environ);
    env["PYTHONPATH"] = pythonpath;

    if not await _check_debugpy_available(python_bin, env) {
        return (None, "debugpy is not installed for this project. Run 'jac install' (it's declared in jac.toml) to install it, then try again.");
    }

    handle = DapProcess();
    try {
        handle.process = await asyncio.create_subprocess_exec(
            python_bin, "-X", "frozen_modules=off", "-m", "debugpy",
            "--listen", "127.0.0.1:" + str(port),
            "--wait-for-client",
            launcher, path,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=cwd,
            env=env
        );
    } except Exception {
        return (None, "Failed to spawn the debugpy process.");
    }
    handle.event_queue = asyncio.Queue();
    handle.initialized_event = asyncio.Event();
    handle.debug_path = path;

    connected = False;
    deadline = time.time() + _DAP_CONNECT_TIMEOUT_SECONDS;
    while time.time() < deadline {
        try {
            (reader, writer) = await asyncio.open_connection("127.0.0.1", port);
            handle.reader = reader;
            handle.writer = writer;
            connected = True;
            break;
        } except Exception {
            await asyncio.sleep(0.2);
        }
    }
    if not connected {
        try {
            handle.process.kill();
        } except Exception {}
        return (None, "Timed out waiting for the debug adapter to start listening.");
    }

    handle.reader_task = asyncio.create_task(_read_loop(handle));
    asyncio.create_task(_drain_process_output(handle));

    await _send_dap_request(handle, "initialize", {"adapterID": "jac-studio"});
    await _write_dap_request(handle, "attach", {"justMyCode": False});
    try {
        await asyncio.wait_for(handle.initialized_event.`wait(), timeout=_DAP_CONNECT_TIMEOUT_SECONDS);
    } except Exception {
        try {
            handle.process.kill();
        } except Exception {}
        return (None, "Timed out waiting for the debug adapter to initialize.");
    }

    await _send_dap_request(handle, "setBreakpoints", {
        "source": {"path": path},
        "breakpoints": [{"line": l} for l in lines]
    });
    await _send_dap_request(handle, "configurationDone", {});
    return (handle, "");
}

"""Does not reach a live session -- a breakpoint toggled mid-session applies to the next one, and
`verified: false` says nothing has confirmed it."""
async def:pub set_breakpoints(path: str, lines: list[int]) -> list[dict[str, any]] {
    _dap_breakpoints[path] = lines;
    return [{"line": l, "verified": False} for l in lines];
}

def:pub get_breakpoints(path: str) -> list[int] {
    return _dap_breakpoints.get(path, []);
}

"""The one SSE-streamed entry point. `lines` must be passed by the caller, not read from
`_dap_breakpoints` -- this runs in a separate process (see `_DAP_COMMAND_FILE`). Failures yield an
`error` event rather than raising, and nothing guards server-side against a second session."""
async def:pub start_debug_session(path: str, lines: list[int]) -> Generator {
    async def stream -> AsyncGenerator[str, None] {
        if not _dap_enabled() {
            yield json.dumps({"type": "error", "message": "Debugging is disabled. Set [terminal] enabled = true in jac.toml to turn it on."});
            return;
        }
        if not path.endswith(".jac") {
            yield json.dumps({"type": "error", "message": "Only .jac files can be debugged."});
            return;
        }

        _reset_dap_command_file();
        (handle, spawn_error) = await _spawn_session(path, lines);
        if handle is None {
            yield json.dumps({"type": "error", "message": spawn_error if spawn_error != "" else "Failed to start the debug session."});
            return;
        }
        # Must stay referenced: asyncio holds only a weak reference, so an orphaned task is
        # garbage collected before it does any work.
        handle.watcher_task = asyncio.create_task(_watch_dap_commands(handle));
        yield json.dumps({"type": "started", "path": path});

        while True {
            event_msg = await handle.event_queue.get();
            event_name = event_msg.get("event");
            body = event_msg.get("body", {});

            if event_name == "output" {
                yield json.dumps({"type": "output", "text": body.get("output", "")});
                continue;
            }

            if event_name == "stopped" {
                thread_id = body.get("threadId", 0);
                handle.stopped_thread_id = thread_id;
                st_response = await _send_dap_request(handle, "stackTrace", {"threadId": thread_id});
                frames = _dap_stack_frames_from_response(st_response);
                variables = [];
                if len(frames) > 0 {
                    sc_response = await _send_dap_request(handle, "scopes", {"frameId": frames[0]["id"]});
                    var_ref = _dap_top_scope_variables_reference(sc_response);
                    if var_ref is not None {
                        vr_response = await _send_dap_request(handle, "variables", {"variablesReference": var_ref});
                        variables = _dap_variables_from_response(vr_response);
                    }
                }
                yield json.dumps({
                    "type": "stopped",
                    "reason": body.get("reason", ""),
                    "path": frames[0]["path"] if len(frames) > 0 else path,
                    "line": frames[0]["line"] if len(frames) > 0 else 0,
                    "frames": frames,
                    "variables": variables
                });
                continue;
            }

            if event_name == "continued" {
                handle.stopped_thread_id = None;
                yield json.dumps({"type": "continued"});
                continue;
            }

            if event_name == "terminated" or event_name == "exited" or event_name == "__reader_closed__" {
                yield json.dumps({"type": "terminated"});
                break;
            }

            # Unhandled events are normal chatter, never a termination signal -- `thread` always
            # arrives before the first `stopped`, so breaking here loses every breakpoint.
            continue;
        }
    }
    report stream();
}

"""These five write to `_DAP_COMMAND_FILE`; none can check whether a session is running."""
async def:pub continue_execution -> None {
    _write_dap_command("continue");
}

async def:pub step_over -> None {
    _write_dap_command("next");
}

async def:pub step_into -> None {
    _write_dap_command("stepIn");
}

async def:pub step_out -> None {
    _write_dap_command("stepOut");
}

async def:pub stop_session -> None {
    _write_dap_command("disconnect");
}
