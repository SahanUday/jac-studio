"""Workspace search-in-files: reads `workspace_service.jac`'s file listing, not the graph.
Plain case-insensitive substring match, no regex/whole-word/ripgrep.
Bounded by `_MAX_FILES_WITH_MATCHES`/`_MAX_MATCHES_PER_FILE`/`_MAX_FILE_SIZE_BYTES`; a read error
(binary file, or file deleted mid-scan) skips that file rather than failing the whole search.
"""

import os;
import from src.workbench.workspace.workspace_service { list_all_files }

glob _MAX_FILES_WITH_MATCHES: int = 200;
glob _MAX_MATCHES_PER_FILE: int = 50;
glob _MAX_FILE_SIZE_BYTES: int = 2000000;

"""`errors="strict"` deliberately (a binary file should be skipped, not read as replacement-char
noise); `return` must stay inline inside the `with` block, see tracker
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
