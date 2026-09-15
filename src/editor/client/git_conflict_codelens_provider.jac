"""Merge-conflict resolution CodeLens: overlays "Accept Current/Incoming/Both" above each
`<<<<<<<`/`=======`/`>>>>>>>` hunk in the regular editor, reusing git's own conflict markers as
the source of truth. Registered for every language (`"*"`), since a conflict can land in any
tracked file. Applying a resolution is a plain `pushEditOperations` edit; Save/`stage_path`
finish resolving it."""

glob _registered: bool = False;

"""Finds every complete `{start, mid, end}` conflict hunk (0-indexed marker line numbers). A
`<<<<<<<` with no matching `=======`/`>>>>>>>` is skipped, not raised on."""
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
    # Single pushEditOperations call: undo reverts the whole resolution atomically.
    model.pushEditOperations([], [{"range": range_, "text": replacement}], lambda (inverse: any) -> any { return None; });
}

def:pub register_conflict_codelens_provider(monaco: any) -> None {
    if _registered {
        return;
    }
    _registered = True;

    # Three global commands, not per-hunk registrations: registerCommand needs a stable id, and
    # (uri, startLine, midLine, endLine) as arguments identifies which lens fired it.
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
