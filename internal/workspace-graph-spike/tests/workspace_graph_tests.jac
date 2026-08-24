"""Correctness tests against a small, deterministic synthetic fixture (not a real directory --
real-directory contents change over time, which would make hardcoded node-count assertions
brittle). Scale/performance findings against real directories are measured manually via main.jac
and recorded in README.md instead."""

import os;
import tempfile;
import from src.workspace_graph {
    get_or_create_workspace, _reset_workspace_cache_for_tests,
    scan_directory, list_children, count_subtree, find_by_path, Folder, File
}

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

test "scan_directory builds the full tree, excluding node_modules" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    ws = get_or_create_workspace(root_path=fixture);

    (folders, files) = scan_directory(ws, fixture);

    # sub, sub/nested -- node_modules excluded
    assert folders == 2;
    # a.txt, sub/b.txt, sub/nested/c.txt -- node_modules/ignored.txt excluded
    assert files == 3;
}

test "get_or_create_workspace is idempotent" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    first = get_or_create_workspace(root_path=fixture);
    second = get_or_create_workspace(root_path=fixture);
    assert first == second;
}

test "list_children returns direct children only" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    ws = get_or_create_workspace(root_path=fixture);
    scan_directory(ws, fixture);

    children = list_children(ws);
    names = sorted([c.name for c in children]);
    assert names == ["a.txt", "sub"];
}

test "count_subtree matches scan_directory's own counts" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    ws = get_or_create_workspace(root_path=fixture);
    (scanned_folders, scanned_files) = scan_directory(ws, fixture);

    (counted_folders, counted_files) = count_subtree(ws);

    assert counted_folders == scanned_folders;
    assert counted_files == scanned_files;
}

test "find_by_path locates a deeply nested file" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    ws = get_or_create_workspace(root_path=fixture);
    scan_directory(ws, fixture);

    target = os.path.join(fixture, "sub", "nested", "c.txt");
    found = find_by_path(ws, target);

    assert found is not None;
    assert isinstance(found, File);
    assert found.name == "c.txt";
}

test "find_by_path returns None for a path that was never scanned (node_modules)" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    ws = get_or_create_workspace(root_path=fixture);
    scan_directory(ws, fixture);

    target = os.path.join(fixture, "node_modules", "ignored.txt");
    found = find_by_path(ws, target);

    assert found is None;
}

test "a Folder found by find_by_path exposes its own children via list_children" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    ws = get_or_create_workspace(root_path=fixture);
    scan_directory(ws, fixture);

    sub_path = os.path.join(fixture, "sub");
    sub_folder = find_by_path(ws, sub_path);

    assert sub_folder is not None;
    assert isinstance(sub_folder, Folder);
    names = sorted([c.name for c in list_children(sub_folder)]);
    assert names == ["b.txt", "nested"];
}
