"""Real-scale measurement, run inside `test` blocks specifically for the fresh-graph-per-test
guarantee `jac-testing` documents -- repeated `jac run` CLI invocations were found to accumulate
state across invocations that `jac clean --data --force` did not reset (a separate tooling finding,
logged to the tracker), making `jac run` unsuitable for a trustworthy repeated measurement. A test
block sidesteps that entirely."""

import time;
import from src.workspace_graph { get_or_create_workspace, scan_directory, count_subtree, list_children, Folder }

def assert_no_duplicate_edges(parent: any, seen: set) {
    for child in list_children(parent) {
        assert child.path not in seen, f"duplicate path reached: {child.path}";
        seen.add(child.path);
        if isinstance(child, Folder) {
            assert_no_duplicate_edges(child, seen);
        }
    }
}

test "scale measurement: jac-studio's own repo (small project)" {
    target = "/home/sahan/dev/vs/jac-studio";
    ws = get_or_create_workspace(root_path=target);

    start = time.perf_counter();
    (folders, files) = scan_directory(ws, target);
    scan_ms = (time.perf_counter() - start) * 1000;

    start = time.perf_counter();
    (recount_folders, recount_files) = count_subtree(ws);
    count_ms = (time.perf_counter() - start) * 1000;

    print(f"\n=== jac-studio ({target}) ===");
    print(f"folders={folders} files={files} total={folders + files + 1}");
    print(f"scan: {scan_ms:.2f}ms  count_subtree traversal: {count_ms:.2f}ms");

    assert recount_folders == folders;
    assert recount_files == files;
    assert_no_duplicate_edges(ws, set());
}

test "scale measurement: jaclang compiler repo (large real project)" {
    target = "/home/sahan/dev/jaseci/jac/jaclang";
    ws = get_or_create_workspace(root_path=target);

    start = time.perf_counter();
    (folders, files) = scan_directory(ws, target);
    scan_ms = (time.perf_counter() - start) * 1000;

    start = time.perf_counter();
    (recount_folders, recount_files) = count_subtree(ws);
    count_ms = (time.perf_counter() - start) * 1000;

    print(f"\n=== jaclang ({target}) ===");
    print(f"folders={folders} files={files} total={folders + files + 1}");
    print(f"scan: {scan_ms:.2f}ms  count_subtree traversal: {count_ms:.2f}ms");

    assert recount_folders == folders;
    assert recount_files == files;
    assert_no_duplicate_edges(ws, set());
}
