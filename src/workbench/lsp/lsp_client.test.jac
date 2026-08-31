"""Exercises the pure, stateless pieces directly: URI<->path conversion and the `Content-Length`
message framing (encode + decode). **Deliberately does not exercise the actual subprocess lifecycle**
(`_ensure_process`, `_read_loop`, `notify_document_open`/`_save`, `get_completions`'s real request/
response round-trip) -- those require a real `jac lsp` child process and this repo's own `jac.toml`
ships `[terminal] enabled = false` (deny-by-default), the identical reason `terminal_service.jac`
and `task_service.jac`'s own subprocess-execution paths have no test coverage for their live
behavior either. That's verified live instead (`jac browse` against a real `jac run --serve --dev`
server with the flag temporarily flipped on, never committed that way) -- see the PR description.

`FakeStream` stands in for `asyncio.StreamReader`'s two methods `_read_message` actually calls
(`readline`, `readexactly`) -- a plain in-memory byte-queue `obj`, not a mock library, since the
real interface surface needed is this small.

**`asyncio.run(...)` through a local wrapper function, never a bare `await` inside a `test` block --
two real, confirmed jaclang bugs, not a style choice.** A literal `await` keyword anywhere inside a
`test` block fails bytecode compilation under `jac test` with `'await' outside async function` --
reproduced down to the minimal case (a `test` block awaiting nothing but a bare
`asyncio.sleep(...)`, no wrapping function at all) -- even though `jac check` accepts the identical
code with zero errors and the same `async def`-with-internal-`await` shape genuinely works
correctly once actually served (`terminal_service.jac`'s `run_in_terminal`, exercised live via the
integrated terminal across several earlier PRs). Separately, `asyncio.run(...)` called directly on
an *annex-scope* (or cross-module) async function's call expression trips a second, distinct
checker bug -- `jac check` infers that call's type as the function's plain declared return type
(e.g. `dict[str, Any] | None`) instead of `Coroutine[Any, Any, dict[str, Any] | None]`, so
`asyncio.run`'s own signature rejects it (E1053) even though the exact same pattern against a
function defined in the *same* file passes clean. `_wrap_read_message` below (a tiny local `async
def` that just `await`s `_read_message` and returns its result) sidesteps both bugs at once: no
bare `await` at the test-block boundary, and `asyncio.run` is now called on a *locally-defined*
async function, which the checker infers correctly. See tracker entry
`2026-08-31-await-inside-test-block-fails-bytecode-compilation` for the full isolation of both.

No `import from src.workbench.lsp.lsp_client { ... }` here -- this file is `lsp_client.jac`'s own
`.test.jac` annex, which already sees its declarations directly without importing them (the
established convention every other annex in this project follows); doing so anyway doesn't just
duplicate the binding, it can break an unrelated script's import elsewhere in the same session (see
`jac-language`'s own gotcha list, `2026-08-24-test-annex-self-import-breaks-unrelated-runs`)."""

import asyncio;

obj FakeStream {
    has chunks: list[bytes] = [];
    has idx: int = 0;

    async def readline -> bytes;
    async def readexactly(n: int) -> bytes;
}

impl FakeStream.readline -> bytes {
    if self.idx >= len(self.chunks) {
        return b"";
    }
    line = self.chunks[self.idx];
    self.idx += 1;
    return line;
}

impl FakeStream.readexactly(n: int) -> bytes {
    if self.idx >= len(self.chunks) {
        return b"";
    }
    chunk = self.chunks[self.idx];
    self.idx += 1;
    return chunk;
}

async def _wrap_read_message(stream: any) -> dict[str, any] | None {
    return await _read_message(stream);
}

test "_is_jac_file accepts a real .jac path" {
    assert _is_jac_file("/home/user/project/main.jac");
}

"""Regression test for a real, live-caught bug: `monaco_editor.jac` mounts for every open tab
regardless of file type, so without this guard, opening a `.txt`/`.py`/anything-else tab would sync
it to `jac lsp` too -- confirmed live to matter, not just theoretically wasteful: `jac lsp`'s own
dispatcher processes one type-check task at a time, so a backlog of pointless non-`.jac` type-checks
starved out the real `.jac` diagnostics this client exists to surface."""
test "_is_jac_file rejects non-.jac paths" {
    assert not _is_jac_file("/home/user/project/notes.txt");
    assert not _is_jac_file("/home/user/project/app.py");
    assert not _is_jac_file("/home/user/project/README");
}

