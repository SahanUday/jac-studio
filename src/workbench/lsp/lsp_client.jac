"""LspClient: Phase 4's native Jac LSP client (`docs/roadmap.md`) -- "spawn `jac lsp` as a
subprocess the same way the terminal spawns any other process... build a generic client speaking
LSP's JSON-RPC-over-stdio wire format." Confirmed against the real server source
(`jaclang.lsp.server`, `jaclang.lsp.protocol.server`), not assumed: standard `Content-Length`-framed
JSON-RPC over stdio, a real `initialize`/`initialized` handshake, `textDocument/didOpen`/
`didChange`/`didClose`/`didSave` document sync, and a genuinely bidirectional wire -- the server
pushes unsolicited `textDocument/publishDiagnostics` notifications on its own initiative (from
`type_check()`, triggered by `didOpen`/`didChange`/`didSave`), not just responses to requests this
client sends.

**Gated behind the same `[terminal] enabled` flag as the integrated terminal, matching
`architecture.md`'s explicit call** ("the same `shell`-capability gate") -- spawning `jac lsp` is a
subprocess execution, the same trust class the terminal already gates, even though (unlike a task's
arbitrary shell string) the command itself is fixed and non-user-authorable. Honoring the documented
architectural decision rather than second-guessing it into `git_service.jac`'s ungated posture,
which was justified by a *different* property (a fixed allowlist of subcommands invoked as argument
lists, never a shell string) that doesn't actually apply here.

**A persistent, `jid(root)`-keyed process, not a one-shot `subprocess.run` -- a real architectural
departure from every other Phase 4 backend module (`git_service.jac`, `task_service.jac`).** LSP
is not simple request/response: the server needs to hold an in-memory index of every open
document to answer completion/hover/definition questions at all, and spawning it fresh per call
would both pay real startup cost per keystroke and lose all document-sync state between calls. The
process (and its background stdout-reading task) is spawned lazily, on first use, cached in
`_lsp_processes[jid(root)]`, and kept alive for the rest of this server process's lifetime -- the
correct choice here, unlike the terminal's own explicitly-deferred "persistent session" idea
(`terminal_service.jac`'s docstring), because LSP's client/server document-sync model is inherently
stateful in a way "run one command, stream its output" isn't.

**Must be `async def:pub`, not plain sync -- load-bearing, not a style choice.** jaclang's dispatcher
offloads a plain sync `def:pub`'s entire body onto a worker thread via `asyncio.to_thread`
(`jaclang/runtimelib/serving/app.jac`), each call getting its own thread with its own default event
loop; `asyncio.create_task` called from inside one of those would attach the background reader task
to a throwaway, request-scoped loop that's gone the moment the request finishes -- exactly wrong for
something that must keep running and receiving `publishDiagnostics` notifications across every
future request. `async def:pub` functions are `await`-ed directly on the server's own real,
long-lived event loop instead (the same reason `terminal_service.jac` is `async def:pub`, just for
a different underlying need), so a task created there genuinely persists.

**`textDocument/didChange` is sent bundled into `get_completions` (a fresh full-content sync
immediately before the completion request), not on every keystroke as its own notification.** This
is deliberately not the naive "sync on every edit" shape real LSP clients (including VS Code
itself) normally use -- doing that here would mean a network round-trip to jac-studio's own server
on every keystroke, the exact per-keystroke RPC cost `monaco_editor.jac`'s own docstring already
ruled out for editor content generally. Since Monaco's own `registerCompletionItemProvider`
mechanism already rate-limits *when* a completion request actually fires (debounced internally,
triggered by real typing pauses or trigger characters), bundling the sync into that same request is
the natural, already-rate-limited sync point -- no separate debounce timer needed. The trade-off:
`publishDiagnostics` (server-triggered by `didChange`) only refreshes as a side effect of a
completion request or an explicit save, not truly live-as-you-type -- a deliberate v1 scope cut,
not a corner silently cut (task-runner-fed diagnostics from Phase 4's earlier bullet already cover
the "diagnostics exist at all" exit criterion; this is about how *fresh* the LSP-sourced ones are
between keystrokes).

**`publishDiagnostics` diagnostics feed directly into `diagnostics.jac`'s existing `Diagnostic`
node type and Problems panel** -- the same data model and UI `task_service.jac`'s problem matchers
already write to, not a second diagnostics surface. Uses the same `batch`-marker convention
`diagnostics.jac`'s own docstring documents (every diagnostic from one `publishDiagnostics`
notification shares one `time.time()` batch) for the identical reason: re-running `type_check`
(via a later `didChange`) must replace the previous batch's diagnostics for that file, not
duplicate them, and a purely graph-based `batch`-max filter is the only fix that survived a live
multi-request repro for that class of bug (see that module's docstring for the two approaches that
didn't).

**`textDocument/didClose` is never sent -- a deliberate, small, accepted scope cut, not an
oversight.** Closing an editor tab genuinely unmounts `MonacoEditorApp` (unlike a sidebar view's
mount-once-hide-via-CSS), so a `can with exit` hook could call it -- but the only cost of not doing
so is the LSP server holding a slightly stale in-memory copy of a closed file, harmless for
correctness in a local, single-user dev tool session. Matches the same "small accepted leak" trade-
off `monaco_editor.jac`'s own docstring already makes for never explicitly disposing a closed tab's
Monaco model."""

