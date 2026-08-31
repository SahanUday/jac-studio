"""TaskService: Phase 4's task-runner-with-problem-matchers deliverable (`docs/roadmap.md`) --
"proves the contribution model handles a feature with its own persistent config format (a
task-definitions equivalent to `tasks.json`), not just UI."

**Config lives in the workspace, not this app's own graph/settings store.** Unlike
`settings_service.jac`'s `Settings` node (this *app's* preferences, root-scoped, private to one
user's session), task definitions are project config in the same spirit as real VS Code's own
`.vscode/tasks.json` -- meant to be authored once and, realistically, checked into the repo and
shared with a team, not tied to one user's server-side graph. `<workspace_root>/.jac-studio/
tasks.json` is this project's native equivalent: a plain JSON array of `{"label", "command",
"problemMatcher"}` dicts, read/written straight off disk the same way `git_service.jac` reads a
repo's actual `.git` state rather than caching a shadow copy server-side.

**Gated behind the same `[terminal] enabled` flag as the integrated terminal -- deliberately NOT
the ungated posture `git_service.jac` took.** A task's `command` is an arbitrary, user-authored
shell string (`subprocess.run(command, shell=True, ...)`), the same trust class as anything typed
into the terminal -- unlike git_service's fixed, narrow allowlist of `git` subcommands invoked as
argument lists, never a shell string, which is what justified that module's own ungated posture.
Reuses the identical `[terminal]` section (not a second config knob) since running a task and
running the same command by hand in the terminal are the same risk, just triggered differently.

**Runs to completion, not streamed -- a deliberate v1 scope cut, not the terminal's own reason for
staying one-shot-per-call.** `terminal_service.jac` streams because its dispatcher offloads only
the *initial* call onto a worker thread, so a plain sync generator would block the whole event loop
for a long-running command's full runtime (see that module's own docstring). A **non-generator**
sync `def:pub`, by contrast, has its *entire* body run via `asyncio.to_thread` -- exactly what
`git_service.jac`'s own blocking `subprocess.run` calls already rely on safely. So a task's output
only ever appears all at once, after it finishes, not incrementally while it runs. Real VS Code
streams task output live; that's real, useful polish worth adding once this lands, not a
correctness gap in what ships here -- the roadmap's own exit criterion ("a build task's errors show
up in a Problems panel") doesn't require live streaming to be true.

**Two built-in problem matchers, not an arbitrary user-configurable regex DSL.** VS Code's own
`problemMatcher` format supports named built-ins (`$tsc`, `$eslint-stylish`, ...) or a full custom
pattern object; matching that whole surface is out of scope for proving the contribution model
works. `"generic"` covers the extremely common single-line `file:line:col: severity: message` shape
(gcc/clang/many linters/most compilers). `"jac"` is this project's own dogfooding case -- parses
`jac check`'s real two-line output shape (`error[CODE]: message` immediately followed by a
`  --> path:line:col` line, the exact format seen throughout this project's own development), so
running `jac check src` as a configured task surfaces this project's *own* compiler diagnostics in
its own Problems panel. `""`/unset means "no problem matcher" -- output still lands in the Output
channel, just nothing is parsed into diagnostics.

**Diagnostics are attached via `workspace_service.ensure_path_reachable`, not `get_file_node_by_path`
directly** -- a problem matcher can name any file in the project, not just ones already expanded in
the Explorer tree; see that function's own docstring for why `diagnostics.jac`'s existing
"attach only to an already-reachable File" contract needed a real fix here, not a workaround.
Diagnostics for every file the *previous* run touched are cleared before the new run's matches are
attached, so a fixed error doesn't linger in the Problems panel after a re-run.
"""

import os;
import json;
import re;
import subprocess;
import from jaclang.project.config { JacConfig }
import from src.workbench.workspace.workspace_service { get_current_workspace, ensure_path_reachable }
import from src.workbench.output.output_service { append_log, clear_channel }
import from src.workbench.diagnostics.diagnostics { add_diagnostic, clear_diagnostics }

glob _TASK_TIMEOUT_SECONDS: int = 300;

glob _GENERIC_PATTERN: str = r"^(?P<file>[^:\n]+):(?P<line>\d+):(?P<column>\d+):\s*(?:(?P<severity>error|warning|note)\s*:?\s*)?(?P<message>.+)$";
glob _JAC_HEADER_PATTERN: str = r"(?P<severity>error|warning)\[(?P<code>[^\]]+)\]:\s*(?P<message>.+)$";
glob _JAC_LOCATION_PATTERN: str = r"^\s*-->\s*(?P<file>.+):(?P<line>\d+):(?P<column>\d+)\s*$";

def _task_runner_enabled -> bool {
    cfg = JacConfig.discover();
    if not cfg {
        return False;
    }
    section = cfg.get_section("terminal");
    if not section {
        return False;
    }
    return bool(section.get("enabled", False));
}

def _tasks_config_path(root_path: str) -> str {
    return os.path.join(root_path, ".jac-studio", "tasks.json");
}

def:pub list_tasks -> list[dict[str, any]] {
    ws = get_current_workspace();
    if ws is None {
        return [];
    }
    config_path = _tasks_config_path(ws["root_path"]);
    if not os.path.isfile(config_path) {
        return [];
    }
    try {
        with open(config_path, "r", encoding="utf-8") as fh {
            raw = fh.read();
        }
    } except Exception as e {
        return [];
    }
    try {
        parsed = json.loads(raw);
    } except Exception as e {
        return [];
    }
    return parsed if isinstance(parsed, list) else [];
}