test "_path_to_uri prefixes a real filesystem path with file://" {
    assert _path_to_uri("/home/user/project/main.jac") == "file:///home/user/project/main.jac";
}

test "_uri_to_path strips the file:// prefix" {
    assert _uri_to_path("file:///home/user/project/main.jac") == "/home/user/project/main.jac";
}

test "_uri_to_path passes through a URI with no file:// prefix unchanged" {
    assert _uri_to_path("untitled:Untitled-1") == "untitled:Untitled-1";
}

test "_path_to_uri and _uri_to_path round-trip a real path" {
    path = "/tmp/some/nested/path.jac";
    assert _uri_to_path(_path_to_uri(path)) == path;
}

test "_encode_message frames a JSON-RPC payload with a correct Content-Length header" {
    encoded = _encode_message({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}});

    (header, sep, body) = encoded.partition(b"\r\n\r\n");
    assert sep == b"\r\n\r\n";
    content_length = int(header.decode("ascii").split(":")[1].strip());
    assert content_length == len(body);
}

test "_read_message parses a single well-formed framed message back into its dict" {
    payload = {"jsonrpc": "2.0", "id": 7, "result": {"ok": True}};
    framed = _encode_message(payload);
    (header_bytes, sep, body) = framed.partition(b"\r\n\r\n");
    stream = FakeStream(chunks=[header_bytes + b"\r\n", b"\r\n", body]);

    parsed = asyncio.run(_wrap_read_message(stream));

    assert parsed == payload;
}

test "_read_message returns None when the stream closes with nothing left to read" {
    stream = FakeStream(chunks=[]);

    assert asyncio.run(_wrap_read_message(stream)) is None;
}

"""`jac lsp`'s own `get_hover_info` always wraps its answer in `MarkupContent` (`{kind, value}`),
but `Hover.contents`'s declared wire type is the broader LSP union (`MarkupContent | MarkedString
| MarkedString[]`), and a plain string is exactly what a `MarkedString` looks like over JSON --
covering both shapes here rather than assuming only the one this particular server sends today."""
test "_extract_hover_text reads MarkupContent's value field" {
    assert _extract_hover_text({"kind": "plaintext", "value": "def foo() -> int"}) == "def foo() -> int";
}

test "_extract_hover_text returns None for MarkupContent with an empty value" {
    assert _extract_hover_text({"kind": "plaintext", "value": ""}) is None;
}

test "_extract_hover_text passes through a plain MarkedString" {
    assert _extract_hover_text("def foo() -> int") == "def foo() -> int";
}

test "_extract_hover_text returns None for an empty string" {
    assert _extract_hover_text("") is None;
}

test "_extract_hover_text returns None for an unrecognized shape" {
    assert _extract_hover_text(None) is None;
    assert _extract_hover_text(["def foo() -> int"]) is None;
}

"""`_lsp_location_to_dict` converts a raw LSP `Location` into `(path, line, column)`, applying the
same 0-based-to-1-based conversion at this boundary that every other public entry point in this
module applies at its own -- these two cases confirm both halves: the `file://` prefix strip and
the `+1` on both `line`/`character`."""
test "_lsp_location_to_dict converts a real Location to a 1-based (path, line, column)" {
    location = {
        "uri": "file:///home/user/project/main.jac",
        "range": {"start": {"line": 5, "character": 10}, "end": {"line": 5, "character": 16}}
    };
    assert _lsp_location_to_dict(location) == {"path": "/home/user/project/main.jac", "line": 6, "column": 11};
}

test "_lsp_location_to_dict converts a Location at the file's very first character" {
    location = {
        "uri": "file:///home/user/project/main.jac",
        "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 4}}
    };
    assert _lsp_location_to_dict(location) == {"path": "/home/user/project/main.jac", "line": 1, "column": 1};
}

