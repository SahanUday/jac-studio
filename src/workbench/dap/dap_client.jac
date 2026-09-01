"""DapClient: Phase 4's native Jac Debug Adapter Protocol client (`docs/roadmap.md`'s last Phase 4
bullet) -- "a debug session can set a breakpoint and step through at least one language's code via
a real DAP adapter." Confirmed against a real, live end-to-end spike before writing this module (see
tracker entry `2026-08-31-jaclang-no-native-dap-server-but-debugpy-works-against-compiled-jac-source`
for the full recipe and the raw DAP transcript this design is drawn from), not assumed from docs.

**jaclang ships no DAP server of its own** -- `jac run --debug` only wires up a bare
`pdb.Pdb` subclass (`jaclang/runtime/debugger.jac`'s `Jdb`) driven over plain stdio, not a
JSON-RPC/DAP server the way `jac lsp` is a real LSP server. **`debugpy` (Microsoft's Python DAP
implementation) works directly against jaclang-compiled bytecode, unverified only until the spike
above confirmed it live, end to end.** The load-bearing fact: `JacProgram().compile(<f>.jac)
.gen.py_bytecode`'s resulting code object already has `co_filename` set to the literal `.jac` path
and a line table that maps 1:1 to real `.jac` source lines -- the same reason `Jdb`'s plain-`pdb`
breakpoints already work at `.jac` granularity. Since both `pdb` and `debugpy`/pydevd resolve
breakpoints purely via `frame.f_code.co_filename` + `frame.f_lineno` + `sys.settrace`, a real DAP
adapter needs zero source-translation step to debug `.jac` files directly -- `dap_launcher.py`
(this module's sibling, plain Python, not Jac) is the only glue needed: it does the same
compile-bytecode-then-exec dance `jac run --debug` does internally, exposed as an ordinary `.py`
entry script debugpy's `--wait-for-client` mode can `runpy.run_path` against.

**Gated behind the same `[terminal] enabled` flag as the terminal and `jac lsp`, for the identical
reason** -- spawning `python -m debugpy` is a subprocess execution, the same trust class already
gated project-wide (`lsp_client.jac`'s docstring makes the same call for the same reason).

**Must spawn the embedded runtime's own `python3.14` binary directly, never `sys.executable`.**
Confirmed live: inside a running `jac run`/`jac run --serve` process, `sys.executable` resolves to
the `jac` CLI binary itself (a zig-compiled wrapper), not a real Python interpreter -- debugpy's own
internal adapter-spawn logic can't invoke that (`error: argument COMMAND: invalid choice:
'.../debugpy/adapter'`, reproduced directly in the spike). `_resolve_embedded_python` instead globs
`sys.prefix + "/bin/python3*"` for the real interpreter binary jaclang's own runtime is actually
running under (`~/.cache/jac/rt/<hash>/python/bin/python3.14` on a real dev-mode install) -- derived
from the live `sys.prefix`, not hardcoded to any one machine's cache hash.

**`PYTHONPATH` must be built from the running process's own `sys.path`, not assumed.** `dap_launcher.py`
needs `import jaclang...` to resolve inside a *freshly spawned* Python process that starts with no
knowledge of how the parent `jac` process found jaclang's own source -- confirmed live that omitting
this fails with a plain `ModuleNotFoundError: No module named 'jaclang'`. `_build_pythonpath` joins
whatever `sys.path` already contains in the running server process (dev-mode: jaclang's own compiler
source dir plus the embedded runtime's site dir; a packaged install would have a different but
equally correct `sys.path` to inherit from) -- this generalizes past dev-mode rather than hardcoding
either shape.

**The free TCP port is self-allocated, not fixed.** `--listen host:port` needs a real port *before*
this client can connect (unlike `jac lsp`'s stdio pipes, DAP-over-`--listen` is a TCP client/server
pair we connect *to*, so there's no "ask the server what port it picked" option -- we'd have nothing
to connect on to receive that answer). `_find_free_port` binds an ephemeral OS-assigned port,
immediately releases it, and hands that number to both `--listen` and this client's own connect call
-- the same "find a free port" idiom test frameworks use, with the same small unavoidable
TOCTOU race (acceptable here: a single local dev-tool session, not a hardened multi-tenant service).

**`-X frozen_modules=off` silences a real debugpy startup warning, not the actual fix for the "runs
straight through" symptom this project hit live.** debugpy's own first line of stdout is "It seems
that frozen modules are being used, which may make the debugger miss breakpoints" whenever it isn't
passed -- debugpy's own documented mitigation, kept here defensively since there's no reason not
to. The *actual* cause of that symptom in this project, found only after that flag alone didn't fix
it: `start_debug_session`'s own event loop (see its docstring) treated any DAP event it didn't
explicitly handle -- `process`, `thread`, `module`, `debugpySockets`, all normal, expected
handshake chatter -- as a termination signal, breaking out of the loop long before the real
`stopped` event (which always arrives *after* `thread`) ever had a chance to.

**`start_debug_session` is the one function that must stay a raw SSE stream, not an RPC stub --
same reasoning as `terminal_service.jac`'s `run_in_terminal`.** A debug session is fundamentally
server-push: `stopped`/`continued`/`output`/`terminated` events arrive on the adapter's own
schedule (when a breakpoint fires, when the debuggee prints), not in response to a client request.

**A `Generator`-returning SSE function runs in a genuinely separate OS process from every other
`def:pub`/`async def:pub` in the same module -- confirmed live, and the reason
`continue_execution`/`step_over`/`step_into`/`step_out`/`stop_session` can't just reach into a
shared `glob` the way `lsp_client.jac`'s `_lsp_processes[jid(root)]` does.** A plain `glob` written
by one RPC call was still empty when read moments later from inside `start_debug_session`'s own
body in the same browser session -- confirmed by comparing `id()` on both sides (different
objects) and by one side's `print()` never reaching the other's stdout at all. See
`_DAP_COMMAND_FILE`'s own docstring (right before `_watch_dap_commands`) for the actual fix: a
file-based command channel, not shared memory. Logged as tracker entry
`2026-08-31-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state`.

**A real ordering quirk in debugpy's own adapter, confirmed by reading its source
(`debugpy/adapter/clients.py`), not assumed from the DAP spec.** Its own comment there says it
outright: pydevd doesn't send `initialized` right after responding to `initialize` the way the DAP
spec's usual example flow suggests -- it sends `initialized` only while *handling* the `attach`
request, and doesn't respond to `attach` itself until `configurationDone` arrives. A client that
`await`s the `attach` response before moving on deadlocks. `_spawn_session` fires `attach` without
awaiting its response (`_write_dap_request`, not `_send_dap_request`), waits on a dedicated
`initialized_event` (set by `_read_loop` when it sees that event, kept off the general
`event_queue` since it's a handshake-internal signal no caller of `start_debug_session` needs to
see), *then* sends `setBreakpoints`/`configurationDone` -- `attach`'s own response arrives later,
resolved by the still-running `_read_loop` the normal way, and nothing needs to wait on it.

**A `stopped` event is enriched with `stackTrace`/`scopes`/`variables` before it's yielded, not
left as the bare DAP event.** The raw DAP `stopped` event only carries a thread id and a reason
(`"breakpoint"`, `"step"`, ...) -- everything a debugging UI actually needs to *show* (which file
and line, the call stack, the top frame's local variables) takes three more request/response round
trips against the same process. Bundling those into one richer event here means the client gets
everything it needs to render a "stopped here, with these values" view from a single SSE frame,
rather than the UI having to fire three more RPC calls itself every time execution pauses."""

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

