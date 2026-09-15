"""Exercises the pure, stateless pieces only, same scope as `lsp_client.test.jac`. Real subprocess
lifecycle (`_spawn_session`, a live `debugpy` handshake) needs `[terminal] enabled = true`; verified
live instead (PR description). `FakeStream`/`_wrap_read_message` duplicate `lsp_client.test.jac`'s
helpers rather than importing them -- see that file's docstring for the jaclang bugs they sidestep.
"""

import asyncio;
import os;

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

test "_pick_python_binary picks the lexicographically first candidate, deterministically" {
    assert _pick_python_binary(["/x/bin/python3.12", "/x/bin/python3.9"]) == "/x/bin/python3.12";
}

test "_pick_python_binary returns None for an empty candidate list" {
    assert _pick_python_binary([]) is None;
}

test "_build_pythonpath joins non-empty sys.path entries with the OS path separator" {
    result = _build_pythonpath(["/a", "", "/b/c", ""]);
    assert result == "/a" + os.pathsep + "/b/c";
}

test "_build_pythonpath returns an empty string for an all-empty sys.path" {
    assert _build_pythonpath(["", ""]) == "";
}

test "DAP request/response framing round-trips through the reused LSP Content-Length framer" {
    payload = {"seq": 3, "type": "request", "command": "attach", "arguments": {"justMyCode": False}};
    encoded = _encode_message(payload);

    (header, sep, body) = encoded.partition(b"\r\n\r\n");
    assert sep == b"\r\n\r\n";
    content_length = int(header.decode("ascii").split(":")[1].strip());
    assert content_length == len(body);

    stream = FakeStream(chunks=[header + b"\r\n", b"\r\n", body]);
    parsed = asyncio.run(_wrap_read_message(stream));
    assert parsed == payload;
}

test "_dap_stack_frames_from_response converts a real stackTrace response body" {
    response = {
        "success": True,
        "body": {
            "stackFrames": [
                {"id": 2, "name": "add", "line": 5, "source": {"path": "/tmp/hello.jac"}},
                {"id": 3, "name": "<module>", "line": 11, "source": {"path": "/tmp/hello.jac"}}
            ]
        }
    };
    frames = _dap_stack_frames_from_response(response);
    assert len(frames) == 2;
    assert frames[0] == {"id": 2, "name": "add", "line": 5, "path": "/tmp/hello.jac"};
    assert frames[1]["name"] == "<module>";
}

test "_dap_stack_frames_from_response returns an empty list for an unsuccessful response" {
    assert _dap_stack_frames_from_response({"success": False, "body": {}}) == [];
}

test "_dap_stack_frames_from_response returns an empty list for a None response" {
    assert _dap_stack_frames_from_response(None) == [];
}

test "_dap_top_scope_variables_reference reads the first scope's reference" {
    response = {"success": True, "body": {"scopes": [{"name": "Locals", "variablesReference": 5}, {"name": "Globals", "variablesReference": 6}]}};
    assert _dap_top_scope_variables_reference(response) == 5;
}

test "_dap_top_scope_variables_reference returns None when there are no scopes" {
    assert _dap_top_scope_variables_reference({"success": True, "body": {"scopes": []}}) is None;
}

test "_dap_top_scope_variables_reference returns None for an unsuccessful response" {
    assert _dap_top_scope_variables_reference({"success": False, "body": {}}) is None;
}

test "_dap_variables_from_response converts real Jac variable names and values" {
    response = {"success": True, "body": {"variables": [
        {"name": "a", "value": "2", "type": "int"},
        {"name": "total", "value": "5", "type": "int"}
    ]}};
    variables = _dap_variables_from_response(response);
    assert variables == [{"name": "a", "value": "2", "type": "int"}, {"name": "total", "value": "5", "type": "int"}];
}

test "_dap_variables_from_response returns an empty list for an unsuccessful response" {
    assert _dap_variables_from_response({"success": False, "body": {}}) == [];
}

test "get_breakpoints returns an empty list for a path with none stored" {
    _reset_dap_for_tests();
    assert get_breakpoints("/tmp/never-touched.jac") == [];
}
