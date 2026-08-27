"""Exercises `add_diagnostic`/`list_diagnostics`/`clear_diagnostics` against a real scanned `File`
node from `workspace_service.jac`, not a hand-built fixture node -- the module's whole contract is
"attach to a File node reachable via the lazy scan," so the test fixture has to go through that same
scan path (`open_workspace` + `list_children_by_path`) rather than constructing a `File` directly."""

import os;
import tempfile;
import from src.workbench.workspace.workspace_service {
    _reset_workspace_cache_for_tests, open_workspace, list_children_by_path
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

    added = add_diagnostic(unscanned_path, "boom", "error", 1, 1, "test");

    assert not added;
    assert list_diagnostics(unscanned_path) == [];
}

test "add_diagnostic on a scanned file attaches a Diagnostic reachable via list_diagnostics" {
    file_path = make_scanned_file();

    added = add_diagnostic(file_path, "unexpected token", "error", 3, 7, "tsc");

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

    add_diagnostic(file_path, "unused variable", "warning", 1, 1, "eslint");
    add_diagnostic(file_path, "missing semicolon", "error", 2, 5, "eslint");

    diags = list_diagnostics(file_path);
    assert len(diags) == 2;
    assert set([d["message"] for d in diags]) == {"unused variable", "missing semicolon"};
}

test "clear_diagnostics removes every diagnostic for that file" {
    file_path = make_scanned_file();
    add_diagnostic(file_path, "unused variable", "warning", 1, 1, "eslint");

    clear_diagnostics(file_path);

    assert list_diagnostics(file_path) == [];
}

test "clear_diagnostics on an unscanned path is a harmless no-op" {
    _reset_workspace_cache_for_tests();
    clear_diagnostics("/not/a/real/scanned/path.txt");
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

    add_diagnostic(first_path, "only on first", "error", 1, 1, "test");

    assert len(list_diagnostics(first_path)) == 1;
    assert list_diagnostics(second_path) == [];
}
