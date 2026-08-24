"""Direct server-side tests for `document_service.jac`, following the same pattern
`workspace_service.test.jac` established for the workspace graph: everything goes through the
client-facing functions (`open_document`, `apply_document_edit`, `close_document`) against a real
temp-file fixture, and asserts the per-path isolation the Tabs feature depends on -- editing one
open file must never touch another's buffer."""

import os;
import tempfile;

def make_fixture(content: str) -> str {
    fd_and_path = tempfile.mkstemp(suffix=".txt");
    path = fd_and_path[1];
    with open(path, "w") as f {
        f.write(content);
    }
    return path;
}

test "open_document reads a real file's content from disk, split into lines" {
    _reset_document_buffer_cache_for_tests();
    path = make_fixture("hello\nworld\n");

    result = open_document(path);

    assert result["path"] == path;
    assert result["name"] == os.path.basename(path);
    assert result["lines"] == ["hello", "world", ""];
}

test "open_document on a path with no file yet starts from empty content" {
    _reset_document_buffer_cache_for_tests();
    missing_path = os.path.join(tempfile.mkdtemp(), "not_on_disk.txt");

    result = open_document(missing_path);

    assert result["lines"] == [""];
}

test "apply_document_edit mutates only the buffer for its own path" {
    _reset_document_buffer_cache_for_tests();
    path_a = make_fixture("aaa\n");
    path_b = make_fixture("bbb\n");
    open_document(path_a);
    open_document(path_b);

    lines_a = apply_document_edit(path_a, 1, 1, 1, 1, "X");

    assert lines_a[0].startswith("Xaaa");
    lines_b = open_document(path_b)["lines"];
    assert lines_b[0] == "bbb";
}

test "re-opening an already-open path returns the live edited content, not a fresh disk read" {
    _reset_document_buffer_cache_for_tests();
    path = make_fixture("original\n");
    open_document(path);
    apply_document_edit(path, 1, 1, 1, 1, "X");

    result = open_document(path);

    assert result["lines"][0].startswith("Xoriginal");
}

test "close_document frees the buffer so a later open re-reads from disk" {
    _reset_document_buffer_cache_for_tests();
    path = make_fixture("original\n");
    open_document(path);
    apply_document_edit(path, 1, 1, 1, 1, "X");

    close_document(path);
    result = open_document(path);

    assert result["lines"][0] == "original";
}

test "close_document on a never-opened path is a no-op, not an error" {
    _reset_document_buffer_cache_for_tests();
    close_document("/nonexistent/path.txt");
}

test "apply_document_edit can insert a newline, splitting a line in two" {
    _reset_document_buffer_cache_for_tests();
    path = make_fixture("hello world\n");
    original_lines = open_document(path)["lines"];
    original_line_count = len(original_lines);
    original_first_line = original_lines[0];

    lines = apply_document_edit(path, 1, 6, 1, 6, "\n");

    assert len(lines) == original_line_count + 1;
    assert lines[0] == original_first_line[0:5];
    assert lines[1] == original_first_line[5:];
}