"""Picks the embedded runtime's own Python binary from a list of glob-matched candidates --
factored out as a pure function so the "which one, if several" policy (lexicographically first,
stable and deterministic) is unit-testable without touching the filesystem."""
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

"""Joins `path_entries` (the caller's own `sys.path`) into a `PYTHONPATH` string, dropping empty
entries (a leading `""` in `sys.path` means "current directory," meaningless once copied into a
different process's `PYTHONPATH` env var). Takes the list as a parameter rather than reading
`sys.path` itself so this stays a pure, directly testable function."""
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

"""Stores `path`'s breakpoints for the gutter to restore on a later file open -- an ordinary
`glob`, safe here because every reader/writer of it (`get_breakpoints`, `set_breakpoints`) is a
plain `async def:pub`/`def:pub` RPC function, never the `Generator`-returning `start_debug_session`
(see that function's own docstring for why it deliberately never reads this dict)."""
glob _dap_breakpoints: dict[str, list[int]] = {};

"""**A `Generator`-returning SSE function runs in a genuinely separate execution context from every
other `def:pub`/`async def:pub` in the same module -- confirmed live, not assumed, and the reason
this module has no `_dap_session`-style glob at all.** A `glob` written by `set_breakpoints` (a
plain RPC call) was still an empty `{}` when read from *inside* `start_debug_session`'s own body
moments later in the same browser session -- confirmed by comparing `id(_dap_breakpoints)` on both
sides (different objects) and by `set_breakpoints`'s own `print()` never appearing in the server's
stdout log at all, only `start_debug_session`'s did -- the two aren't just different Python module
instances, they don't even share a stdout stream, which only happens across a real OS process
boundary. This isn't `jid(root)`-specific either (an earlier, narrower theory) -- a bare unkeyed
glob shows the identical split. Logged as tracker entry
`2026-08-31-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state`.

**The fix: a file-based command channel, not shared memory.** `start_debug_session` receives
`lines` as an explicit argument (the client already tracks them) instead of reading
`_dap_breakpoints`, sidestepping the isolation for the *initial* breakpoint set entirely.
Mid-session control (`continue`/step/stop) has no such shortcut -- those calls arrive as separate,
later RPC requests, in the *other* process, needing to reach the live subprocess handle that only
exists inside `start_debug_session`'s own process. `_DAP_COMMAND_FILE` (a fixed `/tmp` path, not
`tempfile.gettempdir()` -- caught live: the RPC-process and SSE-process instances disagreed on
where that resolved to, so a command written by one was never at the path the other polled;
hardcoding `/tmp` sidesteps needing to know why. Acceptable for a genuinely single-user local dev
tool, the same scope this module's "one global session" design already assumes) is real, OS-level
shared state neither process's own memory needs to agree on:
`continue_execution`/`step_over`/`step_into`/`step_out`/`stop_session`
each just write a JSON `{"seq", "cmd"}` command to it; `_watch_dap_commands`, a background task
`start_debug_session` spawns alongside its own event-reading loop, polls that same file (every
200ms) from *inside* the process that actually holds the live `DapProcess` handle, and dispatches
each new `seq` it sees as a real DAP request against it."""
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

