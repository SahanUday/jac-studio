"""Direct server-side tests for the load/save `document_service.jac` -- see its docstring for why
this is now stateless (no buffer cache, no per-keystroke edit RPC) since Monaco owns live editing
entirely client-side."""

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

test "open_document reads a real file's content from disk" {
    path = make_fixture("hello\nworld\n");

    result = open_document(path);

    assert result["path"] == path;
    assert result["name"] == os.path.basename(path);
    assert result["content"] == "hello\nworld\n";
}

test "open_document on a path with no file yet starts from empty content" {
    missing_path = os.path.join(tempfile.mkdtemp(), "not_on_disk.txt");

    result = open_document(missing_path);

    assert result["content"] == "";
}

test "save_document writes content to disk, overwriting what was there" {
    path = make_fixture("original\n");

    save_document(path, "replaced\n");

    with open(path, "r") as f {
        assert f.read() == "replaced\n";
    }
}

test "a save followed by an open round-trips the exact content" {
    path = make_fixture("original\n");

    save_document(path, "line one\nline two\n");
    result = open_document(path);

    assert result["content"] == "line one\nline two\n";
}
