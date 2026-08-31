"""SearchService: Phase 4's search-in-files bullet (`docs/roadmap.md`) -- "a workspace-wide feature
reading from the file graph." Reads from the *file listing*, not the graph, deliberately: reuses
`workspace_service.jac`'s `list_all_files` (a plain `os.walk` over the current workspace, already
proven at real scale for Quick Open) as the candidate set, rather than walking the
`Workspace`/`Folder`/`File` graph -- the same "don't pay the eager-graph-scan cost" reasoning that
module's own docstring already gives, now applies here too: a content search reads every candidate
file's bytes regardless, so nothing here would gain anything from graph nodes existing for them
first.

**Plain case-insensitive substring search, not regex/whole-word/ripgrep.** Real VS Code's
production search view uses a bundled `ripgrep` binary and supports regex/case/whole-word toggles;
none of that is inherent to "search workspace text" being useful -- a single substring match
covers the large majority of real search-in-files usage (find every call site of a name, every
reference to a string), and ripgrep integration is exactly the kind of "process execution" pattern
already proven for the terminal (`terminal_service.jac`), not a new one, so it stays a legitimate
future widen rather than something this bullet needs to reach for on day one.

**Bounded, not exhaustive** -- `_MAX_FILES_WITH_MATCHES`/`_MAX_MATCHES_PER_FILE` cap the response
the same way `output_service.jac` caps a channel's line count, and `_MAX_FILE_SIZE_BYTES` skips
anything large enough that reading it fully for one search isn't worth the cost (a build artifact,
a data file that slipped past `DEFAULT_EXCLUDED_DIRS`) -- matches VS Code's own default
`search.maxResults` posture (bounded, not "read the whole workspace no matter its size") without
inventing new machinery to enforce it.

**A read error skips the file, not the whole search** -- covers both genuinely binary files (which
raise `UnicodeDecodeError` under `errors="strict"`, deliberately not `"replace"` here: a `.jpg`
full of decode-replacement noise matching a common query substring by accident would be a false
positive no user wants) and any file that vanishes between `list_all_files`' listing and this
function actually opening it (a real, if narrow, TOCTOU window in a live, editable workspace).
"""

import os;
import from src.workbench.workspace.workspace_service { list_all_files }

glob _MAX_FILES_WITH_MATCHES: int = 200;
glob _MAX_MATCHES_PER_FILE: int = 50;
glob _MAX_FILE_SIZE_BYTES: int = 2000000;

"""`errors="strict"` deliberately, unlike `document_service.jac`'s own `_read_file_content` (which
uses `"replace"` since it's rendering a file for editing, where losing a few bytes to replacement
characters is preferable to refusing to open it at all) -- see the module docstring's "A read error
skips the file" section for why a search wants the opposite trade-off. Mirrors
`document_service.jac`'s exact `with open(...) as f { return f.read(); }` shape (a `return`
directly inside the `with` block, not an intermediate assignment used after it) -- the only form
the type checker resolves `open()`'s return through cleanly; see tracker entry
`2026-08-31-open-read-return-must-be-inline-in-with-block-not-assigned`."""
def _read_file_text(path: str) -> str {
    with open(path, "r", encoding="utf-8", errors="strict") as fh {
        return fh.read();
    }
}

def:pub search_in_files(query: str) -> list[dict[str, any]] {
    needle = query.strip().lower();
    if needle == "" {
        return [];
    }

    results = [];
    for f in list_all_files() {
        if len(results) >= _MAX_FILES_WITH_MATCHES {
            break;
        }
        path = f["path"];
        try {
            if os.path.getsize(path) > _MAX_FILE_SIZE_BYTES {
                continue;
            }
        } except Exception as e {
            continue;
        }

        matches = [];
        try {
            content = _read_file_text(path);
            lines = content.splitlines();
            for idx in range(len(lines)) {
                line: str = lines[idx];
                lowered: str = line.lower();
                if needle in lowered {
                    matches.append({
                        "line": idx + 1,
                        "column": lowered.index(needle) + 1,
                        "preview": line[:300]
                    });
                    if len(matches) >= _MAX_MATCHES_PER_FILE {
                        break;
                    }
                }
            }
        } except Exception as e {
            continue;
        }

        if len(matches) > 0 {
            results.append({"path": path, "name": f["name"], "matches": matches});
        }
    }
    return results;
}
