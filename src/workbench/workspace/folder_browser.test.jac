import os;
import tempfile;

def make_tree -> str {
    base = tempfile.mkdtemp();
    os.makedirs(os.path.join(base, "beta"));
    os.makedirs(os.path.join(base, "Alpha"));
    os.makedirs(os.path.join(base, ".hidden"));
    with open(os.path.join(base, "file.txt"), "w") as f {
        f.write("x");
    }
    return base;
}

test "list_directories returns only directories, sorted case-insensitively, hiding dotfolders" {
    base = make_tree();
    result = list_directories(base, False);
    assert result["path"] == base;
    assert [e["name"] for e in result["entries"]] == ["Alpha", "beta"];
    assert result["entries"][0]["path"] == os.path.join(base, "Alpha");
    assert result["parent"] == os.path.dirname(base);
    assert result["error"] == "";
}

test "list_directories shows dotfolders when asked" {
    base = make_tree();
    names = [e["name"] for e in list_directories(base, True)["entries"]];
    assert ".hidden" in names;
}

test "a missing path lands on its nearest existing ancestor" {
    base = make_tree();
    result = list_directories(os.path.join(base, "beta", "nope", "deeper"), False);
    assert result["path"] == os.path.join(base, "beta");
}

test "an empty path starts at the home directory and the filesystem root has no parent" {
    assert list_directories("", False)["path"] == os.path.expanduser("~");
    assert list_directories("/", False)["parent"] == "";
}
