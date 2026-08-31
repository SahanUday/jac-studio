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

**`_handle_publish_diagnostics` ends with an explicit `Jac.acommit()` -- a third, genuinely new
persistence finding, distinct from the two just mentioned.** Graph writes made from a background
`asyncio.create_task` (this handler's own call context, reacting to an unsolicited server
notification with no HTTP request/response cycle wrapping it) never go through jaseci's normal
per-request auto-commit at all, not just unreliably -- see that function's own docstring for the
full live repro and why an explicit commit call was the fix, not another read-side workaround.

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
import from jaclang { JacRuntime as Jac }
import from jaclang.project.config { JacConfig }
import from src.workbench.workspace.workspace_service { get_current_workspace, ensure_path_reachable }
import from src.workbench.diagnostics.diagnostics { add_diagnostic, clear_diagnostics }
import from src.workbench.output.output_service { append_log }
import from src.editor.document_service { open_document, save_document }

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

"""`jac lsp` is a language server for exactly one language -- every public entry point below checks
this before doing anything, rather than trusting callers to remember. **Caught live, not designed
in from the start**: `monaco_editor.jac` mounts for every open tab regardless of file type, so its
first version synced *every* opened file (`.txt`, `.py`, anything) to the same shared `jac lsp`
process. That's not just pointless work -- `jac lsp`'s own dispatcher processes one type-check task
at a time (confirmed live via its own debug logging, each task taking 10-60+ seconds on a real,
if small, workspace), so a backlog of type-check requests for files `jac lsp` was never going to
usefully check starved out the requests that actually mattered, and real `.jac` diagnostics never
surfaced within any reasonable wait. Guarding here, once, protects every current and future caller
(`notify_document_open`, `notify_document_save`, `get_completions`) without relying on each call
site to remember the same check."""
def:pub _is_jac_file(path: str) -> bool {
    return path.endswith(".jac");
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

"""**Ends with an explicit `Jac.acommit()` -- load-bearing, not defensive padding, caught live.**
Every other graph write in this project (`add_diagnostic` from `task_service.jac`'s problem
matchers, every `workspace_service.jac` mutation, ...) runs as the direct, synchronous body of a
request that a real HTTP call is waiting on -- jaseci's dispatcher commits those durably in
`_finalize_call_response`, *after* the function returns, as part of finishing that response. This
function is different: it runs inside `_read_loop`'s background `asyncio.create_task`, reacting to
an unsolicited notification from the `jac lsp` subprocess, with no HTTP request/response cycle
wrapping it at all -- so that automatic per-request commit never fires. Confirmed live, not assumed:
`add_diagnostic` genuinely returned `True` (its own in-process graph mutation succeeded) but a
*separate*, later `list_all_diagnostics()` call kept coming back empty -- the identical symptom the
"field mutation not committed" and "edge deletion not committed" findings elsewhere in this project
describe, but for a fresh reason (no request boundary to hook a commit to at all, not an unreliable
one) rather than either of those. `await Jac.acommit()` (`import from jaclang { JacRuntime as Jac }`
-- **not** ambient the way `root`/`jid`/`jobj` are, caught live: an earlier version assumed it was,
since a standalone repro script had it resolve with no import at all, but this project's own module
context needs the explicit import or the call fails at runtime with `name 'Jac' is not defined`,
silently killing the reader task the same way an uncaught exception here always would -- exactly
why the `try`/`except` wrapping this call in `_read_loop` isn't optional either) forces the same
durable commit `_finalize_call_response` performs internally, explicitly. `Jac` is checker-typed as
`Unknown` (the same untyped-Python-interop boundary `jac-python-interop`'s guide describes for any
object the
checker can't fully type), hence the `as any` cast -- not a workaround for a real type error, just
satisfying the checker about a boundary it was never going to resolve."""
async def _handle_publish_diagnostics(params: dict[str, any]) -> None {
    path = _uri_to_path(params.get("uri", ""));
    if path == "" {
        return;
    }
    diags = params.get("diagnostics", []);
    clear_diagnostics(path);
    if len(diags) == 0 {
        await (Jac as any).acommit();
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
    await (Jac as any).acommit();
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
            try {
                await _handle_publish_diagnostics(msg.get("params", {}));
            } except Exception as e {
                append_log(_LSP_LOG_CHANNEL, "[error] publishDiagnostics handling failed: " + str(e));
            }
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
    if not _is_jac_file(path) {
        return;
    }
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
    if not _is_jac_file(path) {
        return;
    }
    handle = await _ensure_process();
    if handle is None {
        return;
    }
    await _sync_content(handle, path, content);
    await _send_notification(handle, "textDocument/didSave", {
        "textDocument": {"uri": _path_to_uri(path)}
    });
}

"""Pulled out of `get_hover` as its own pure, testable step -- `jac lsp`'s `get_hover_info` always
wraps its answer in an LSP `MarkupContent` (`{kind, value}`), but the wire type it's declared as
(`Hover.contents`) is the broader LSP union (`MarkupContent | MarkedString | MarkedString[]`), and a
plain string is exactly what a `MarkedString` looks like over JSON -- handling both shapes here
rather than assuming the one this particular server happens to always send today."""
def:pub _extract_hover_text(contents: any) -> str | None {
    if isinstance(contents, dict) {
        value = contents.get("value", "");
        return value if value else None;
    }
    if isinstance(contents, str) {
        return contents if contents else None;
    }
    return None;
}

"""Syncs `content`, then asks `jac lsp` for hover info at `line`/`column` (same 1-based convention
`get_completions` uses, converted to LSP's 0-based `line`/`character` at the boundary). Returns
the hover text as a plain string (or `None` for "no hover info here," e.g. whitespace or a token
`jac lsp` couldn't resolve a symbol for) -- `get_node_info`'s own output (confirmed against
`engine.impl.jac`) is already a small, human-readable summary, not structured data worth a richer
shape."""
async def:pub get_hover(path: str, content: str, line: int, column: int) -> str | None {
    if not _is_jac_file(path) {
        return None;
    }
    handle = await _ensure_process();
    if handle is None {
        return None;
    }
    await _sync_content(handle, path, content);
    result = await _send_request(handle, "textDocument/hover", {
        "textDocument": {"uri": _path_to_uri(path)},
        "position": {"line": line - 1, "character": column - 1}
    });
    if result is None or not isinstance(result, dict) {
        return None;
    }
    return _extract_hover_text(result.get("contents"));
}

"""A second pure, testable step, the `get_definition`/`get_references` counterpart to
`_extract_hover_text` above -- converts one raw LSP `Location` (`{uri, range}`) into this project's
own `(path, line, column)` shape (`_uri_to_path`, plus the 0-based-to-1-based conversion every other
public entry point in this module already does at its own boundary), or `None` for a malformed/empty
`Location` (defensive against a genuinely absent `uri`, not a case `jac lsp` is known to send)."""
def:pub _lsp_location_to_dict(location: any) -> dict[str, any] | None {
    if not isinstance(location, dict) {
        return None;
    }
    uri = location.get("uri", "");
    if uri == "" {
        return None;
    }
    range_start = location.get("range", {}).get("start", {});
    return {
        "path": _uri_to_path(uri),
        "line": int(range_start.get("line", 0)) + 1,
        "column": int(range_start.get("character", 0)) + 1
    };
}

"""Syncs `content`, then asks `jac lsp` where `line`/`column`'s symbol is defined -- `get_definition`
(`engine.impl.jac`) returns at most one `Location` (never a list, unlike `get_references` below), so
this mirrors that shape: one `{path, line, column}` dict, or `None` for "nothing resolvable here"
(whitespace, a token with no symbol, `jac lsp` couldn't determine a definition)."""
async def:pub get_definition(path: str, content: str, line: int, column: int) -> dict[str, any] | None {
    if not _is_jac_file(path) {
        return None;
    }
    handle = await _ensure_process();
    if handle is None {
        return None;
    }
    await _sync_content(handle, path, content);
    result = await _send_request(handle, "textDocument/definition", {
        "textDocument": {"uri": _path_to_uri(path)},
        "position": {"line": line - 1, "character": column - 1}
    });
    if result is None {
        return None;
    }
    return _lsp_location_to_dict(result);
}

"""Syncs `content`, then asks `jac lsp` for every reference to the symbol at `line`/`column` --
`get_references` (`engine.impl.jac`) always returns a plain `list[Location]`, never `None`, unlike
`get_definition`'s `Optional[Location]` above -- this mirrors that with an empty list for "nothing
found," not `None`. That list already includes the symbol's own declaration (`[*node_selected.sym.
defn, *node_selected.sym.uses]`, confirmed against the server source), matching real "Find All
References" convention, where the declaration itself is one of the listed references."""
async def:pub get_references(path: str, content: str, line: int, column: int) -> list[dict[str, any]] {
    if not _is_jac_file(path) {
        return [];
    }
    handle = await _ensure_process();
    if handle is None {
        return [];
    }
    await _sync_content(handle, path, content);
    result = await _send_request(handle, "textDocument/references", {
        "textDocument": {"uri": _path_to_uri(path)},
        "position": {"line": line - 1, "character": column - 1},
        "context": {"includeDeclaration": True}
    });
    if not isinstance(result, list) {
        return [];
    }
    locations = [];
    for loc in result {
        parsed = _lsp_location_to_dict(loc);
        if parsed is not None {
            locations.append(parsed);
        }
    }
    return locations;
}

"""A third pure, testable conversion step, alongside `_extract_hover_text` and
`_lsp_location_to_dict` -- converts one raw LSP `WorkspaceEdit` (`{changes: {uri: [TextEdit]}}`)
into a flat list of `{path, startLine, startColumn, endLine, endColumn, newText}` dicts (1-based,
`_uri_to_path` applied per-file). Flat rather than the LSP shape's own per-file grouping because
every real caller (`jac_rename_provider.jac`) wants to re-group by *Monaco model existence*, not by
file -- a flat list is the more useful intermediate shape, not a lossy simplification."""
def:pub _lsp_workspace_edit_to_list(workspace_edit: any) -> list[dict[str, any]] {
    if not isinstance(workspace_edit, dict) {
        return [];
    }
    changes = workspace_edit.get("changes", {});
    if not isinstance(changes, dict) {
        return [];
    }
    edits = [];
    for (uri, text_edits) in changes.items() {
        if not isinstance(text_edits, list) {
            continue;
        }
        path = _uri_to_path(uri);
        for text_edit in text_edits {
            range_ = text_edit.get("range", {});
            start = range_.get("start", {});
            end = range_.get("end", {});
            edits.append({
                "path": path,
                "startLine": int(start.get("line", 0)) + 1,
                "startColumn": int(start.get("character", 0)) + 1,
                "endLine": int(end.get("line", 0)) + 1,
                "endColumn": int(end.get("character", 0)) + 1,
                "newText": text_edit.get("newText", "")
            });
        }
    }
    return edits;
}

"""Converts a 1-based `(line, column)` position into an absolute character offset into `content` --
the shared unit `_apply_text_edits` below applies every edit in, rather than working line-by-line
directly (line-by-line application has to reason about which edits share a line and in what order;
offset-based splicing sidesteps that once every edit is expressed the same way)."""
def _line_col_to_offset(content: str, line: int, column: int) -> int {
    lines = content.split("\n");
    offset = 0;
    for i in range(line - 1) {
        offset += len(lines[i]) + 1;
    }
    return offset + column - 1;
}

"""Applies a group of this module's own `(startLine, startColumn, endLine, endColumn, newText)`
edits (all for the same file) to that file's raw content, purely as string manipulation -- the
counterpart to Monaco's own `model.pushEditOperations` for a rename target with no live Monaco
model (see `jac_rename_provider.jac`'s docstring for why that split exists at all). Every edit's
position is computed by `jac lsp` against the *original*, pre-rename document, so edits are
resolved to absolute offsets and applied back-to-front (descending by start offset) -- applying
them in document order would let an earlier edit's splice shift a later edit's still-unprocessed
offset out from under it, the identical reason Monaco's own bulk-edit service always computes a
model's edits as one batch against its pre-edit state rather than replaying them one at a time."""
def:pub _apply_text_edits(content: str, edits: list[dict[str, any]]) -> str {
    resolved = [
        {
            "start": _line_col_to_offset(content, e["startLine"], e["startColumn"]),
            "end": _line_col_to_offset(content, e["endLine"], e["endColumn"]),
            "newText": e["newText"]
        }
        for e in edits
    ];
    resolved = sorted(resolved, key=lambda (r: dict[str, any]) { r["start"]; }, reverse=True);
    result = content;
    for r in resolved {
        start = r["start"] as int;
        end = r["end"] as int;
        result = result[:start] + (r["newText"] as str) + result[end:];
    }
    return result;
}

"""Applies `edits` (this module's own shape, all for `path`) directly to `path` on disk -- for a
rename target `jac_rename_provider.jac` found has no open tab (no live Monaco model to mutate), so
there is no in-memory buffer to apply against or dirty-mark; this re-reads whatever's currently on
disk, applies the edits, and writes the result straight back with `save_document`. Trusts the
caller already confirmed no open model holds this path -- checking that is the client's job (it can
query `monaco.editor.getModel` directly), not this function's."""
async def:pub apply_disk_rename_edits(path: str, edits: list[dict[str, any]]) -> None {
    loaded = open_document(path);
    new_content = _apply_text_edits(loaded["content"], edits);
    save_document(path, new_content);
}

"""Syncs `content`, then asks `jac lsp` to rename the symbol at `line`/`column` to `new_name` --
`rename_symbol` (`engine.impl.jac`) returns `Optional[WorkspaceEdit]`, `None` when nothing at that
position resolves to a renameable symbol; this mirrors that with an empty edit list rather than
`None`; every caller in this project already treats "no edits" and "nothing renameable" the same
way (a no-op), so there's no information lost collapsing the two."""
async def:pub get_rename_edits(path: str, content: str, line: int, column: int, new_name: str) -> list[dict[str, any]] {
    if not _is_jac_file(path) {
        return [];
    }
    handle = await _ensure_process();
    if handle is None {
        return [];
    }
    await _sync_content(handle, path, content);
    result = await _send_request(handle, "textDocument/rename", {
        "textDocument": {"uri": _path_to_uri(path)},
        "position": {"line": line - 1, "character": column - 1},
        "newName": new_name
    });
    return _lsp_workspace_edit_to_list(result);
}

"""Recursively converts `jac lsp`'s hierarchical `DocumentSymbol[]` (`{name, kind, range,
selectionRange, children}`, confirmed against `utils.impl.jac`'s `get_symbols_for_outline`) into
this project's own nested shape, 1-based, carrying *both* ranges rather than picking one: `line`/
`column` come from `selectionRange` (the symbol's own name-token span -- `outline.jac`'s
click-to-jump wants "put the cursor on this symbol's name," the same thing `_lsp_location_to_dict`
already does for go-to-definition, not "select this symbol's entire body"), while `startLine`/
`startColumn`/`endLine`/`endColumn` come from the broader `range` (the symbol's whole body) --
`symbol_path_at_position` below needs that wider span to test whether a cursor position falls
*inside* a symbol, which its name token alone can't answer. `children` recurses through the
identical conversion rather than being left as raw LSP dicts, so a consumer never has to know the
wire shape past this one boundary function."""
def:pub _lsp_document_symbols_to_list(symbols: any) -> list[dict[str, any]] {
    if not isinstance(symbols, list) {
        return [];
    }
    result = [];
    for sym in symbols {
        if not isinstance(sym, dict) {
            continue;
        }
        body_range = sym.get("range", {});
        body_start = body_range.get("start", {});
        body_end = body_range.get("end", {});
        selection_range = sym.get("selectionRange", {});
        sel_start = selection_range.get("start", {});
        result.append({
            "name": sym.get("name", ""),
            "kind": sym.get("kind", 0),
            "line": int(sel_start.get("line", 0)) + 1,
            "column": int(sel_start.get("character", 0)) + 1,
            "startLine": int(body_start.get("line", 0)) + 1,
            "startColumn": int(body_start.get("character", 0)) + 1,
            "endLine": int(body_end.get("line", 0)) + 1,
            "endColumn": int(body_end.get("character", 0)) + 1,
            "children": _lsp_document_symbols_to_list(sym.get("children") or [])
        });
    }
    return result;
}

"""Syncs `content`, then asks `jac lsp` for `path`'s symbol outline -- the data source for both
`outline.jac` and `monaco_editor.jac`'s breadcrumb bar (`symbol_path_at_position` above tracks
which symbol currently contains the cursor from this same tree). `get_outline` (`engine.impl.jac`)
always returns a plain list, never `None`, so this mirrors that with an empty list rather than
`None` for "no symbols" (an empty file, or one `jac lsp` hasn't type-checked)."""
async def:pub get_document_symbols(path: str, content: str) -> list[dict[str, any]] {
    if not _is_jac_file(path) {
        return [];
    }
    handle = await _ensure_process();
    if handle is None {
        return [];
    }
    await _sync_content(handle, path, content);
    result = await _send_request(handle, "textDocument/documentSymbol", {
        "textDocument": {"uri": _path_to_uri(path)}
    });
    return _lsp_document_symbols_to_list(result);
}

"""Syncs `content`, then asks for completions at `line`/`column` (1-based, matching this project's
own convention everywhere else -- `handle_cursor_change`, `get_line_changes`, ... -- converted to
LSP's 0-based `line`/`character` at the boundary). Returns a small, client-friendly shape
(`label`/`kind`/`detail`/`insertText`), not the raw LSP `CompletionItem`/`CompletionList` -- the
client-side provider (`jac_completion_provider.jac`) maps `kind` onto Monaco's own differently-
numbered `CompletionItemKind` enum, so translating the LSP integer here would just move that mapping
without simplifying anything."""
async def:pub get_completions(path: str, content: str, line: int, column: int) -> list[dict[str, any]] {
    if not _is_jac_file(path) {
        return [];
    }
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
