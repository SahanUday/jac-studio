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

"""Regression test for the real, live-reproduced crash (`2026-09-04-list-children-by-path-crashes-
on-unexpected-contains-target`): a `Workspace` object turning up where a `Contains`-edge target
should only ever be a `Folder`/`File` used to raise `AttributeError: 'Workspace' object has no
attribute 'path'` and take the whole call down. The real trigger (some interleaving of concurrent
requests around `get_or_create_workspace`) wasn't reproducible under `jac test`'s synchronous
execution -- this constructs the *symptom* directly instead, the same way the duplicate-File test
above constructs its own symptom rather than the race that would naturally produce it."""
test "list_children_by_path skips a Contains target that isn't a Folder or File, rather than crashing" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    ws = get_or_create_workspace(fixture);
    ws +>:Contains():+> Workspace(root_path="/somewhere/else");
    ws +>:Contains():+> File(name="a.txt", path=os.path.join(fixture, "a.txt"));
    ws.scanned = True;

    children = list_children_by_path(fixture);

    assert [c["name"] for c in children] == ["a.txt"];
}

test "get_current_workspace returns None when nothing has ever been opened" {
    _reset_workspace_cache_for_tests();

    assert get_current_workspace() is None;
}

test "get_current_workspace returns the previously opened workspace" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    result = get_current_workspace();

    assert result is not None;
    assert result["root_path"] == fixture;
    assert result["name"] == os.path.basename(fixture);
}

test "get_current_workspace re-populates the path index so list_children_by_path works after restore" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    # simulate a fresh page load: the cache is cleared, but the graph itself still holds the
    # previously created Workspace node (as it would across a real process restart)
    _cached_workspace_jid.clear();
    _path_index.clear();

    restored = get_current_workspace();
    children = list_children_by_path(restored["root_path"]);

    assert [c["name"] for c in children] == ["sub", "a.txt"];
}

test "a no-op get_current_workspace call in between does not wipe an already-expanded folder's children" {
    # Regression test for a real, reported bug: every SCM function (get_scm_status,
    # get_diff_content, ...) calls get_current_workspace -> get_or_create_workspace first, purely
    # to resolve the repo root, with no intent to change or reset anything. get_or_create_workspace
    # used to unconditionally overwrite _path_index[key] with a fresh single-entry dict on *every*
    # call, even when root_path hadn't changed -- discarding every previously cached Folder/File
    # entry (list_children_by_path's own doc). Since list_children_by_path returns [] immediately
    # when parent_path isn't in _path_index[key] (never even reaching the graph), simply having the
    # SCM panel open -- or opening a diff view -- silently emptied out every already-expanded
    # folder in the Explorer, even though the underlying graph (Folder node, scanned flag, Contains
    # edges) was never touched.
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);
    sub_path = os.path.join(fixture, "sub");
    list_children_by_path(sub_path);

    # simulates an SCM-panel-shaped call: resolves the current workspace, same as
    # get_scm_status/get_diff_content do via git_service.jac's _repo_root(), with no path change
    get_current_workspace();

    sub_children_again = list_children_by_path(sub_path);

    assert [c["name"] for c in sub_children_again] == ["nested", "b.txt"];
}

test "list_all_files returns nothing when no workspace has ever been opened" {
    _reset_workspace_cache_for_tests();

    assert list_all_files() == [];
}

test "list_all_files finds every file in the whole tree, not just the top level" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    files = list_all_files();

    names = sorted([f["name"] for f in files]);
    assert names == ["a.txt", "b.txt", "c.txt"];
}

test "list_all_files excludes node_modules without walking into it" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    files = list_all_files();

    assert "ignored.txt" not in [f["name"] for f in files];
}

test "list_all_files does not require any prior list_children_by_path scan" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    # unlike list_children_by_path, list_all_files walks the filesystem directly -- it must not
    # depend on _path_index having been populated by a prior expand-click
    files = list_all_files();

    assert len(files) == 3;
}

test "list_all_files reflects files added after the workspace was opened (no stale scanned flag)" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_all_files();

    with open(os.path.join(fixture, "new_after_scan.txt"), "w") as f {
        f.write("late");
    }

    files = list_all_files();
    assert "new_after_scan.txt" in [f["name"] for f in files];
}

"""Regression test for `2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache`: a cross-module
`def:pub` call (`search_service.jac`'s `search_in_files` calling this module's `list_all_files`)
saw an empty `_cached_workspace_jid`, even though `open_workspace` had genuinely just populated it
in the same request session and `jid(root)` was confirmed identical across both call paths. This
test can't reproduce the cross-module call itself (that only manifests over a real HTTP round trip,
not within one `jac test` process -- see the tracker entry), but it does directly exercise the fix:
`list_all_files` must not go blind just because its own module-level cache dict happens to be
empty, as long as the graph still has a real `Workspace` node to fall back to."""
test "list_all_files falls back to a graph query and still works when its own cache is empty" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_all_files();

    # Simulate exactly the bug's observed symptom directly: jid(root) unchanged, but the
    # module-level cache dict that list_all_files reads from is empty -- the Workspace node itself
    # is untouched in the graph, only the cache is cleared.
    _cached_workspace_jid.clear();

    files = list_all_files();

    assert len(files) == 3;
}

test "create_file makes a real empty file on disk and it appears in the listing" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    result = create_file(fixture, "new.txt");

    new_path = os.path.join(fixture, "new.txt");
    assert result == {"name": "new.txt", "path": new_path, "is_dir": False};
    assert os.path.isfile(new_path);
    children = list_children_by_path(fixture);
    assert "new.txt" in [c["name"] for c in children];
}

