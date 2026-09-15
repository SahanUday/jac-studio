"""Source-control provider over the real `git` CLI, one-shot `subprocess.run` per call.

Deliberately not gated behind `[terminal] enabled`: this is a fixed set of `git` subcommands invoked
as argument lists, never a shell string. The repo root is resolved fresh per call rather than cached
-- `git rev-parse` costs no more than the other spawns an SCM action already makes."""

import os;
import subprocess;
import difflib;
import from src.workbench.workspace.workspace_service { get_current_workspace }

glob _GIT_TIMEOUT_SECONDS: int = 15;

def _run_git(args: list[str], cwd: str) -> tuple[int, str, str] {
    try {
        result = subprocess.run(
            ["git"] + args,
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=_GIT_TIMEOUT_SECONDS
        );
        return (result.returncode, result.stdout, result.stderr);
    } except Exception as e {
        return (1, "", str(e));
    }
}

def _read_file_text(path: str) -> str {
    with open(path, "r", encoding="utf-8", errors="strict") as fh {
        return fh.read();
    }
}

def _repo_root -> str | None {
    ws = get_current_workspace();
    if ws is None {
        return None;
    }
    (code, out, err) = _run_git(["rev-parse", "--show-toplevel"], ws["root_path"]);
    if code != 0 {
        return None;
    }
    return out.strip();
}

def _to_relpath(repo_root: str, path: str) -> str {
    return os.path.relpath(path, repo_root).replace(os.sep, "/");
}

glob _EMPTY_STATUS: dict[str, any] = {
    "is_repo": False, "branch": "", "repo_root": "", "staged": [], "unstaged": [], "untracked": [], "conflicted": []
};

"""The complete, closed set of porcelain `XY` codes meaning an unresolved merge conflict -- not every
two-letter code is one (`MM` is ordinary staged-then-modified)."""
glob _CONFLICT_CODES: set[str] = {"UU", "AA", "DD", "AU", "UA", "DU", "UD"};

"""Parses `git status --porcelain=v1 -z`; `-z` is required so paths with spaces round-trip unquoted,
and a rename/copy entry carries an extra NUL-delimited old path this loop consumes and discards.
Conflicts are routed out before the staged/unstaged split, which would otherwise put `UU` in both."""
def:pub get_scm_status -> dict[str, any] {
    repo_root = _repo_root();
    if repo_root is None {
        return _EMPTY_STATUS;
    }
    (branch_code, branch_out, branch_err) = _run_git(["rev-parse", "--abbrev-ref", "HEAD"], repo_root);
    branch = branch_out.strip() if branch_code == 0 else "";

    (code, out, err) = _run_git(["status", "--porcelain=v1", "-z"], repo_root);
    if code != 0 {
        return {"is_repo": True, "branch": branch, "repo_root": repo_root, "staged": [], "unstaged": [], "untracked": [], "conflicted": []};
    }

    staged = [];
    unstaged = [];
    untracked = [];
    conflicted = [];
    entries = out.split("\0");
    idx = 0;
    while idx < len(entries) {
        status_entry = entries[idx];
        idx += 1;
        if status_entry == "" {
            continue;
        }
        x = status_entry[0];
        y = status_entry[1];
        rel = status_entry[3:];
        if x == "R" or x == "C" {
            idx += 1;
        }
        abs_path = os.path.join(repo_root, rel);
        name = os.path.basename(rel);
        if x == "?" and y == "?" {
            untracked.append({"path": abs_path, "name": name, "relPath": rel, "status": "U"});
            continue;
        }
        if (x + y) in _CONFLICT_CODES {
            conflicted.append({"path": abs_path, "name": name, "relPath": rel, "status": x + y});
            continue;
        }
        if x != " " and x != "?" {
            staged.append({"path": abs_path, "name": name, "relPath": rel, "status": x});
        }
        if y != " " and y != "?" {
            unstaged.append({"path": abs_path, "name": name, "relPath": rel, "status": y});
        }
    }
    return {"is_repo": True, "branch": branch, "repo_root": repo_root, "staged": staged, "unstaged": unstaged, "untracked": untracked, "conflicted": conflicted};
}

