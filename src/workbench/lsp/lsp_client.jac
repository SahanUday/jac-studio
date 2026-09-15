"""Client for `jac lsp`: `Content-Length`-framed JSON-RPC over stdio, one persistent process per
`jid(root)`, spawned lazily and kept alive so document-sync state survives between calls.
Entry points must stay `async def:pub` -- a plain sync `def:pub` runs on a throwaway worker-thread
event loop, so the background reader task created there dies with the request. Gated on
`[terminal] enabled` (`docs/architecture.md`'s shell-capability gate)."""

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

"""Every public entry point must guard on this -- `jac lsp` type-checks one file at a time, so
syncing non-`.jac` files starves out the requests that matter."""
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

"""Reads one `Content-Length`-framed message off `stream`; `None` means the stream closed cleanly."""
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

"""Runs in a background task with no request boundary, so jaseci's per-request auto-commit never
fires -- the explicit `Jac.acommit()` calls are load-bearing, and `Jac` must be imported (it is not
ambient the way `root`/`jid` are)."""
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

"""Resolves pending request futures and dispatches unsolicited notifications for the process's life."""
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

"""Spawns and initializes `jac lsp` lazily, or returns the running one; `None` (never raises) when
the gate is off or no workspace is open."""
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

"""Also how diagnostics refresh: `jac lsp`'s `did_save` handler re-runs `type_check`."""
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

"""Handles both shapes `Hover.contents` may take over the wire: `MarkupContent` and bare `MarkedString`."""
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

"""`line`/`column` are 1-based, converted to LSP's 0-based pair at the boundary."""
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

"""One LSP `Location` to this project's 1-based `{path, line, column}`; `None` if malformed."""
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

"""Includes the symbol's own declaration, matching "Find All References" convention."""
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

"""Flattens an LSP `WorkspaceEdit` into 1-based per-edit dicts -- callers re-group by Monaco model
existence, not by file."""
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

def _line_col_to_offset(content: str, line: int, column: int) -> int {
    lines = content.split("\n");
    offset = 0;
    for i in range(line - 1) {
        offset += len(lines[i]) + 1;
    }
    return offset + column - 1;
}

"""Edits carry positions against the *original* document, so they are applied back-to-front --
in document order an earlier splice would shift a later edit's offset out from under it."""
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

"""Writes straight to disk -- the caller must have confirmed no open Monaco model holds `path`."""
async def:pub apply_disk_rename_edits(path: str, edits: list[dict[str, any]]) -> None {
    loaded = open_document(path);
    new_content = _apply_text_edits(loaded["content"], edits);
    save_document(path, new_content);
}

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

"""Carries *both* LSP ranges: `line`/`column` from `selectionRange` (the name token, for
click-to-jump), `start*`/`end*` from `range` (the whole body, for cursor-containment tests)."""
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

"""`kind` stays the raw LSP integer -- `jac_completion_provider.jac` maps it onto Monaco's own enum."""
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
