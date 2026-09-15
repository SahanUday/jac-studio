# 0071 — Workspace changes are watched via OS-level events, polled from the client

- **Date**: 2026-09-15
- **Status**: accepted; supersedes an interim per-second `os.walk` polling design and a since-reverted SSE-streamed version

## Decision

`workspace_watcher.jac` watches the open workspace with a real OS-level watch (`watchdog`),
scheduled per directory and excluding `node_modules`/`.git`/etc. The client still polls via
`setInterval`, but each poll is an O(1) in-memory read of already-computed watcher state, not a
disk walk. `file_tree.jac` owns the watch connection for the currently open workspace.

## Why

Real VS Code has one general, workspace-wide file-change stream (`IFileService.onDidFilesChange`)
that everything subscribes to, not a callback special-cased per cause — the first version of this
feature was AI-write-specific and didn't generalize. An indefinite SSE stream (one per
workspace-open, never disconnecting) was tried first and was itself a regression: it broke
`list_children_by_path` server-wide the moment it started, the first stream in this codebase that
never ends, giving the known SSE-generator-isolation risk far more room to interfere with shared,
`root`-keyed state than any short-lived stream does. Per-second `os.walk`-and-diff worked but cost a
full disk walk every poll.

## Consequences

The server side of this feature must stay stateless per call (`check_workspace_changes` takes the
client's last snapshot and returns a fresh one) — no server-held connection to leak or abort on
workspace switch. `watchdog`'s event set is broader than expected (`opened`/`closed`/
`closed_no_write`, not just the four the module was built against) — the directory-event branch
must be an explicit allowlist, not a blocklist, or spurious events mark unrelated directories dirty.