test "create_file scans an unexpanded parent first, so no duplicate node is created later" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    # deliberately never call list_children_by_path(fixture) before creating -- the parent has
    # never been scanned yet

    create_file(fixture, "new.txt");

    children = list_children_by_path(fixture);
    matching = [c for c in children if c["name"] == "a.txt"];
    assert len(matching) == 1;
}

test "create_file refuses to overwrite an existing file" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    with testraises(ValueError) {
        create_file(fixture, "a.txt");
    }
}

test "create_folder makes a real directory and it appears in the listing" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    result = create_folder(fixture, "new_dir");

    new_path = os.path.join(fixture, "new_dir");
    assert result == {"name": "new_dir", "path": new_path, "is_dir": True};
    assert os.path.isdir(new_path);
    children = list_children_by_path(fixture);
    assert "new_dir" in [c["name"] for c in children];
}

test "create_folder's new folder lists empty without a filesystem scan" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);
    create_folder(fixture, "new_dir");

    children = list_children_by_path(os.path.join(fixture, "new_dir"));

    assert children == [];
}

test "rename_path renames a file on disk and updates the tree" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    old_path = os.path.join(fixture, "a.txt");
    result = rename_path(old_path, "renamed.txt");

    new_path = os.path.join(fixture, "renamed.txt");
    assert result == {"name": "renamed.txt", "path": new_path, "is_dir": False};
    assert not os.path.exists(old_path);
    assert os.path.isfile(new_path);
    children = list_children_by_path(fixture);
    names = [c["name"] for c in children];
    assert "renamed.txt" in names;
    assert "a.txt" not in names;
}

test "rename_path on a folder detaches its scanned children rather than rewriting their paths" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);
    sub_path = os.path.join(fixture, "sub");
    list_children_by_path(sub_path);  # scan "sub" so it has children attached

    result = rename_path(sub_path, "renamed_sub");

    renamed_path = os.path.join(fixture, "renamed_sub");
    assert result["path"] == renamed_path;
    # the renamed folder must be re-scanned from scratch, not show stale pre-rename children
    children = list_children_by_path(renamed_path);
    assert [c["name"] for c in children] == ["nested", "b.txt"];
}

test "rename_path refuses to rename onto an existing path" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    with testraises(ValueError) {
        rename_path(os.path.join(fixture, "a.txt"), "sub");
    }
}

test "delete_path removes a file from disk and from the listing" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);

    target = os.path.join(fixture, "a.txt");
    delete_path(target);

    assert not os.path.exists(target);
    children = list_children_by_path(fixture);
    assert "a.txt" not in [c["name"] for c in children];
}

test "delete_path removes a folder and its contents recursively" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    list_children_by_path(fixture);
    sub_path = os.path.join(fixture, "sub");
    list_children_by_path(sub_path);

    delete_path(sub_path);

    assert not os.path.exists(sub_path);
    children = list_children_by_path(fixture);
    assert "sub" not in [c["name"] for c in children];
}

test "delete_path on an unscanned path is a safe no-op" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    delete_path(os.path.join(fixture, "never-scanned.txt"));
}

test "ensure_path_reachable scans every ancestor and resolves a never-clicked nested file" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    target = os.path.join(fixture, "sub", "nested", "c.txt");
    found = ensure_path_reachable(target);

    assert found is not None;
    assert found.name == "c.txt";
    assert found.path == target;
    # now reachable without any further scan, via the ordinary lazy-scan path
    assert [c["name"] for c in list_children_by_path(os.path.join(fixture, "sub", "nested"))] == ["c.txt"];
}

test "ensure_path_reachable returns None for a path outside the open workspace" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);
    outside = tempfile.mkdtemp();
    with open(os.path.join(outside, "unrelated.txt"), "w") as f {
        f.write("x");
    }

    assert ensure_path_reachable(os.path.join(outside, "unrelated.txt")) is None;
}

test "ensure_path_reachable returns None for the workspace root itself" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    assert ensure_path_reachable(fixture) is None;
}

test "ensure_path_reachable returns None for a path that doesn't exist on disk" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    assert ensure_path_reachable(os.path.join(fixture, "does-not-exist.txt")) is None;
}

test "ensure_path_reachable returns None when no workspace is open" {
    _reset_workspace_cache_for_tests();

    assert ensure_path_reachable("/tmp/whatever.txt") is None;
}

"""Regression test for the cross-module `def:pub` cache-miss bug
(`2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache`), which the tracker entry's own "what
to check next" note predicted would hit the task runner -- confirmed live, then fixed here the same
way `list_all_files` already was. Directly clears `_cached_workspace_jid` after a real
`open_workspace` call to simulate what a cross-module caller apparently observes, without needing an
actual second module or a real HTTP round trip to reproduce; confirmed this test fails against the
pre-fix version (the unconditional `if key not in _cached_workspace_jid { return None; }` early
return) by temporarily reverting the fix and re-running it."""
test "ensure_path_reachable falls back to a graph query and still works when its own cache is empty" {
    _reset_workspace_cache_for_tests();
    fixture = make_fixture();
    open_workspace(fixture);

    # Simulate the bug's observed symptom directly: jid(root) unchanged, but the module-level
    # cache dict this function reads from is empty -- the Workspace node itself is untouched.
    _cached_workspace_jid.clear();

    found = ensure_path_reachable(os.path.join(fixture, "sub", "b.txt"));

    assert found is not None;
    assert found.name == "b.txt";
}
