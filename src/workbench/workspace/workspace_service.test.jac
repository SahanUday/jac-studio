"""Correctness tests against a small, deterministic synthetic fixture -- see
`internal/workspace-graph-spike/tests/workspace_graph_tests.jac` for the shared fixture shape this
mirrors. Unlike the spike, everything here goes through the two client-facing functions
(`open_workspace`, `list_children_by_path`) and asserts the lazy-scan contract: a path that hasn't
been listed yet returns nothing, listing a folder scans exactly one level (not its descendants),
and re-listing an already-scanned folder doesn't rescan or duplicate children."""

import os;
import tempfile;

"""Builds a fixture directory tree:
fixture_root/
  a.txt
  sub/
    b.txt
    nested/
      c.txt
  node_modules/
    ignored.txt
"""
def make_fixture -> str {
    fixture_root = tempfile.mkdtemp();
    with open(os.path.join(fixture_root, "a.txt"), "w") as f {
        f.write("a");
    }
    os.makedirs(os.path.join(fixture_root, "sub", "nested"));
    with open(os.path.join(fixture_root, "sub", "b.txt"), "w") as f {
        f.write("b");
    }
    with open(os.path.join(fixture_root, "sub", "nested", "c.txt"), "w") as f {
        f.write("c");
    }
    os.makedirs(os.path.join(fixture_root, "node_modules"));
    with open(os.path.join(fixture_root, "node_modules", "ignored.txt"), "w") as f {
        f.write("ignored");
    }
    return fixture_root;
}

test "open_workspace returns the root path and its basename as the display name" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();

    result = open_workspace(fixture);

    assert result["root_path"] == fixture;
    assert result["name"] == os.path.basename(fixture);
}

test "list_children_by_path on an unopened path returns nothing" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();

    children = list_children_by_path(fixture);

    assert children == [];
}

test "list_children_by_path on the workspace root lists direct children only, folders first" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    children = list_children_by_path(fixture);

    assert [c["name"] for c in children] == ["sub", "a.txt"];
    assert children[0]["is_dir"] == True;
    assert children[1]["is_dir"] == False;
}

test "node_modules is excluded from the listing" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    children = list_children_by_path(fixture);

    assert "node_modules" not in [c["name"] for c in children];
}

test "expanding a subfolder lists only its own children, not the whole subtree" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    sub_path = os.path.join(fixture, "sub");
    sub_children = list_children_by_path(sub_path);

    assert [c["name"] for c in sub_children] == ["nested", "b.txt"];
}

test "a folder two levels deep is only reachable after its parent has been listed" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    sub_path = os.path.join(fixture, "sub");
    nested_path = os.path.join(sub_path, "nested");

    # not reachable yet -- "sub" has been scanned, but "nested" itself hasn't been listed
    assert list_children_by_path(nested_path) == [];

    list_children_by_path(sub_path);
    nested_children = list_children_by_path(nested_path);
    assert [c["name"] for c in nested_children] == ["c.txt"];
}

test "listing an already-scanned folder again does not duplicate children" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    first = list_children_by_path(fixture);
    second = list_children_by_path(fixture);

    assert first == second;
}

test "re-listing after scanning does not touch the filesystem again (scanned flag holds)" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    # add a new file after the initial scan -- a real rescan would pick it up, the lazy
    # contract says it must not, since the folder is already marked scanned
    with open(os.path.join(fixture, "new_after_scan.txt"), "w") as f {
        f.write("late");
    }

    children = list_children_by_path(fixture);
    assert "new_after_scan.txt" not in [c["name"] for c in children];
}

"""Directly manufactures the duplicate-node graph state that the commit-timing race described in
`_workspace_lock`'s docstring can leave behind, bypassing the normal scan path so this test
exercises `list_children_by_path`'s read-side dedup itself rather than the lock that fails to
prevent the duplicate in the first place."""
test "list_children_by_path collapses two File nodes sharing one path into one entry" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    ws = get_or_create_workspace(fixture);
    dup_path = os.path.join(fixture, "a.txt");
    ws +>:Contains():+> File(name="a.txt", path=dup_path);
    ws +>:Contains():+> File(name="a.txt", path=dup_path);
    ws.scanned = True;

    children = list_children_by_path(fixture);

    matching = [c for c in children if c["path"] == dup_path];
    assert len(matching) == 1;
}