"""Returns raw content, not paths -- the `HEAD` blob side has no filesystem path to give. A missing
blob or file falls back to `""` rather than raising, which renders as a whole-file add/delete."""
def:pub get_diff_content(path: str, staged: bool) -> dict[str, str] {
    repo_root = _repo_root();
    if repo_root is None {
        return {"original": "", "modified": ""};
    }
    rel = _to_relpath(repo_root, path);
    (head_code, head_out, head_err) = _run_git(["show", "HEAD:" + rel], repo_root);
    original = head_out if head_code == 0 else "";

    if staged {
        (idx_code, idx_out, idx_err) = _run_git(["show", ":" + rel], repo_root);
        modified = idx_out if idx_code == 0 else "";
    } else {
        try {
            modified = _read_file_text(path);
        } except Exception as e {
            modified = "";
        }
    }
    return {"original": original, "modified": modified};
}

"""Gutter line ranges, diffed against `HEAD` vs. the working tree -- never the index, so the gutter
shows what changed since the last commit regardless of staging. Returns `[]` instead of raising."""
def:pub get_line_changes(path: str) -> list[dict[str, any]] {
    repo_root = _repo_root();
    if repo_root is None {
        return [];
    }
    rel = _to_relpath(repo_root, path);
    (head_code, head_out, head_err) = _run_git(["show", "HEAD:" + rel], repo_root);
    original = head_out if head_code == 0 else "";
    try {
        current = _read_file_text(path);
    } except Exception as e {
        return [];
    }

    original_lines = original.splitlines();
    current_lines = current.splitlines();
    matcher = difflib.SequenceMatcher(None, original_lines, current_lines, autojunk=False);
    changes = [];
    for (tag, i1, i2, j1, j2) in matcher.get_opcodes() {
        if tag == "equal" {
            continue;
        }
        if tag == "insert" {
            changes.append({"type": "added", "startLine": j1 + 1, "endLine": j2});
        } elif tag == "delete" {
            changes.append({"type": "removed", "startLine": max(j1, 1), "endLine": max(j1, 1)});
        } elif tag == "replace" {
            changes.append({"type": "modified", "startLine": j1 + 1, "endLine": j2});
        }
    }
    return changes;
}

def:pub stage_path(path: str) -> None {
    repo_root = _repo_root();
    if repo_root is None {
        return;
    }
    _run_git(["add", "--", path], repo_root);
}

def:pub stage_all -> None {
    repo_root = _repo_root();
    if repo_root is None {
        return;
    }
    _run_git(["add", "-A"], repo_root);
}

def:pub unstage_path(path: str) -> None {
    repo_root = _repo_root();
    if repo_root is None {
        return;
    }
    _run_git(["restore", "--staged", "--", path], repo_root);
}

def:pub unstage_all -> None {
    repo_root = _repo_root();
    if repo_root is None {
        return;
    }
    _run_git(["restore", "--staged", "."], repo_root);
}

"""An untracked file has no version to restore, so discarding it means deleting it, not `git checkout`."""
def:pub discard_path(path: str, is_untracked: bool) -> None {
    repo_root = _repo_root();
    if repo_root is None {
        return;
    }
    if is_untracked {
        try {
            os.remove(path);
        } except Exception as e {}
    } else {
        _run_git(["checkout", "--", path], repo_root);
    }
}

def:pub commit_changes(message: str) -> dict[str, any] {
    repo_root = _repo_root();
    if repo_root is None {
        return {"success": False, "error": "No git repository is open."};
    }
    if message.strip() == "" {
        return {"success": False, "error": "A commit message is required."};
    }
    (code, out, err) = _run_git(["commit", "-m", message], repo_root);
    if code != 0 {
        return {"success": False, "error": (err.strip() or out.strip() or "Commit failed.")};
    }
    return {"success": True, "error": ""};
}