"""Polls `_DAP_COMMAND_FILE` for new commands written by `continue_execution`/`step_over`/
`step_into`/`step_out`/`stop_session` (each running as a separate, later RPC call, in a different
process -- see this module's own docstring) and dispatches each one against `handle`, the live
session this task shares a closure with. `last_seq` starts at whatever the file already held when
the watcher started (not 0) so a stale command left over from a previous session/page load is never
replayed into a fresh one. Stops on `disconnect` (after actually disconnecting) or once the process
has exited on its own."""
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

"""Writes a DAP `request` frame and registers its pending future, but does **not** await the
response -- the low-level primitive `_send_dap_request` builds on. Exists as its own function only
because `attach` (see this module's own docstring) must be fired without waiting for its response,
unlike every other request this client sends."""
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

"""The background task started once per session, alongside it -- reads every message the adapter
sends for the rest of the session's life. Responses resolve their matching pending future by
`request_seq`; the `initialized` event (handshake-internal, see this module's own docstring) sets
`initialized_event` directly rather than going through `event_queue`; every other event is queued
for whichever coroutine is draining it (`start_debug_session`'s own stream)."""
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

"""Drains the spawned `python -m debugpy` process's own stdout/stderr (piped together, matching
`terminal_service.jac`'s own `stderr=STDOUT` convention) -- this is the debuggee's real program
output (a `.jac` file's own `print()` calls, plus debugpy's own startup diagnostics), a genuinely
different channel from the DAP `stopped`/`continued`/... events `_read_loop` handles, piped
directly to `event_queue` as a synthetic `output` event so `start_debug_session`'s stream shows it
without depending on whether the adapter also happens to forward it as a DAP `output` event."""
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

"""Converts a raw `stackTrace` response into this module's own `{id, name, line, path}` shape --
factored out as a pure function, unit-testable against a hand-built response dict, the same role
`lsp_client.jac`'s `_lsp_location_to_dict` plays for LSP responses."""
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

"""Converts a raw `scopes` response into the top scope's `variablesReference` (the id `variables`
needs next) -- `None` when there's no scope at all (a frame with no locals to show)."""
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

"""Converts a raw `variables` response into this module's own `{name, value, type}` shape."""
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