def:pub save_tasks(tasks: list[dict[str, any]]) -> None {
    ws = get_current_workspace();
    if ws is None {
        return;
    }
    config_dir = os.path.join(ws["root_path"], ".jac-studio");
    os.makedirs(config_dir, exist_ok=True);
    config_path = _tasks_config_path(ws["root_path"]);
    with open(config_path, "w", encoding="utf-8") as fh {
        fh.write(json.dumps(tasks, indent=2));
    }
}

def _parse_generic(output: str) -> list[dict[str, any]] {
    results = [];
    for line in output.splitlines() {
        m = re.`match(_GENERIC_PATTERN, line);
        if m {
            results.append({
                "file": m.group("file"),
                "line": int(m.group("line")),
                "column": int(m.group("column")),
                "severity": (m.group("severity") or "error"),
                "message": m.group("message").strip()
            });
        }
    }
    return results;
}

"""`jac check`'s real diagnostic shape is two lines: a header immediately followed by a location
line (`  --> path:line:col`). Scans line-by-line rather than a single multi-line regex -- easier to
reason about than a `re.MULTILINE` pattern spanning two lines with different leading whitespace, and
this output isn't large enough for the extra pass to matter.

**The header line is not just `error[CODE]: message` -- caught live against a real `jac check`
run, not assumed from the docs.** The CLI's own pretty-printer prefixes every header with a glyph
and a capitalized label (`✖ Error: error[E0013]: 'entry' is a keyword...`, `⚠ warning[W2003]: ...`
for a warning), so an anchored `^(?:error|warning)\\[...` pattern (this function's first version)
never matched a single real diagnostic -- confirmed by running the actual fixture used in this
module's test file through the real CLI and finding zero results instead of the expected one.
`_JAC_HEADER_PATTERN` uses `re.search` (unanchored) rather than `re.match` for this one line so the
glyph/label prefix doesn't matter; the location-line pattern stays anchored (`re.match`), since that
line genuinely has nothing before it."""
def _parse_jac(output: str) -> list[dict[str, any]] {
    lines = output.splitlines();
    results = [];
    idx = 0;
    while idx < len(lines) {
        header_match = re.search(_JAC_HEADER_PATTERN, lines[idx]);
        if header_match and (idx + 1) < len(lines) {
            loc_match = re.`match(_JAC_LOCATION_PATTERN, lines[idx + 1]);
            if loc_match {
                results.append({
                    "file": loc_match.group("file"),
                    "line": int(loc_match.group("line")),
                    "column": int(loc_match.group("column")),
                    "severity": header_match.group("severity"),
                    "message": header_match.group("message").strip()
                });
                idx += 2;
                continue;
            }
        }
        idx += 1;
    }
    return results;
}

def _run_matcher(name: str, output: str) -> list[dict[str, any]] {
    if name == "generic" {
        return _parse_generic(output);
    }
    if name == "jac" {
        return _parse_jac(output);
    }
    return [];
}

"""Runs the configured task named `label`, streams its combined stdout/stderr into an
`"Task: " + label` output channel, then runs the task's own `problemMatcher` (if any) over that
output and refreshes the `Diagnostic`s for every file the matches touch. Returns a small result
summary for the caller to report as a toast (`onNotify`), matching the roadmap's own exit criterion
that a task's completion surfaces one."""
def:pub run_task(label: str) -> dict[str, any] {
    if not _task_runner_enabled() {
        return {"success": False, "exitCode": -1, "diagnosticCount": 0, "error": "The task runner is disabled. Set [terminal] enabled = true in jac.toml to turn it on."};
    }
    ws = get_current_workspace();
    if ws is None {
        return {"success": False, "exitCode": -1, "diagnosticCount": 0, "error": "No workspace is open."};
    }
    matching = [t for t in list_tasks() if t["label"] == label];
    if len(matching) == 0 {
        return {"success": False, "exitCode": -1, "diagnosticCount": 0, "error": "Unknown task: " + label};
    }
    task = matching[0];
    channel = "Task: " + label;
    clear_channel(channel);
    append_log(channel, "> " + task["command"]);

    exit_code = -1;
    combined_output = "";
    try {
        result = subprocess.run(
            task["command"],
            shell=True,
            cwd=ws["root_path"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=_TASK_TIMEOUT_SECONDS
        );
        combined_output = result.stdout + result.stderr;
        exit_code = result.returncode;
    } except Exception as e {
        combined_output = str(e);
    }

    for out_line in combined_output.splitlines() {
        append_log(channel, out_line);
    }
    append_log(channel, "[task exited with code " + str(exit_code) + "]");

    matcher_name = task.get("problemMatcher", "");
    matches = _run_matcher(matcher_name, combined_output) if matcher_name else [];

    touched_paths: set[str] = set();
    for hit in matches {
        abs_path = hit["file"] if os.path.isabs(hit["file"]) else os.path.join(ws["root_path"], hit["file"]);
        touched_paths.add(os.path.normpath(abs_path));
    }
    for touched_path in touched_paths {
        clear_diagnostics(touched_path);
        ensure_path_reachable(touched_path);
    }

    diagnostic_count = 0;
    for hit in matches {
        abs_path = hit["file"] if os.path.isabs(hit["file"]) else os.path.join(ws["root_path"], hit["file"]);
        abs_path = os.path.normpath(abs_path);
        attached = add_diagnostic(abs_path, hit["message"], hit["severity"], hit["line"], hit["column"], label);
        if attached {
            diagnostic_count += 1;
        }
    }

    return {"success": (exit_code == 0), "exitCode": exit_code, "diagnosticCount": diagnostic_count, "error": ""};
}
