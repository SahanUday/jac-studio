"""Exercises `add_diagnostic`/`list_diagnostics`/`clear_diagnostics` against a real scanned `File`
node from `workspace_service.jac`, not a hand-built fixture node -- the module's whole contract is
"attach to a File node reachable via the lazy scan," so the test fixture has to go through that same
scan path (`open_workspace` + `list_children_by_path`) rather than constructing a `File` directly."""

import os;
import tempfile;
import from src.workbench.workspace.workspace_service {
    _reset_workspace_cache_for_tests, open_workspace, list_children_by_path
}

def reset_diagnostics_state {
    _reset_workspace_cache_for_tests();
    _reset_diagnostic_tracking_for_tests();
}

def make_scanned_file -> str {
    fixture_root = tempfile.mkdtemp();
    file_path = os.path.join(fixture_root, "a.txt");
    with open(file_path, "w") as f {
        f.write("a");
    }
    _reset_workspace_cache_for_tests();
    open_workspace(fixture_root);
    list_children_by_path(fixture_root);
    return file_path;
}

test "add_diagnostic on an unscanned path returns False and attaches nothing" {
    _reset_workspace_cache_for_tests();
    unscanned_path = "/not/a/real/scanned/path.txt";

    added = add_diagnostic(unscanned_path, "boom", "error", 1, 1, "test", 1.0);

    assert not added;
    assert list_diagnostics(unscanned_path) == [];
}

test "add_diagnostic on a scanned file attaches a Diagnostic reachable via list_diagnostics" {
    file_path = make_scanned_file();

    added = add_diagnostic(file_path, "unexpected token", "error", 3, 7, "tsc", 1.0);

    assert added;
    diags = list_diagnostics(file_path);
    assert len(diags) == 1;
    assert diags[0]["message"] == "unexpected token";
    assert diags[0]["severity"] == "error";
    assert diags[0]["line"] == 3;
    assert diags[0]["column"] == 7;
    assert diags[0]["source"] == "tsc";
}

test "a file can carry more than one diagnostic at once" {
    file_path = make_scanned_file();

    # Same batch -- both diagnostics are from the same producer run, matching how
    # task_service.jac's run_task stamps every diagnostic from one run identically.
    add_diagnostic(file_path, "unused variable", "warning", 1, 1, "eslint", 1.0);
    add_diagnostic(file_path, "missing semicolon", "error", 2, 5, "eslint", 1.0);

    diags = list_diagnostics(file_path);
    assert len(diags) == 2;
    assert set([d["message"] for d in diags]) == {"unused variable", "missing semicolon"};
}

test "clear_diagnostics removes every diagnostic for that file" {
    file_path = make_scanned_file();
    add_diagnostic(file_path, "unused variable", "warning", 1, 1, "eslint", 1.0);

    clear_diagnostics(file_path);

    assert list_diagnostics(file_path) == [];
}

test "clear_diagnostics on an unscanned path is a harmless no-op" {
    _reset_workspace_cache_for_tests();
    clear_diagnostics("/not/a/real/scanned/path.txt");
}

"""Regression test for a real, live-caught duplication bug: re-running a task twice against the
same file (`clear_diagnostics` then `add_diagnostic` with a newer `batch`, the exact sequence
`task_service.jac`'s `run_task` performs on every re-run) must not leave the *old* batch's
diagnostics visible alongside the new one. This particular shape doesn't reproduce the actual root
cause (`Reports` edge deletion not taking effect across separate real HTTP requests, confirmed live
via `jac browse` -- a single `jac test` process never crosses that request boundary), but the next
test below does exercise it directly: it skips `clear_diagnostics` entirely, simulating exactly what
an unreliable `del e` would look like, and confirms `list_diagnostics`' own `batch`-max filtering is
what actually keeps the result correct regardless."""
test "clear_diagnostics followed by a fresh add_diagnostic never leaves the old batch visible" {
    file_path = make_scanned_file();
    _reset_diagnostic_tracking_for_tests();
    add_diagnostic(file_path, "first run's error", "error", 1, 1, "test", 1.0);
    assert len(list_diagnostics(file_path)) == 1;

    clear_diagnostics(file_path);
    add_diagnostic(file_path, "second run's error", "error", 2, 2, "test", 2.0);

    diags = list_diagnostics(file_path);
    assert len(diags) == 1;
    assert diags[0]["message"] == "second run's error";
}

"""The actual live-caught failure mode: `clear_diagnostics` NOT called at all (standing in for a
`del e` that silently didn't take effect across a real request boundary) still must not resurrect
the old batch alongside the new one -- `list_diagnostics` filters by `batch` alone, never assuming
the old `Reports` edges were actually removed."""
test "a newer batch supersedes an older one even if the old Reports edge was never detached" {
    file_path = make_scanned_file();
    add_diagnostic(file_path, "stale error from an earlier run", "error", 1, 1, "test", 1.0);

    # No clear_diagnostics call here -- deliberately simulating del e's real, observed failure mode.
    add_diagnostic(file_path, "fresh error from the latest run", "error", 2, 2, "test", 2.0);

    diags = list_diagnostics(file_path);
    assert len(diags) == 1;
    assert diags[0]["message"] == "fresh error from the latest run";
}

"""Two files scanned out of the *same* workspace, not two separate `make_scanned_file()` calls --
`get_or_create_workspace` only tracks one open root at a time per test's `root` (opening a second
root path detaches the first one's `Contains` subtree, see its own docstring), so exercising
"two files, one workspace" is what the module actually needs to isolate correctly here."""
test "diagnostics on one file don't leak onto another in the same workspace" {
    fixture_root = tempfile.mkdtemp();
    first_path = os.path.join(fixture_root, "first.txt");
    second_path = os.path.join(fixture_root, "second.txt");
    with open(first_path, "w") as f {
        f.write("1");
    }
    with open(second_path, "w") as f {
        f.write("2");
    }
    _reset_workspace_cache_for_tests();
    open_workspace(fixture_root);
    list_children_by_path(fixture_root);

    add_diagnostic(first_path, "only on first", "error", 1, 1, "test", 1.0);

    assert len(list_diagnostics(first_path)) == 1;
    assert list_diagnostics(second_path) == [];
}

test "list_all_diagnostics starts empty with nothing attached" {
    reset_diagnostics_state();

    assert list_all_diagnostics() == [];
}

test "list_all_diagnostics reports every diagnostic across every touched file, each carrying its own path" {
    reset_diagnostics_state();
    fixture_root = tempfile.mkdtemp();
    first_path = os.path.join(fixture_root, "first.txt");
    second_path = os.path.join(fixture_root, "second.txt");
    with open(first_path, "w") as f {
        f.write("1");
    }
    with open(second_path, "w") as f {
        f.write("2");
    }
    open_workspace(fixture_root);
    list_children_by_path(fixture_root);

    add_diagnostic(first_path, "error on first", "error", 1, 1, "test", 1.0);
    add_diagnostic(second_path, "warning on second", "warning", 2, 3, "test", 1.0);

    all_diags = list_all_diagnostics();
    assert len(all_diags) == 2;
    by_path = {d["path"]: d for d in all_diags};
    assert by_path[first_path]["message"] == "error on first";
    assert by_path[second_path]["severity"] == "warning";
}

test "list_all_diagnostics stops reporting a file once its diagnostics are cleared" {
    file_path = make_scanned_file();
    _reset_diagnostic_tracking_for_tests();
    add_diagnostic(file_path, "will be cleared", "error", 1, 1, "test", 1.0);
    assert len(list_all_diagnostics()) == 1;

    clear_diagnostics(file_path);

    assert list_all_diagnostics() == [];
}