"""Runs `python_bin -c "import debugpy"` (with `PYTHONPATH` already pointed at the same env
`_spawn_session` is about to use) as a cheap, fast preflight before the real spawn-and-connect
dance -- **the concrete failure this exists for, caught live**: `jac.toml` declares
`debugpy = ">=1.8.0"`, but that only lands in this project's own `.jac/venv` after an actual
`jac install` run -- it is not bundled into the embedded runtime cache `_resolve_embedded_python`
targets. When `.jac/venv` is missing or stale (pruned by this machine's own periodic
build-artifact cleanup, or simply never installed on a fresh checkout -- see this project's own
`jac-language` skill for the identical `.jac/venv`-wiped-by-`clean --all` gotcha), the *real*
`-m debugpy` subprocess spawned further down still starts, but crashes near-instantly with its own
`ModuleNotFoundError: No module named 'debugpy'` and never binds its listen port -- invisible to
this client, since `_drain_process_output` isn't wired up until *after* the TCP connect below
succeeds. Without this preflight, that failure was indistinguishable from a slow adapter: the
client just sat at "Starting..." for the full `_DAP_CONNECT_TIMEOUT_SECONDS` (15s) before falling
back to the same generic message every other failure path already produced. Confirmed live (this
exact scenario, reproduced by emptying `.jac/venv` and hitting Start): five seconds, one specific,
actionable message, instead of fifteen seconds of silence and a dead end."""
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

"""Spawns `python -m debugpy --listen <port> --wait-for-client dap_launcher.py <path>`, connects to
it as a DAP client, and drives the handshake through `configurationDone` -- see this module's own
docstring for why each step is shaped the way it is (embedded interpreter, `PYTHONPATH`, the
`attach`/`initialized` ordering quirk). Returns `(None, reason)` on any failure along the way (no
embedded Python found, debugpy not installed, spawn failed, connect timed out, handshake timed out)
rather than raising -- matching this project's established "nothing to attach to" convention for a
feature that can't proceed, but **carrying the specific reason back to the caller (2026-09-02),
not just a bare `None`** -- every branch here used to discard *why* it failed, collapsing every
distinct cause into `start_debug_session`'s one generic "Failed to start the debug session."
message, exactly the gap that made the missing-`debugpy` case above so slow to diagnose."""
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

"""Stores `lines` as `path`'s breakpoints, purely for the gutter to restore on a later file open --
does **not** reach a live session (there is no in-memory way to, see this module's own docstring);
a breakpoint toggled while a session is already running only takes effect on the *next* session,
a deliberate, small v1 scope cut (live mid-session breakpoint edits are real follow-up work, not
silently broken -- the caller still gets each line back with `verified: false`, an honest signal
nothing confirmed it yet)."""
async def:pub set_breakpoints(path: str, lines: list[int]) -> list[dict[str, any]] {
    _dap_breakpoints[path] = lines;
    return [{"line": l, "verified": False} for l in lines];
}

def:pub get_breakpoints(path: str) -> list[int] {
    return _dap_breakpoints.get(path, []);
}

"""The one SSE-streamed entry point (see this module's own docstring for why) -- spawns a fresh
session debugging `path` with `lines` as its breakpoints (passed explicitly by the caller, not read
from `_dap_breakpoints` -- see this module's own docstring for why), then streams
`output`/`stopped`/`continued`/`terminated`/`error` events, JSON-encoded one per line, for the rest
of the session's life, while `_watch_dap_commands` (spawned alongside) handles mid-session control.
Refuses non-`.jac` paths (this client only knows how to debug the one language `dap_launcher.py`
knows how to run) with an `error` event rather than raising -- an SSE stream that raises
mid-response is a worse experience than a stream that explains itself and ends cleanly. Does not
guard against a second concurrent session server-side (the isolated-process constraint means there
is no reliable in-memory way to check) -- the client only ever offers one "Start" button, disabled
while a session is already open, which is enough for this project's single-user scope."""
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
        # Stored on `handle`, not discarded -- asyncio only holds a *weak* reference to a task once
        # nothing else references it, so an orphaned `create_task(...)` call can be garbage
        # collected before it ever does real work. Caught live: the very first version of this line
        # didn't keep the return value, and every `continue_execution`/step call after a real
        # breakpoint hit silently did nothing (`handle.reader_task` above already gets the same
        # treatment for the identical reason).
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

            # Every other event (process/thread/module/debugpySockets/debugpyWaitingForServer/...)
            # is normal, expected DAP chatter -- ignored, not a termination signal. Treating any
            # unhandled event as "terminated" here was a real, live-caught bug: `thread`
            # ("reason": "started") always arrives *before* the first real `stopped` event, so this
            # branch broke the loop before a breakpoint ever had a chance to fire.
            continue;
        }
    }
    report stream();
}

"""Each of these five just writes one command to `_DAP_COMMAND_FILE` -- see this module's own
docstring for why that's the whole mechanism, and `_watch_dap_commands` for where it's actually
consumed. None of them can check "is a session even running" (no shared memory to check against);
the client only offers these controls while its own last-known SSE event said `stopped`, which is
enough for this project's single-user scope."""
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
