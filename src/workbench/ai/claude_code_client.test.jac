"""Exercises the pure, stateless pieces only (`_pick_python_binary`). `start_chat_turn`'s real
subprocess/network/credential path isn't testable here; verified live instead, see trackers
`2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure` and
`2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run`.
"""

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