test "_lsp_location_to_dict returns None for a Location with no uri" {
    assert _lsp_location_to_dict({"uri": "", "range": {}}) is None;
}

test "_lsp_location_to_dict returns None for a non-dict input" {
    assert _lsp_location_to_dict(None) is None;
    assert _lsp_location_to_dict("not a location") is None;
}

"""`_lsp_workspace_edit_to_list` flattens a `WorkspaceEdit`'s per-file `changes` map into a single
list of `{path, startLine, startColumn, endLine, endColumn, newText}` dicts -- covering the same
1-based conversion `_lsp_location_to_dict` applies, plus the multi-file, multi-edit-per-file case a
single `Location` never has to."""
test "_lsp_workspace_edit_to_list flattens a multi-file WorkspaceEdit into one list, 1-based" {
    workspace_edit = {
        "changes": {
            "file:///home/user/project/main.jac": [
                {"range": {"start": {"line": 0, "character": 5}, "end": {"line": 0, "character": 11}}, "newText": "Human"}
            ],
            "file:///home/user/project/helper.jac": [
                {"range": {"start": {"line": 2, "character": 20}, "end": {"line": 2, "character": 26}}, "newText": "Human"},
                {"range": {"start": {"line": 3, "character": 11}, "end": {"line": 3, "character": 17}}, "newText": "Human"}
            ]
        }
    };
    edits = _lsp_workspace_edit_to_list(workspace_edit);
    assert len(edits) == 3;
    assert {"path": "/home/user/project/main.jac", "startLine": 1, "startColumn": 6, "endLine": 1, "endColumn": 12, "newText": "Human"} in edits;
    assert {"path": "/home/user/project/helper.jac", "startLine": 3, "startColumn": 21, "endLine": 3, "endColumn": 27, "newText": "Human"} in edits;
    assert {"path": "/home/user/project/helper.jac", "startLine": 4, "startColumn": 12, "endLine": 4, "endColumn": 18, "newText": "Human"} in edits;
}

test "_lsp_workspace_edit_to_list returns an empty list for a None WorkspaceEdit" {
    assert _lsp_workspace_edit_to_list(None) == [];
}

test "_lsp_workspace_edit_to_list returns an empty list when changes is missing" {
    assert _lsp_workspace_edit_to_list({}) == [];
}

"""`_apply_text_edits` is what `apply_disk_rename_edits` uses to rename a symbol in a file with no
open Monaco model -- pure string splicing, no I/O, so it's tested directly against real multi-edit,
same-line and cross-line cases rather than only through a live subprocess round-trip."""
test "_apply_text_edits applies a single single-line edit" {
    content = "node Person {\n    has name: str;\n}\n";
    edits = [{"startLine": 1, "startColumn": 6, "endLine": 1, "endColumn": 12, "newText": "Human"}];
    assert _apply_text_edits(content, edits) == "node Human {\n    has name: str;\n}\n";
}

"""Two edits on the same line, applied together -- if these were applied in document order against
a mutating string instead of back-to-front, the second edit's column would land in the wrong place
once the first edit's replacement text (a different length than the original) shifted everything
after it."""
test "_apply_text_edits applies two edits on the same line without shifting the second's position" {
    content = "greet(p, p)\n";
    edits = [
        {"startLine": 1, "startColumn": 1, "endLine": 1, "endColumn": 6, "newText": "welcome"},
        {"startLine": 1, "startColumn": 10, "endLine": 1, "endColumn": 11, "newText": "person"}
    ];
    assert _apply_text_edits(content, edits) == "welcome(p, person)\n";
}

test "_apply_text_edits applies edits spanning multiple lines" {
    content = "def greet(p: Person) -> str {\n    return p\n}\n";
    edits = [
        {"startLine": 1, "startColumn": 14, "endLine": 1, "endColumn": 20, "newText": "Human"},
        {"startLine": 2, "startColumn": 12, "endLine": 2, "endColumn": 13, "newText": "person"}
    ];
    assert _apply_text_edits(content, edits) == "def greet(p: Human) -> str {\n    return person\n}\n";
}

test "_apply_text_edits with no edits returns the content unchanged" {
    content = "unchanged\n";
    assert _apply_text_edits(content, []) == content;
}
