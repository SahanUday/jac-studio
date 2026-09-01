"""Exercises `_find_conflict_hunks`, the one pure, Monaco-free piece of this module -- the same
scope every other provider's `.test.jac` annex covers for its own conversion helpers. Everything
else here (`_provide_code_lenses`, `_resolve_hunk`, the two `register*` calls) needs a real Monaco
`model`/`monaco` object and is verified live instead (`jac browse` against a real merge conflict in
`testing-workspace/` -- see the PR description)."""

test "finds a single well-formed conflict hunk" {
    lines = [
        "before",
        "<<<<<<< HEAD",
        "current line",
        "=======",
        "incoming line",
        ">>>>>>> feature",
        "after"
    ];

    hunks = _find_conflict_hunks(lines);

    assert hunks == [{"start": 1, "mid": 3, "end": 5}];
}

test "finds multiple hunks in the same file" {
    lines = [
        "<<<<<<< HEAD", "a", "=======", "b", ">>>>>>> feature",
        "middle",
        "<<<<<<< HEAD", "c", "=======", "d", ">>>>>>> feature"
    ];

    hunks = _find_conflict_hunks(lines);

    assert len(hunks) == 2;
    assert hunks[0] == {"start": 0, "mid": 2, "end": 4};
    assert hunks[1] == {"start": 6, "mid": 8, "end": 10};
}

test "a file with no conflict markers reports no hunks" {
    assert _find_conflict_hunks(["plain", "file", "content"]) == [];
}

test "an empty file reports no hunks" {
    assert _find_conflict_hunks([]) == [];
}

test "a hunk with no closing markers is skipped, not raised on" {
    lines = ["<<<<<<< HEAD", "dangling", "no markers after this"];

    assert _find_conflict_hunks(lines) == [];
}

test "a hunk missing only the closing >>>>>>> is skipped" {
    lines = ["<<<<<<< HEAD", "current", "=======", "incoming", "no closer here"];

    assert _find_conflict_hunks(lines) == [];
}

test "content between hunks that merely resembles a marker prefix does not confuse detection" {
    lines = [
        "<<<<<<< HEAD",
        "some line that is not a marker",
        "=======",
        "another normal line",
        ">>>>>>> feature"
    ];

    hunks = _find_conflict_hunks(lines);

    assert hunks == [{"start": 0, "mid": 2, "end": 4}];
}
