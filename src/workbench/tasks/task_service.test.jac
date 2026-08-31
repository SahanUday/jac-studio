"""Exercises the pure pieces directly (`_parse_generic`/`_parse_jac`, `list_tasks`/`save_tasks`),
plus `run_task`'s deny-by-default gate. **Deliberately does not exercise `run_task`'s actual
subprocess-execution success path** -- this repo's own `jac.toml` ships `[terminal] enabled =
false` (deny-by-default, matching `terminal_service.jac`'s own posture, which has no test file at
all for the identical reason), so a `jac test` run against the real project config can only ever
observe the disabled branch deterministically. The execution path (a real task actually running,
its output landing in the right `output_service.jac` channel, its problem matcher populating real
diagnostics) is verified live against a real `jac run --serve --dev` server with the flag
temporarily flipped on, not committed that way -- see the PR description for that verification."""

import os;
import tempfile;
import from src.workbench.workspace.workspace_service { _reset_workspace_cache_for_tests, open_workspace }

def open_fixture_workspace -> str {
    fixture_root = tempfile.mkdtemp();
    _reset_workspace_cache_for_tests();
    open_workspace(fixture_root);
    return fixture_root;
}

test "_parse_generic matches a standard file:line:col: severity: message line" {
    output = "src/main.c:42:9: error: expected ';' before '}' token";

    results = _parse_generic(output);

    assert len(results) == 1;
    assert results[0]["file"] == "src/main.c";
    assert results[0]["line"] == 42;
    assert results[0]["column"] == 9;
    assert results[0]["severity"] == "error";
    assert results[0]["message"] == "expected ';' before '}' token";
}

test "_parse_generic defaults to error severity when none is present" {
    results = _parse_generic("lib/util.py:10:1: unused import 'os'");

    assert len(results) == 1;
    assert results[0]["severity"] == "error";
}

test "_parse_generic ignores lines that don't match the pattern" {
    output = "Building project...\nsrc/a.c:1:1: error: bad\nDone.";

    results = _parse_generic(output);

    assert len(results) == 1;
    assert results[0]["file"] == "src/a.c";
}

test "_parse_generic returns every match across multiple lines" {
    output = "a.c:1:1: error: first\nb.c:2:5: warning: second";

    results = _parse_generic(output);

    assert len(results) == 2;
    assert results[0]["file"] == "a.c";
    assert results[1]["file"] == "b.c";
    assert results[1]["severity"] == "warning";
}

"""`jac check`'s CLI pretty-printer prefixes every real header line with a glyph and a capitalized
label (`✖ Error: `/`⚠ `) before the actual `error[CODE]:`/`warning[CODE]:` text -- these fixtures
use that real shape, not a simplified one, specifically because a first version of `_parse_jac`
anchored its header regex at line-start and silently matched nothing against real `jac check`
output (caught by running the exact fixture below through the real CLI, not assumed). See
`_parse_jac`'s own docstring for the fix."""

test "_parse_jac matches a real jac check error header plus its location line" {
    output = "✖ Error: error[E0013]: 'entry' is a keyword and cannot be used as a variable name\n  --> src/workbench/scm/git_service.jac:120:9\n";

    results = _parse_jac(output);

    assert len(results) == 1;
    assert results[0]["severity"] == "error";
    assert results[0]["file"] == "src/workbench/scm/git_service.jac";
    assert results[0]["line"] == 120;
    assert results[0]["column"] == 9;
    assert results[0]["message"] == "'entry' is a keyword and cannot be used as a variable name";
}

test "_parse_jac matches a warning header the same way as an error one" {
    output = "⚠ warning[W1037]: Explicit 'any' type annotation disables type checking here\n  --> src/foo.jac:10:5\n";

    results = _parse_jac(output);

    assert len(results) == 1;
    assert results[0]["severity"] == "warning";
}

test "_parse_jac finds every error/location pair across multiple diagnostics" {
    output = "✖ Error: error[E1]: first problem\n  --> a.jac:1:1\n✖ Error: error[E2]: second problem\n  --> b.jac:2:2\n";

    results = _parse_jac(output);

    assert len(results) == 2;
    assert results[0]["file"] == "a.jac";
    assert results[1]["file"] == "b.jac";
}

test "_parse_jac ignores a header line with no following location line" {
    output = "✖ Error: error[E1]: dangling header with nothing after it\n";

    results = _parse_jac(output);

    assert results == [];
}

test "list_tasks returns an empty list when no workspace is open" {
    _reset_workspace_cache_for_tests();

    assert list_tasks() == [];
}

test "list_tasks returns an empty list when tasks.json doesn't exist yet" {
    open_fixture_workspace();

    assert list_tasks() == [];
}

test "save_tasks then list_tasks round-trips real task definitions through a real file" {
    fixture_root = open_fixture_workspace();
    tasks = [
        {"label": "Check", "command": "jac check src", "problemMatcher": "jac"},
        {"label": "Build", "command": "echo building", "problemMatcher": ""}
    ];

    save_tasks(tasks);

    assert os.path.isfile(os.path.join(fixture_root, ".jac-studio", "tasks.json"));
    loaded = list_tasks();
    assert loaded == tasks;
}

test "list_tasks returns an empty list for malformed JSON rather than raising" {
    fixture_root = open_fixture_workspace();
    config_dir = os.path.join(fixture_root, ".jac-studio");
    os.makedirs(config_dir);
    with open(os.path.join(config_dir, "tasks.json"), "w") as f {
        f.write("{ not valid json");
    }

    assert list_tasks() == [];
}

test "run_task refuses to run while the task runner is disabled (this repo's own jac.toml default)" {
    open_fixture_workspace();
    save_tasks([{"label": "Echo", "command": "echo hi", "problemMatcher": ""}]);

    result = run_task("Echo");

    assert result["success"] == False;
    assert "disabled" in result["error"];
}
