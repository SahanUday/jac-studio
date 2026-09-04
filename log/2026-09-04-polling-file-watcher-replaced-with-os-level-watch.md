---
id: 2026-09-04-polling-file-watcher-replaced-with-os-level-watch
date: 2026-09-04
category: resolved
severity: minor
status: resolved
phase: 5
subsystem: workbench-shell
jac_version: "0.37.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: "src/vs/workbench/services/explorer/browser/explorerService.ts (IFileService.onDidFilesChange); files.watcherExclude default setting"
upstream_issue: ""
tags: [workspace-watcher, file-tree, performance, watchdog, real-user-qa, python-interop]
---

## What happened

Same-day follow-up QA (2026-09-04) after `workspace_watcher.jac` was rewritten from an indefinite
SSE stream to a polled `def:pub check_workspace_changes(root_path, last_snapshot)` (see the
sibling entry about that stream's regression). The polled function itself was flagged as wasteful:
it did a fresh, full `os.walk` of the entire workspace tree, diffing the whole thing against the
client's last snapshot, on every single poll tick (client-side `setInterval`, 1000ms) --
regardless of whether anything had actually changed. Real, measurable CPU cost on a non-trivial
tree for a signal that's usually "nothing happened." Asked to check how VS Code's own production
architecture handles this specific tradeoff rather than re-inventing a rougher approximation.

## What VS Code actually does

It doesn't poll at all. `IFileService`'s watcher is backed by a real OS-level notification
mechanism (inotify on Linux, equivalent APIs elsewhere) -- the OS itself reports a change; nothing
walks the tree on a timer to discover one. `files.watcherExclude`
(`**/node_modules/**`, `**/.git/objects/**`, ...) prunes the native watcher itself, not just what's
displayed afterward, for exactly the resource reason this project's own `DEFAULT_EXCLUDED_DIRS`
prunes `os.walk` -- a huge `node_modules` tree (this project's own frontend has one) would
otherwise burn OS watch handles and wake the process for churn nobody's watching.

## Fix

Added `watchdog` as a new Python dependency (`jac.toml`) and rewrote `workspace_watcher.jac` to
use a real `watchdog.observers.Observer`, scheduled per-directory and non-recursively (walking the
tree once at watch-start with the same `DEFAULT_EXCLUDED_DIRS` filter `os.walk` already used, and
scheduling each non-excluded directory individually -- `Observer.schedule(..., recursive=True)` on
the workspace root would place OS watches on every subdirectory including excluded ones, defeating
the whole point). A `created` event for a new, non-excluded directory schedules that directory too,
so a freshly-created subtree keeps being watched without a full re-scan. One process-wide watch at
a time, swapped when a different workspace opens (this app only ever has one workspace open).

The client-side transport is unchanged and deliberately still a poll, not a push: going back to a
live connection per client would reopen the SSE-generator-isolation risk the sibling entry
describes. What changed is that answering a poll is now an O(1) read of a small in-memory
dirty-directory set instead of an O(files) disk walk -- the OS does the expensive part once,
continuously, in the background, matching how a real file watcher is supposed to work.

**Confirmed safe to add `watchdog` at `.jac` module scope before committing to this design, not
assumed.** A prior, unrelated finding
(`2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure`) showed that
`claude_agent_sdk`'s huge transitive dependency closure blows up jaclang's own compiler when
imported at `.jac` module scope. `watchdog` is small and has no such closure; a real `jac check`
against a probe file importing `watchdog.observers.Observer`/`watchdog.events.FileSystemEventHandler`
at module scope passed clean, and a real `jac run` of a script that subclasses
`FileSystemEventHandler` as a Jac `obj` (`obj DirtyHandler(FileSystemEventHandler) { def
on_any_event(event: any) { ... } }`), schedules a real `Observer` against a real directory, writes
a file into it, and confirms the overridden method actually fires -- virtual dispatch across the
Jac/Python inheritance boundary, not just an import -- also passed, live.

**One real bug caught live-testing before it shipped**: the first version of the event handler
uniformly took `dirname(event.src_path)` for every event type, which mis-marked the *parent*
directory dirty for a `modified` event fired *on a directory itself* (its own mtime changes when a
file is created/deleted inside it -- `dirname` of a directory's own path is one level too high).
Fixed by dropping `modified` events entirely: they carry no signal this module needs beyond what
the `created`/`deleted`/`moved` event that caused them already provides (this module only ever
cares about the *set of names* in a directory changing, matching the old `os.walk`-diffing
version's own semantics, never file content).

## Plan

No further action needed -- this is a permanent, correct-practice fix (an OS-level watch is
strictly better than polling-and-diffing for this exact problem), not a stopgap pending an
upstream change. If a future need arises for the file tree to also react to a *content* change in
an already-open editor tab (not just the tree's own listing), that's separate, larger scope
(`file_tree.jac`'s own docstring already notes this boundary) and would likely reuse the same
`Observer` infrastructure rather than needing a new mechanism.
