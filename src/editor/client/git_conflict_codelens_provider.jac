"""register_conflict_codelens_provider: Phase 4's merge-conflict resolution UI (`docs/roadmap.md`'s
last outstanding exit-criterion item -- `scm_diff_editor.jac`'s own docstring explicitly deferred
this). The realistic minimum scope, not the full three-pane merge editor: real VS Code's own
`<<<<<<<`/`=======`/`>>>>>>>` conflict markers are already what git leaves in a working-tree file
after a failed merge -- this reuses that as the source of truth (no new file format, no new
persistence) and overlays CodeLens "Accept Current/Incoming/Both" buttons directly above each hunk
in the *regular* editor, the same surface every other file already opens in. Applying a resolution
is a plain in-buffer edit (`pushEditOperations`, undo-able like any other edit); the existing Save
and `stage_path` actions are what actually finish resolving it -- no new git plumbing needed beyond
`git_service.jac`'s own new `conflicted` status bucket.

**Registered for every language (`"*"`), not just `"jac"` -- unlike every other provider in this
directory.** A merge conflict can land in any tracked file, `.jac` or not (this project's own
`README.md`/`.md` files, `.py` scripts, ...); scoping this to `"jac"` the way
`jac_hover_provider.jac` scopes to Jac-specific language intelligence would silently miss every
non-`.jac` conflict.

**Hunk detection is a pure, testable function (`_find_conflict_hunks`) over plain
`list[str]` lines, not something that reaches into Monaco at all** -- the same "pure core,
thin Monaco-facing shell" split every other provider in this directory already uses for its
own conversion helpers. Scans for a `<<<<<<<` line, then the *next* `=======` line, then the
*next* `>>>>>>>` line after that, discarding a `<<<<<<<` that never finds both (a genuinely
malformed/partial marker set, not this UI's job to repair) rather than raising.

**Three global commands, not per-hunk dynamically-registered ones.** `monaco.editor.registerCommand`
needs a real, stable command id; rather than minting one per hunk per file (churn, and nothing to
ever unregister them), `jac-studio.acceptCurrent`/`acceptIncoming`/`acceptBoth` are registered once
and take `(uri, startLine, midLine, endLine)` as `command.arguments` -- Monaco's own convention for
a CodeLens command that needs to know which specific lens fired it. `_resolve_hunk` looks the model
up by `uri` (addressable independent of which editor currently shows it) and replaces the whole
marker span (`<<<<<<<` line through `>>>>>>>` line inclusive) with whichever side's lines were kept,
joined back with real newlines -- one `pushEditOperations` call, so undo reverts the whole
resolution atomically, not the marker lines and the kept content as two separate steps."""

glob _registered: bool = False;

"""Given a file's lines (0-indexed, no trailing newline per element -- `content.split("\\n")`'s own
shape), returns every complete `{start, mid, end}` conflict hunk found (0-indexed line numbers of
the `<<<<<<<`, `=======`, and `>>>>>>>` marker lines themselves). A `<<<<<<<` with no matching
`=======`/`>>>>>>>` after it is skipped, not raised on -- scans past it rather than getting stuck."""
def:pub _find_conflict_hunks(lines: list[str]) -> list[dict[str, int]] {
    hunks = [];
    i = 0;
    n = len(lines);
    while i < n {
        if lines[i].startswith("<<<<<<<") {
            start = i;
            mid = -1;
            end = -1;
            j = i + 1;
            while j < n {
                if mid == -1 and lines[j].startswith("=======") {
                    mid = j;
                } elif mid != -1 and lines[j].startswith(">>>>>>>") {
                    end = j;
                    break;
                }
                j += 1;
            }
            if mid != -1 and end != -1 {
                hunks.append({"start": start, "mid": mid, "end": end});
                i = end + 1;
                continue;
            }
        }
        i += 1;
    }
    return hunks;
}

def _provide_code_lenses(model: any) -> dict[str, any] {
    lines = model.getValue().split("\n");
    hunks = _find_conflict_hunks(lines);
    lenses = [];
    for h in hunks {
        line = h["start"] + 1;
        range_ = {"startLineNumber": line, "startColumn": 1, "endLineNumber": line, "endColumn": 1};
        args = [model.uri, h["start"], h["mid"], h["end"]];
        lenses.append({"range": range_, "command": {"id": "jac-studio.acceptCurrent", "title": "Accept Current Change", "arguments": args}});
        lenses.append({"range": range_, "command": {"id": "jac-studio.acceptIncoming", "title": "Accept Incoming Change", "arguments": args}});
        lenses.append({"range": range_, "command": {"id": "jac-studio.acceptBoth", "title": "Accept Both Changes", "arguments": args}});
    }
    return {"lenses": lenses, "dispose": lambda -> None {}};
}

def _resolve_hunk(monaco: any, uri: any, start: int, mid: int, end: int, mode: str) -> None {
    model = monaco.editor.getModel(uri);
    if not model {
        return;
    }
    total_lines = model.getLineCount();
    all_lines = [model.getLineContent(i) for i in range(1, total_lines + 1)];
    current_lines = all_lines[start + 1:mid];
    incoming_lines = all_lines[mid + 1:end];
    if mode == "current" {
        kept = current_lines;
    } elif mode == "incoming" {
        kept = incoming_lines;
    } else {
        kept = current_lines + incoming_lines;
    }
    replacement = "\n".join(kept);
    if len(kept) > 0 {
        replacement += "\n";
    }
    end_line = min(end + 2, total_lines + 1);
    range_ = new(monaco.Range, start + 1, 1, end_line, 1);
    model.pushEditOperations([], [{"range": range_, "text": replacement}], lambda (inverse: any) -> any { return None; });
}

def:pub register_conflict_codelens_provider(monaco: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    monaco.editor.registerCommand("jac-studio.acceptCurrent", lambda (accessor: any, uri: any, start: int, mid: int, end: int) {
        _resolve_hunk(monaco, uri, start, mid, end, "current");
    });
    monaco.editor.registerCommand("jac-studio.acceptIncoming", lambda (accessor: any, uri: any, start: int, mid: int, end: int) {
        _resolve_hunk(monaco, uri, start, mid, end, "incoming");
    });
    monaco.editor.registerCommand("jac-studio.acceptBoth", lambda (accessor: any, uri: any, start: int, mid: int, end: int) {
        _resolve_hunk(monaco, uri, start, mid, end, "both");
    });

    monaco.languages.registerCodeLensProvider("*", {
        "provideCodeLenses": lambda (model: any, token: any) {
            return _provide_code_lenses(model);
        },
        "resolveCodeLens": lambda (model: any, codeLens: any, token: any) {
            return codeLens;
        }
    });
}
