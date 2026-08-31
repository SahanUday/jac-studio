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
