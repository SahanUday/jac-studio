---
id: 2026-09-03-jac-run-kill-leaves-vite-child-process-serving-stale-state
date: 2026-09-03
category: ergonomics
severity: minor
status: workaround-found
phase: 5
subsystem: tooling
jac_version: "0.37.1 (dev mode, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac-run, vite, dev-server, process-management, jac-browse]
---

Found live-verifying Phase 5's AI-chat panel (`ai_chat.jac`) via `jac browse` -- cost real
debugging time chasing two apparently-real bugs that turned out not to exist.

## What happened

Across several `kill <jac-run-pid>; ...; nohup jac run ... &` restart cycles (rebuilding the
client after each source edit, standard practice this session per `jac-studio-implementation`'s
"verify empirically" discipline), the app started showing two different, seemingly-real errors on
different restarts:

1. `E7001: The module '.../workspace_service.js' has no export named 'create_file'` -- even though
   `create_file` genuinely exists in the `.jac` source (confirmed via `grep`, and confirmed present
   identically on `main`).
2. A full React `ErrorBoundary` crash, `ReferenceError: len is not defined`, inside
   `workbench.js`'s compiled `App` function -- on a line (`active_tab_path` computation) that
   predates this PR entirely and had never been touched.

Both looked like real, load-bearing bugs (one suggesting a placement-solver regression from adding
a new module import, the other suggesting a jac2js `len()`-lowering defect) and were investigated
as such, including a full `git stash`/rebuild bisection against `main` to rule out the first one.

## Root cause -- confirmed, not assumed

`pkill -f "jac run"` (and even a plain `kill <pid>` on the `jac run` process) does **not**
reliably terminate the Vite dev-server child process `jac run` spawns
(`.jac/client/node_modules/vite/bin/vite.js`, run under jaclang's bundled `bun`). Confirmed live:
`pgrep -af "jac run|vite"` after killing the parent still showed a live Vite process bound to port
8000, from a *previous* restart cycle, still serving whatever compiled/cached state it had at the
moment its parent died -- independent of later `rm -rf .jac/client/compiled` cache clears and
later `jac run` restarts, which each started a *new* Vite instance without ever reaping the old
one. Two full restart cycles in this same session left two different stale Vite processes behind,
each showing a different symptom depending on which one happened to be the effective server my
`jac browse`/`curl` calls landed on port 8000.

## The fix

`kill <jac-run-pid>` is not sufficient. Confirmed working: `pgrep -af "jac run|vite"` after every
kill, and explicitly `kill -9` any Vite process still listed, before trusting a fresh restart's
state. Once genuinely clean (`pgrep` shows nothing), a fresh `jac run` restart reliably showed
neither symptom -- both "bugs" vanished completely, confirming they were never real code defects.

## Plan

Worth reporting upstream to jaseci: `jac run`'s shutdown path (whatever `kill`/SIGTERM handling
it has, or lack thereof) should also terminate its own spawned Vite child, the same way a
well-behaved process supervisor reaps its children -- a bare `kill <jac-run-pid>` leaving an
orphaned dev server bound to the same port is a real footgun for exactly the workflow this
project's own `jac-studio-implementation` skill mandates (kill-and-restart between every source
edit during live verification). Until fixed upstream, this project's own convention for
restarting `jac run` during live verification should be `pgrep -af "jac run|vite"` +
explicit-kill-anything-found, not a single `kill <pid>`, to avoid repeating this exact multi-hour
false-lead chase.
