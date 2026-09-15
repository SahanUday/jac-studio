"""Task runner with problem matchers; definitions are project config read off disk from
`<workspace_root>/.jac-studio/tasks.json`, not this app's settings node.

Gated behind `[terminal] enabled` because a task's `command` is an arbitrary shell string. Runs to
completion, not streamed: a non-generator sync `def:pub` gets its whole body on `asyncio.to_thread`."""

import os;
import json;
import re;
import subprocess;
import from jaclang.project.config { JacConfig }
import time;
import from src.workbench.workspace.workspace_service { get_current_workspace, ensure_path_reachable }
import from src.workbench.output.output_service { append_log, clear_channel }
import from src.workbench.diagnostics.diagnostics { add_diagnostic, clear_diagnostics, list_all_diagnostics }

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

"""`jac check` emits a header line followed by a `  --> path:line:col` line. The header is matched
unanchored because the CLI prefixes it with a glyph and label (`✖ Error: error[E0013]: ...`); the
location line stays anchored."""
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

"""Runs `label`, logs its output to a `"Task: " + label` channel, then refreshes diagnostics for every
file its `problemMatcher` touches. Every diagnostic from one run shares one `batch` marker."""
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
    # a file this run no longer matches gets no fresh batch to supersede its stale one -- clear it here
    previously_reported_paths = set([
        d["path"] for d in list_all_diagnostics() if d["source"] == label
    ]);
    for touched_path in (touched_paths | previously_reported_paths) {
        clear_diagnostics(touched_path);
    }
    for touched_path in touched_paths {
        ensure_path_reachable(touched_path);
    }

    run_batch = time.time();
    diagnostic_count = 0;
    for hit in matches {
        abs_path = hit["file"] if os.path.isabs(hit["file"]) else os.path.join(ws["root_path"], hit["file"]);
        abs_path = os.path.normpath(abs_path);
        attached = add_diagnostic(abs_path, hit["message"], hit["severity"], hit["line"], hit["column"], label, run_batch);
        if attached {
            diagnostic_count += 1;
        }
    }

    return {"success": (exit_code == 0), "exitCode": exit_code, "diagnosticCount": diagnostic_count, "error": ""};
}
