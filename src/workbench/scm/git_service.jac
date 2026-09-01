"""GitService: Phase 4's source-control provider (`docs/roadmap.md`) -- a first, git-specific
implementation of the "provider-agnostic SCM view" the roadmap describes, talking to the real
`git` CLI as a subprocess the same way `terminal_service.jac` talks to any other process
(per `vscode-feature-gap-analysis.md` and `docs/architecture.md`'s Process Execution section).

**Not gated behind `[terminal] enabled` (deliberate, distinct from `terminal_service.jac`'s own
deny-by-default posture).** The terminal's gate exists because an arbitrary shell command is a
generic remote-code-execution surface; source control is a fixed, narrow set of well-known `git`
subcommands (status/diff/add/restore/checkout/commit) invoked with argument lists, never a shell
string -- `asyncio.create_subprocess_shell` vs. `subprocess.run(["git", ...])` is the same
distinction real VS Code's own bundled Git extension draws (it talks to `git` unconditionally, with
no separate opt-in, while the *integrated terminal* is its own, separately-gated feature). Matching
that split here rather than folding SCM behind the terminal flag too.

**One-shot `subprocess.run` per call, not the terminal's streamed async-generator shape.** Every
git operation here (`status`, `diff`, `add`, `commit`, ...) is a short, bounded command whose full
output is needed before the caller can do anything useful with it (parse status lines, build a
diff view) -- there's no "stream partial output to the user as it arrives" requirement the way a
long-running build/watch command in the terminal has, so a plain synchronous `def:pub` (dispatched
via `asyncio.to_thread` like any other sync call, per `jaclang/runtimelib/serving/app.jac`) is the
right shape, matching `search_service.jac`'s own plain-sync precedent over `terminal_service.jac`'s
async-generator one.

**Resolves the repo root fresh on every call (`git rev-parse --show-toplevel`), not cached.** Unlike
`workspace_service.jac`'s `jid(root)`-keyed node cache (needed there because resolving/creating a
graph node is comparatively expensive), a `git rev-parse` call is itself just as cheap as any other
one-shot git invocation this module already makes per call -- caching it would only save one of the
several subprocess spawns a single SCM action already costs, not eliminate the dominant cost.
Keeps every function here trivially stateless and correct across the workspace being closed/reopened
mid-session, with no cache-invalidation bookkeeping to get wrong.

**Diff content is fetched by content, not by real file path (2026-08-31)** -- see
`scm_diff_editor.jac`'s docstring for why `get_diff_content` returns raw original/modified strings
rather than paths for `document_service.open_document` to load: the "original" side (a `git show
HEAD:<path>` blob) has no real filesystem path to give it.

**Line-level gutter decorations (`get_line_changes`) reuse `difflib.SequenceMatcher`** against the
same HEAD-blob-vs-working-tree-content pair `get_diff_content` computes for the unstaged case,
rather than shelling out to `git diff --unified=0`'s own hunk-header format -- Python's stdlib
opcode output (`"equal"|"replace"|"delete"|"insert"`, each with `(i1, i2, j1, j2)`) is already
exactly the shape a gutter decoration needs (a contiguous added/modified/removed line range in the
*current* buffer), with no hunk-header parsing to get subtly wrong."""

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

"""The seven porcelain `XY` codes git itself only ever emits for an unresolved merge conflict --
confirmed against git's own `git-status` documentation, not guessed from the two-letter shape alone
(an ordinary `MM`, staged-then-further-modified, is a completely normal non-conflict state that
happens to also have two non-space letters -- these seven are the actual, complete, closed set)."""
glob _CONFLICT_CODES: set[str] = {"UU", "AA", "DD", "AU", "UA", "DU", "UD"};

"""Parses `git status --porcelain=v1 -z` -- the `-z` (NUL-separated, unquoted paths) form
specifically so a path containing a space or unusual character round-trips correctly, unlike the
default human-oriented, potentially-quoted format. Each entry is `"XY " + path`, or for a rename/
copy, `"XY " + new_path + "\\0" + old_path` (an extra NUL-delimited field this loop consumes and
discards -- old-path history isn't surfaced in this v1 UI). `X` is the index/staged status, `Y` is
the working-tree/unstaged status; a bare `??` means untracked, handled as its own bucket rather than
appearing in both.

**A conflicted file is checked and routed to its own `conflicted` bucket before the ordinary
staged/unstaged split -- not left to fall through into them.** Without this, `_CONFLICT_CODES`'
own docstring's real example (`UU`, both letters non-space/non-`?`) would previously have landed in
*both* `staged` and `unstaged` with a nonsense `status: "U"` in each -- confirmed by reading the
old logic, not just theorized. The merge-conflict UI (`git_conflict_codelens_provider.jac`) is what
actually consumes this bucket."""
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

"""Returns `{"original", "modified"}` content for a git diff view -- `original` is always the
`HEAD` blob (empty string for a file that doesn't exist there yet: a new/untracked file). `modified`
is the index (staged) blob for `staged=True`, or the real on-disk working-tree content otherwise.
Never raises on a missing blob/file -- both sides fall back to `""`, which a diff view renders as
"everything on the other side was added/removed", the correct display for a brand-new or deleted
file."""
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

"""Line-range decorations for `monaco_editor.jac`'s gutter, computed against `HEAD` vs. the current
on-disk working-tree content (never the staged/index blob -- a plain open file's gutter should
reflect what's changed since the last commit, regardless of staging state, matching real VS Code's
own editor gutter). Returns `[]` for anything that isn't a clean two-content diff (no repo, unreadable
file) rather than raising -- a gutter with no decorations is the correct display for "nothing to
compare", not an error state."""
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

"""`is_untracked` files have no committed/index version to revert to -- "discard" for those means
deleting the file itself (matching real VS Code's own confirmation-then-delete behavior for an
untracked file's Discard Changes action), never `git checkout --`, which only knows how to restore
a *tracked* file's working-tree copy from the index."""
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
