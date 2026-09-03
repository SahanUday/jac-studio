"""Exercises the pure, stateless pieces directly -- the same scope `dap_client.test.jac` covers for
its own module, for the identical reason: the real subprocess lifecycle (`start_chat_turn` spawning
`claude_code_launcher.py`, a live `claude-agent-sdk` call) needs `[terminal] enabled = true`, a real
network call, and real credentials, none of which belong in an automated test run. That's verified
live instead -- see the isolation spike this module is built on
(tracker entries 2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure and
2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run) and the PR
description.

No `import from src.workbench.ai.claude_code_client { ... }` here -- this is that module's own
`.test.jac` annex, which already sees its declarations directly."""

test "_pick_python_binary picks the lexicographically first candidate, deterministically" {
    assert _pick_python_binary(["/x/bin/python3.14", "/x/bin/python3.9"]) == "/x/bin/python3.14";
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
