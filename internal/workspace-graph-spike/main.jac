"""Manual one-off demo entry point -- NOT for repeated measurement. `jac run` was found to persist
root-attached graph state across separate CLI invocations in a way `jac clean --data --force`
does not reset (see README.md and the tracker entry this spike produced), so re-running this
against the same target path accumulates duplicate nodes on every call. The real, trustworthy
scale measurements live in tests/scale_measurement_tests.jac instead, which gets the fresh-graph-
per-test guarantee `jac-testing` documents. Use this file only for a single one-off look."""

import time;
import from src.workspace_graph { get_or_create_workspace, scan_directory, count_subtree }

with entry:__main__ {
    import sys;
    target_path = sys.argv[1] if len(sys.argv) > 1 else ".";

    ws = get_or_create_workspace(root_path=target_path);

    start = time.perf_counter();
    (folders, files) = scan_directory(ws, target_path);
    scan_elapsed = time.perf_counter() - start;

    start = time.perf_counter();
    (recount_folders, recount_files) = count_subtree(ws);
    count_elapsed = time.perf_counter() - start;

    print(f"scanned {target_path}");
    print(f"  folders: {folders}, files: {files}, total nodes: {folders + files + 1}");
    print(f"  scan (build graph):  {scan_elapsed * 1000:.2f}ms");
    print(f"  count (traverse graph): {count_elapsed * 1000:.2f}ms");
    if recount_folders != folders or recount_files != files {
        print(
            f"  NOTE: recount ({recount_folders}f/{recount_files}files) != this run's own scan "
            "count -- likely stale state from a previous invocation, see this file's docstring."
        );
    }
}
