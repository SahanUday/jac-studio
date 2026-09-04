---
id: 2026-09-04-dev-server-stale-vite-cache-after-rapid-restarts
date: 2026-09-04
category: ergonomics
severity: minor
status: workaround
phase: 5
subsystem: tooling
jac_version: "0.37.1 (dev build, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac-run-dev, vite, build-cache, tooling]
---

## What happened

Live-verifying a new feature required starting and killing several isolated `jac run --dev`
instances in quick succession (different ports each time, ~6 start/stop cycles within about 15
minutes, to test against clean state without disturbing the real user's own running server). After
several cycles, a completely fresh browser session against a freshly-started instance began
crashing at initial mount with `ReferenceError: len is not defined`, thrown from
`compiled/src/workbench/shell/workbench.js` at a pre-existing, unmodified `len(...)` call
(`active_group_list`/`active_tab_path` in `workbench.jac`) -- the app's whole root component,
caught by the top-level `ErrorBoundary`, showing "🚨 Something went wrong."

## Investigation

Initially looked like a real regression in code changed that same session. Ruled out by `git stash`
-- restarted a server against the exact last-committed HEAD (no uncommitted changes at all) on a
fresh port, and the identical crash reproduced there too, on code that had not been touched. This
confirmed the bug was not in any `.jac` source at all -- something about the *build artifacts* had
gone stale or corrupted across the repeated rapid restarts.

## Fix (workaround)

`rm -rf .jac/client/.vite .jac/cache`, then a fresh `jac run --dev` (a real, from-scratch
recompile, ~29s vs. the usual few seconds for an incremental one) -- the crash did not reproduce
again afterward, confirmed via a fresh browser session. `.jac/cache` held one hash-named
subdirectory with a very recent mtime matching the rapid-restart window, consistent with a stale or
partially-written compilation-cache entry from an interrupted (`kill`ed, not gracefully stopped)
prior run being reused by a later one.

## Plan

Not investigated further at the compiler/build-tool level -- this project's own `jac.toml`
convention (`[test]`, `[client.vite]`) and `jac run --help`'s own `-c/--cache/--no-cache` flag
suggest the caching behavior is by design and normally safe under an ordinary single-session dev
workflow (start once, edit, HMR, stop once) -- the trigger here was specifically *repeated,
non-graceful* (`kill`, not a clean shutdown) restarts within a short window, an unusual pattern for
a real user session but a normal one for this kind of rapid live-verification testing. Documenting
the workaround (`rm -rf .jac/client/.vite .jac/cache` before a clean restart) so a future session
doing similar rapid isolated-server verification testing doesn't mistake this for a real regression
in whatever code it's actually trying to verify, the way this session initially did before checking
against a clean stash.
