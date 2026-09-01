---
id: 2026-09-02-dap-client-generic-spawn-failure-hid-missing-debugpy
date: 2026-09-02
category: ergonomics
severity: minor
status: resolved
phase: 4
subsystem: workbench-shell
jac_version: "0.37.1 (dev mode, compiler source at /home/sahan/dev/jaseci/jac)"
related_vscode_ref: ""
upstream_issue: ""
tags: [dap, debugging, error-handling, jac-venv, jac-install]
---

Reported live: starting a debug session showed "Starting..." for roughly 15 seconds, then
"Failed to start the debug session." — on the very first debug attempt of a fresh server process,
not a restart (PR #64 had already fixed the separate restart-hang bug).

## Root cause

`dap_client.jac`'s `start_debug_session` declares `debugpy = ">=1.8.0"` in `jac.toml`, but that
dependency only lands in this project's own `.jac/venv` after an actual `jac install` run — it is
never bundled into the embedded runtime cache `_resolve_embedded_python` targets
(`~/.cache/jac/rt/<hash>/python`). Checked directly: every cached runtime hash on this machine had
zero trace of `debugpy` anywhere under its own `python/` or `site/` trees.

When `.jac/venv` is missing or stale (pruned by this machine's own periodic build-artifact
cleanup per this user's own working-agreement doc, or simply never installed on a fresh checkout —
matches the already-known `jac-language` skill gotcha about `jac clean --all` wiping `.jac/venv`),
`_spawn_session` still successfully resolves a python binary and successfully spawns
`python3.14 -X frozen_modules=off -m debugpy --listen ... --wait-for-client dap_launcher.py <path>`
as a subprocess — but that subprocess crashes almost instantly with its own
`ModuleNotFoundError: No module named 'debugpy'` and never binds its listen port. This failure was
completely invisible to the client: `_drain_process_output` (which pipes the subprocess's own
stdout/stderr into the SSE stream) is only wired up *after* the TCP connect step below succeeds, so
a subprocess that dies before ever listening produces zero visible output anywhere. The connect
loop then just burns the full `_DAP_CONNECT_TIMEOUT_SECONDS` (15s) retrying against a dead process
before giving up — and every failure branch in `_spawn_session` (no embedded Python, spawn
exception, connect timeout, handshake timeout) collapsed into the exact same generic
`"Failed to start the debug session."` message in `start_debug_session`, discarding whatever the
real reason was.

Confirmed by direct reproduction: renamed `.jac/venv/lib/python3.14/site-packages/debugpy` out of
the way, restarted an isolated test server, and reproduced the identical 15s-then-generic-failure
symptom via a direct SSE fetch against `/function/start_debug_session` (bypassing the UI entirely,
to rule out any client-side involvement). Running `jac install` (which puts `debugpy` into
`.jac/venv`, a directory distinct from the embedded runtime cache) and retrying against the *same
already-running* server process succeeded immediately — no restart needed, confirming
`add_project_venv_to_path()`'s `site.addsitedir()` call (in the bundled `_jac_finder.py`/
`sitecustomize.py`) adds `.jac/venv`'s site-packages as a live directory reference, not a
startup-time snapshot.

## Fix

Two changes to `dap_client.jac`:

1. `_spawn_session`'s return type changed from `DapProcess | None` to `(DapProcess | None, str)` --
   every failure branch now returns its own specific reason instead of discarding it.
2. A new `_check_debugpy_available(python_bin, env)` preflight runs `python_bin -c "import debugpy"`
   (using the exact same `PYTHONPATH` the real spawn will use) before attempting the real
   spawn-and-connect dance. On failure it returns immediately (confirmed live: ~130ms, not 15s)
   with `"debugpy is not installed for this project. Run 'jac install' (it's declared in jac.toml)
   to install it, then try again."` -- a message a user can act on directly, instead of a dead end.

Verified end-to-end on an isolated test server, both directions: the missing-debugpy case now
fails in ~130ms with the specific message (previously 15s + generic message), and the real
happy-path breakpoint-hit flow (stack frames, variables) still works identically once `.jac/venv`
has `debugpy` again.

## Plan

Resolved as shipped -- specific, fast, actionable failure messages are the correct permanent
behavior regardless of what jaseci does or doesn't add later, not a stopgap for a jaseci
limitation. No follow-up needed on the DAP client side. The one open, adjacent question this
surfaces (not this entry's to solve): should `jac run --serve --dev`'s own boot sequence detect
and auto-run `jac install` when a project has undeclared/uninstalled Python dependencies, the same
way it already auto-runs `bun install` for JS dependencies at boot? That would prevent this whole
class of "silently missing Python dependency" failure for any project, not just this one feature --
worth raising as a jaseci-level question if it recurs elsewhere, but out of scope for jac-studio's
own code to fix unilaterally.
