---
id: 2026-09-04-watchdog-emits-opened-closed-events-blocklist-bug
date: 2026-09-04
category: resolved
severity: minor
status: resolved
phase: 5
subsystem: workbench-shell
jac_version: "0.37.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [workspace-watcher, watchdog, file-tree, real-user-qa]
---

## What happened

Live-testing a new feature (auto-reloading an open editor tab on an external file change, see
`docs/phases/phase-5-ai-integrations.md`'s "fourteenth finding" for the full feature), added
temporary debug logging directly to `workspace_watcher.jac`'s event handler running inside a real
served `jac run --dev` process (not the `jac run --no-serve` script probes used to originally build
and verify this module). The log showed the installed `watchdog` version emitting event types this
module was never written to expect: `opened`, `closed`, and `closed_no_write`, alongside the four it
was originally built against (`created`, `deleted`, `modified`, `moved`).

## Root cause

The directory-event branch of `on_any_event` was written as a **blocklist**
(`if event_type == "modified" { return; }`, then unconditionally mark `_dirty_dirs` for everything
else) rather than an **allowlist** -- correct as long as `modified` was the only "not real signal"
event type that could occur on a directory, which was true of every event type this module's
original design was tested against. With `opened`/`closed`/`closed_no_write` now confirmed to occur
too (e.g. `os.walk`/`os.listdir` genuinely opens and closes a directory handle to read its entries,
which this `watchdog` version reports as real events), any of these three on a *directory* would
fall through the blocklist and spuriously mark that directory's *parent* dirty, even though nothing
about what the directory actually contains changed at all.

The file-event branch of the same handler already used the correct allowlist shape
(`if event_type in ["created", "deleted", "moved"] { mark dirty }`) from when `_modified_files`
tracking was added the same day -- this bug was only in the directory branch, which predates that
change and was never revisited to match.

## Fix

Changed the directory branch to the same allowlist shape: `if event_type not in ["created",
"deleted", "moved"] { return; }`. `opened`/`closed`/`closed_no_write` (and any other event type not
in that list) now correctly no-op on both branches, rather than being handled correctly on files by
accident of a different code path and incorrectly on directories by omission.

## Plan

No further action -- this is now a permanent, correct fix, verified by re-running the full,
end-to-end live browser test afterward (external edit, create, delete, rename, new-subdirectory
cases) with no false-positive dirty-directory marks observed. Worth remembering for any *future*
`FileSystemEventHandler` work in this codebase: don't assume `watchdog`'s event-type set from its
own documentation or from a single earlier live-test session -- the actual set observed here
(seven distinct types across two live-testing rounds) was larger than assumed both times.
