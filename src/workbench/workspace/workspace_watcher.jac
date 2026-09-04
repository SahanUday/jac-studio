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
everything else that cares) subscribes to, regardless of whether a change came from an AI tool, a
terminal command, `git checkout`, or another program entirely. This module is that same idea,
scoped to what this project actually needs today (the Explorer tree, not yet open-editor
auto-reload -- see `file_tree.jac`'s own docstring for that boundary).

**A second, real, live-reproduced regression, same day: this module's *first* version was itself an
indefinite, always-connected SSE stream (`watch_workspace_changes() -> Generator`, opened once per
workspace-open and left running for the component's whole lifetime) -- and it broke
`list_children_by_path` server-wide the moment it started running, confirmed from a real user's own
terminal log: every `list_children_by_path` call failed with `'Workspace' object has no attribute
'path'` (a shape mismatch that only makes sense if a request landed against a *different* `root`'s
`_path_index` than the one that actually opened `testing-workspace`) from the instant the watch
started, for the rest of that server process's life.** This is this project's own already-documented
SSE-generator-isolation risk (see `claude_code_client.jac`'s docstring and tracker entries
`2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state`/
`2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run`/
`2026-09-05-sse-generator-root-scoped-graph-query-unreliable`) -- but a materially worse instance of
it than any of those: every other `Generator`-returning endpoint in this codebase is short-lived,
scoped to one chat turn or one debug session, and disconnects on its own; this was the first
*indefinite* one, reconnected on every workspace-open and otherwise left running for a whole
session. Whatever isolation mechanism those tracker entries describe, a stream that never
disconnects gives it far more opportunity to interfere with this process's shared, `root`-keyed
`_path_index`/`_cached_workspace_jid` globals than a stream that naturally ends in seconds.

**Fixed by not streaming at all.** `check_workspace_changes` below is a plain, ordinary `def:pub`
function -- the same request/response shape `list_children_by_path` itself, `refresh_status`, and
every other polled-from-the-client call in this codebase already use safely. `file_tree.jac` now
polls it on a `setInterval`, passing back the snapshot it got last time so this function stays
completely stateless server-side (no lingering task, no connection to leak, nothing to abort when a
different workspace opens -- `clearInterval` is all the client-side cleanup this needs, simpler than
the `AbortController` the streaming version required). This isn't a smaller, faster-to-write version
of the same idea -- it's the version that doesn't reach for this project's own proven-unreliable
mechanism for something that never needed to be a stream in the first place.

**Still diffs the *set of immediate entries* per directory, not per-file content/mtimes** -- the
Explorer tree only cares whether what's listed inside a directory changed (a file appeared,
disappeared, or was renamed), not whether some existing file's own content changed. A subdirectory
being deleted entirely is still caught correctly: it stops appearing in *its own parent's* entry
list, which the parent's own diff catches, without needing a separate "disappeared directory" case."""

import os;
import from src.workbench.workspace.workspace_service { DEFAULT_EXCLUDED_DIRS }

def _dir_snapshot(root_path: str) -> dict[str, list[str]] {
    snapshot: dict[str, list[str]] = {};
    for (dirpath, dirnames, filenames) in os.walk(root_path) {
        dirnames[:] = [d for d in dirnames if d not in DEFAULT_EXCLUDED_DIRS];
        snapshot[dirpath] = sorted(dirnames + filenames);
    }
    return snapshot;
}

"""Stateless: `last_snapshot` is whatever the caller got back from its own previous call (an empty
dict on the first call for a given `root_path`), and this function's own `snapshot` return value is
what the caller should pass back on its *next* call -- nothing is kept between calls on this side.
`changed_dirs` is every directory whose own immediate entry list differs from `last_snapshot`,
including any directory present in one snapshot but not the other (a newly created or entirely
deleted subtree)."""
def:pub check_workspace_changes(root_path: str, last_snapshot: dict[str, list[str]]) -> dict[str, any] {
    if not os.path.isdir(root_path) {
        return {"changed_dirs": [], "snapshot": {}};
    }
    current_snapshot = _dir_snapshot(root_path);
    changed_dirs = [
        d for d in current_snapshot
        if d not in last_snapshot or current_snapshot[d] != last_snapshot[d]
    ];
    changed_dirs += [d for d in last_snapshot if d not in current_snapshot];
    return {"changed_dirs": changed_dirs, "snapshot": current_snapshot};
}
