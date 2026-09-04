"""WorkspaceWatcher: a general, feature-agnostic external-file-change notifier for the currently
open workspace -- closes a real gap found live (2026-09-04, real-user QA): a file the AI agent's
own `Write` tool created was genuinely on disk but never appeared in `file_tree.jac`'s Explorer
tree, since nothing in this project's client-side state had any way to know a write happened
outside its own RPC calls.

**A first fix wired a dedicated `onWorkspaceFileChanged` callback directly from `ai_chat.jac`'s own
`tool_result` handling -- correct, but special-cased to one specific *cause* of an external change
(this app's own AI tool calls), not the general problem.** Asked to check how real VS Code handles
this, and it doesn't special-case causes either: `IFileService.onDidFilesChange`
(`explorerService.ts` in a real `microsoft/vscode` checkout) is one general, OS-level file-system
watcher covering the *entire* open workspace, feeding a single event stream that the Explorer (and
everything else that cares -- open editors, SCM, search) subscribes to, regardless of whether a
change came from an AI tool, a terminal command, `git checkout`, or another program entirely. This
module is that same idea, scoped to what this project actually needs today (the Explorer tree, not
yet open-editor auto-reload -- see `file_tree.jac`'s own docstring for that boundary) --
**replacing** the `onWorkspaceFileChanged` wiring, not layering on top of it, since a general
watcher already covers every case the special-cased one did plus everything it didn't.

**Polling a directory snapshot, not a native OS watcher (inotify/`watchdog`/parcel) -- a deliberate
choice, not a missing dependency.** This project already has two real, working precedents for
polling-based cross-process coordination doing the identical job a "real" watcher would
(`claude_code_launcher.py`'s `_wait_for_tool_approval`, `dap_client.jac`'s command-file polling) --
extending that same idiom here, rather than introducing this project's first native file-system-
event dependency, for a local dev tool where sub-second latency isn't the bar VS Code's own
Electron-process-boundary architecture has to clear. `_POLL_INTERVAL_SECONDS` trades a small,
bounded latency (at most one interval before a change is noticed) for zero new dependencies and no
platform-specific native-watcher behavior to verify across environments.

**Diffs the *set of immediate entries* per directory, not per-file content/mtimes.** The Explorer
tree only cares whether what's listed inside a directory changed (a file appeared, disappeared, or
was renamed) -- an existing file's own content changing doesn't change its parent directory's
listing, so tracking mtimes would notice changes this tree has no reason to react to. A
subdirectory being deleted entirely is still caught correctly: it stops appearing in *its own
parent's* entry list, which the parent's own diff catches, without needing a separate
"disappeared directory" case -- `os.walk` simply never visits the deleted path in the new snapshot,
so nothing yields a stale reference to it.

**`root_path` resolved by the caller, passed in as a plain argument -- the same SSE-generator-
isolation-safe pattern `claude_code_client.jac`'s `start_chat_turn` and this exact class of bug
already established (see that module's own docstring).** This generator never queries
`get_current_workspace()` (a real `root`-scoped graph query) itself; `file_tree.jac` already has
`root_path` as plain component state by the time it starts watching, from the same
`_open_path_into_tree` call that opened the workspace in the first place.

**No server-side "has the workspace changed" self-termination.** An earlier design considered
having this generator poll `get_current_workspace()` itself each iteration to notice when the user
opens a *different* folder and stop on its own -- rejected for the identical reason `root_path`
isn't resolved fresh here at all: that's exactly the root-scoped-graph-query-inside-an-SSE-generator
pattern already proven unreliable. Instead this stream runs until its connection closes, and
`file_tree.jac`'s own client-side `AbortController` (see that module's docstring) is what actually
stops it when the user opens a new root -- the correct side for that decision to live on, since the
client is the one that knows when it no longer wants this particular watch."""

import asyncio;
import json;
import os;
import from typing { AsyncGenerator, Generator }
import from src.workbench.workspace.workspace_service { DEFAULT_EXCLUDED_DIRS }

glob _POLL_INTERVAL_SECONDS: float = 1.0;

def _dir_snapshot(root_path: str) -> dict[str, list[str]] {
    snapshot: dict[str, list[str]] = {};
    for (dirpath, dirnames, filenames) in os.walk(root_path) {
        dirnames[:] = [d for d in dirnames if d not in DEFAULT_EXCLUDED_DIRS];
        snapshot[dirpath] = sorted(dirnames + filenames);
    }
    return snapshot;
}

"""The one SSE-streamed entry point. Yields `{"type": "changed", "dirs": [...]}` whenever a poll
notices any directory's own immediate entry list differ from the previous poll -- `dirs` is every
directory that changed in that interval, not just one, since several can genuinely change between
two polls (a multi-file AI turn, a `git checkout` touching many paths at once). Yields nothing on an
interval with no changes -- an idle workspace produces an empty, silent stream, not a periodic
no-op event `file_tree.jac` would have to filter out itself."""
async def:pub watch_workspace_changes(root_path: str) -> Generator {
    async def stream -> AsyncGenerator[str, None] {
        if not os.path.isdir(root_path) {
            return;
        }
        last_snapshot = _dir_snapshot(root_path);
        while True {
            await asyncio.sleep(_POLL_INTERVAL_SECONDS);
            current_snapshot = _dir_snapshot(root_path);
            changed_dirs = [
                d for d in current_snapshot
                if d not in last_snapshot or current_snapshot[d] != last_snapshot[d]
            ];
            if changed_dirs {
                yield json.dumps({"type": "changed", "dirs": changed_dirs});
            }
            last_snapshot = current_snapshot;
        }
    }
    report stream();
}
