glob LISTINGS: dict[str, list[dict[str, any]]] = {
    "/w": [
        {"name": "src", "path": "/w/src", "is_dir": True},
        {"name": "a.txt", "path": "/w/a.txt", "is_dir": False}
    ],
    "/w/src": [{"name": "b.jac", "path": "/w/src/b.jac", "is_dir": False}]
};

test "with nothing selected the target is the workspace root" {
    assert target_directory("", "/w", LISTINGS) == "/w";
}

test "a selected folder is its own target" {
    assert target_directory("/w/src", "/w", LISTINGS) == "/w/src";
}

test "a selected file targets its parent folder, at any depth" {
    assert target_directory("/w/a.txt", "/w", LISTINGS) == "/w";
    assert target_directory("/w/src/b.jac", "/w", LISTINGS) == "/w/src";
}

test "a selection the tree no longer lists falls back to the root" {
    assert target_directory("/w/gone.txt", "/w", LISTINGS) == "/w";
    assert target_directory("/w/src", "/w", {}) == "/w";
}