import asyncio;
import json;
import os;
import time;
import from jaclang.project.config { JacConfig }
import from src.workbench.workspace.workspace_service { get_current_workspace, ensure_path_reachable }
import from src.workbench.diagnostics.diagnostics { add_diagnostic, clear_diagnostics }
import from src.workbench.output.output_service { append_log }

glob _LSP_LOG_CHANNEL: str = "Jac Language Server";
glob _LSP_REQUEST_TIMEOUT_SECONDS: float = 10.0;

glob _LSP_SEVERITY_MAP: dict[int, str] = {1: "error", 2: "warning", 3: "info", 4: "hint"};

def _lsp_enabled -> bool {
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

def:pub _path_to_uri(path: str) -> str {
    return "file://" + path;
}

def:pub _uri_to_path(uri: str) -> str {
    if uri.startswith("file://") {
        return uri[len("file://"):];
    }
    return uri;
}

def:pub _encode_message(msg: dict[str, any]) -> bytes {
    body = json.dumps(msg).encode("utf-8");
    header = ("Content-Length: " + str(len(body)) + "\r\n\r\n").encode("ascii");
    return header + body;
}

"""Reads one `Content-Length`-framed JSON-RPC message off `stream` (an object exposing async
`readline`/`readexactly`, matching `asyncio.StreamReader`'s shape -- accepted as `any` so a small
in-memory fake can stand in for tests, not just a real subprocess pipe). Returns `None` on a clean
stream close (empty `readline`), the correct "the process exited" signal for the reader loop above
to stop on."""
async def:pub _read_message(stream: any) -> dict[str, any] | None {
    header = b"";
    while True {
        line = await stream.readline();
        if not line {
            return None;
        }
        if line == b"\r\n" or line == b"\n" {
            break;
        }
        header += line;
    }
    length = 0;
    for part in header.decode("ascii").split("\r\n") {
        if part.lower().startswith("content-length:") {
            length = int(part.split(":")[1].strip());
        }
    }
    if length == 0 {
        return None;
    }
    body = await stream.readexactly(length);
    return json.loads(body.decode("utf-8"));
}

obj LspProcess {
    has process: any = None;
    has reader_task: any = None;
    has pending: dict[int, any] = {};
    has next_id: int = 1;
    has open_versions: dict[str, int] = {};
}

glob _lsp_processes: dict[str, LspProcess] = {};

def:pub _reset_lsp_for_tests {
    _lsp_processes.clear();
}

async def _drain_stderr(handle: LspProcess) -> None {
    stream = handle.process.stderr;
    while True {
        line = await stream.readline();
        if not line {
            break;
        }
        text = line.decode("utf-8", errors="replace").rstrip();
        if text != "" {
            append_log(_LSP_LOG_CHANNEL, text);
        }
    }
}

async def _handle_publish_diagnostics(params: dict[str, any]) -> None {
    path = _uri_to_path(params.get("uri", ""));
    if path == "" {
        return;
    }
    diags = params.get("diagnostics", []);
    clear_diagnostics(path);
    if len(diags) == 0 {
        return;
    }
    ensure_path_reachable(path);
    batch = time.time();
    for d in diags {
        severity = _LSP_SEVERITY_MAP.get(d.get("severity", 1), "error");
        message = d.get("message", "");
        range_start = d.get("range", {}).get("start", {});
        line = int(range_start.get("line", 0)) + 1;
        column = int(range_start.get("character", 0)) + 1;
        add_diagnostic(path, message, severity, line, column, "jac lsp", batch);
    }
}

"""The background task started once per process, alongside it -- reads every message `jac lsp`
sends for the rest of this process's life, resolving pending request futures and dispatching
unsolicited notifications (currently just `publishDiagnostics`; anything else is logged to the
Output channel for visibility, not silently dropped)."""
async def _read_loop(handle: LspProcess) -> None {
    stream = handle.process.stdout;
    while True {
        try {
            msg = await _read_message(stream);
        } except Exception as e {
            break;
        }
        if msg is None {
            break;
        }
        msg_id = msg.get("id");
        method = msg.get("method");
        if method is None and msg_id is not None {
            future = handle.pending.get(msg_id);
            if future is not None and not future.done() {
                future.set_result(msg.get("result"));
            }
            continue;
        }
        if method == "textDocument/publishDiagnostics" {
            await _handle_publish_diagnostics(msg.get("params", {}));
        } elif method is not None {
            append_log(_LSP_LOG_CHANNEL, "[notification] " + method);
        }
    }
}

async def _send_notification(handle: LspProcess, method: str, params: dict[str, any]) -> None {
    payload = {"jsonrpc": "2.0", "method": method, "params": params};
    handle.process.stdin.write(_encode_message(payload));
    await handle.process.stdin.drain();
}

async def _send_request(handle: LspProcess, method: str, params: dict[str, any]) -> any {
    msg_id = handle.next_id;
    handle.next_id += 1;
    future = asyncio.get_event_loop().create_future();
    handle.pending[msg_id] = future;
    payload = {"jsonrpc": "2.0", "id": msg_id, "method": method, "params": params};
    handle.process.stdin.write(_encode_message(payload));
    await handle.process.stdin.drain();
    try {
        result = await asyncio.wait_for(future, timeout=_LSP_REQUEST_TIMEOUT_SECONDS);
    } except Exception as e {
        del handle.pending[msg_id];
        return None;
    }
    return result;
}

"""Lazily spawns and initializes `jac lsp` for the current workspace, or returns the already-running
one -- the one function every public entry point in this module calls first. Returns `None` (never
raises) when the task runner-style gate is off or no workspace is open, matching this project's
established "nothing to attach to" convention for a feature that can't proceed rather than a thrown
error."""
async def _ensure_process -> LspProcess | None {
    if not _lsp_enabled() {
        return None;
    }
    ws = get_current_workspace();
    if ws is None {
        return None;
    }
    key = jid(root);
    if key in _lsp_processes {
        existing = _lsp_processes[key];
        if existing.process is not None and existing.process.returncode is None {
            return existing;
        }
    }

    handle = LspProcess();
    try {
        handle.process = await asyncio.create_subprocess_exec(
            "jac", "lsp",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=ws["root_path"]
        );
    } except Exception as e {
        append_log(_LSP_LOG_CHANNEL, "Failed to start jac lsp: " + str(e));
        return None;
    }
    handle.reader_task = asyncio.create_task(_read_loop(handle));
    asyncio.create_task(_drain_stderr(handle));
    _lsp_processes[key] = handle;

    await _send_request(handle, "initialize", {
        "processId": None,
        "rootUri": _path_to_uri(ws["root_path"]),
        "capabilities": {}
    });
    await _send_notification(handle, "initialized", {});
    return handle;
}

async def _sync_content(handle: LspProcess, path: str, content: str) -> None {
    uri = _path_to_uri(path);
    version = handle.open_versions.get(uri, 1) + 1;
    handle.open_versions[uri] = version;
    await _send_notification(handle, "textDocument/didChange", {
        "textDocument": {"uri": uri, "version": version},
        "contentChanges": [{"text": content}]
    });
}

async def:pub notify_document_open(path: str, content: str) -> None {
    handle = await _ensure_process();
    if handle is None {
        return;
    }
    uri = _path_to_uri(path);
    handle.open_versions[uri] = 1;
    await _send_notification(handle, "textDocument/didOpen", {
        "textDocument": {"uri": uri, "languageId": "jac", "version": 1, "text": content}
    });
}

"""Syncs `content` (a fresh full-document sync, matching `_sync_content`'s own shape) and then
notifies the server this document was saved -- `jac lsp`'s own `did_save` handler re-runs
`type_check`, so this is also how a save-triggered diagnostics refresh happens, not just a completion
request."""
async def:pub notify_document_save(path: str, content: str) -> None {
    handle = await _ensure_process();
    if handle is None {
        return;
    }
    await _sync_content(handle, path, content);
    await _send_notification(handle, "textDocument/didSave", {
        "textDocument": {"uri": _path_to_uri(path)}
    });
}

"""Syncs `content`, then asks for completions at `line`/`column` (1-based, matching this project's
own convention everywhere else -- `handle_cursor_change`, `get_line_changes`, ... -- converted to
LSP's 0-based `line`/`character` at the boundary). Returns a small, client-friendly shape
(`label`/`kind`/`detail`/`insertText`), not the raw LSP `CompletionItem`/`CompletionList` -- the
client-side provider (`jac_completion_provider.jac`) maps `kind` onto Monaco's own differently-
numbered `CompletionItemKind` enum, so translating the LSP integer here would just move that mapping
without simplifying anything."""
async def:pub get_completions(path: str, content: str, line: int, column: int) -> list[dict[str, any]] {
    handle = await _ensure_process();
    if handle is None {
        return [];
    }
    await _sync_content(handle, path, content);
    result = await _send_request(handle, "textDocument/completion", {
        "textDocument": {"uri": _path_to_uri(path)},
        "position": {"line": line - 1, "character": column - 1}
    });
    if result is None {
        return [];
    }
    items = result.get("items", []) if isinstance(result, dict) else result;
    if not isinstance(items, list) {
        return [];
    }
    completions = [];
    for item in items {
        completions.append({
            "label": item.get("label", ""),
            "kind": item.get("kind", 0),
            "detail": (item.get("detail") or ""),
            "insertText": (item.get("insertText") or item.get("label", ""))
        });
    }
    return completions;
}
