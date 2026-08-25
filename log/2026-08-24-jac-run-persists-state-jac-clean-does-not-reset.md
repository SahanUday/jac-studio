---
id: 2026-08-24-jac-run-persists-state-jac-clean-does-not-reset
date: 2026-08-24
category: doc-gap
severity: minor
status: resolved
phase: 2
subsystem: tooling
jac_version: "0.36.1 (dev build, jaseci main)"
related_vscode_ref: ""
upstream_issue: ""
tags: [jac-run, jac-clean, persistence, tooling, phase-2]
---

Found while measuring `internal/workspace-graph-spike/`'s real-directory scan performance
(see the companion entry `2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale` for the
actual performance finding this tooling issue got in the way of measuring cleanly).

**What was found**: running `jac run main.jac -- <path>` repeatedly against the same target
directory (a `kind = "cli"` project) produced an ever-growing, obviously-wrong node count --
roughly 5x inflation after five re-runs of the identical command. Root cause: the accessor's
`[root-->[?:Workspace]]` fallback found the *previous* invocation's already-populated `Workspace`
node and scanned a duplicate copy of the whole tree on top of it, every single run. This means
`root`-attached graph state survives across **separate `jac run` process invocations**, not just
within one process's lifetime.

That alone would be expected/documented behavior (matches `jac-testing`'s own "graph state...
persists to `.jac/data` between runs" note) -- except `jac clean --data --force` reported "Nothing
to clean" both before and after the inflation was observed, and no `.jac/data` directory was ever
found to exist anywhere in this project (`ls -la .jac/` showed only a `cache/` directory). The
state is surviving somewhere `jac clean` does not know to look for, at least for this
`kind = "cli"`-project-via-`jac-run` combination -- not confirmed whether this is specific to `cli`
projects, to `jac run` specifically (vs. `jac start`/`jac test`), or something else.

**Verification that it's real, not a graph/query bug of my own making**: the same scan, run inside
a `test` block instead of via `jac run`, never showed the inflation and produced identical,
correct, single-run numbers on repeated `jac test` invocations -- consistent with `jac-testing`'s
documented fresh-graph-per-test-block guarantee. This isolates the issue specifically to
`jac run`'s cross-invocation persistence plus `jac clean`'s failure to reach whatever store that
persistence uses, not to anything in the workspace-graph code itself.

**Plan**: workaround is simply not using repeated `jac run` invocations against a shared `root` for
any measurement or manual testing that needs a clean slate -- use `test` blocks instead, which
reliably get a fresh graph per block regardless of this gap. Not investigated further on our side
(where the actual persisted state lives, or why `jac clean --data` doesn't find it) -- that needs
either reading the runtime's actual store-resolution code more deeply than this pass did, or
asking the maintainers directly, similar to the still-open `2026-08-23-service-registry-snapshot-
read-primitive` question. No action needed for jac-studio itself right now: the `test`-block
workaround is sufficient for anything this project currently needs to measure or verify. Revisit if
this gap ever blocks something that genuinely requires the `jac run` CLI path specifically (not
just measurement/testing).

**CORRECTION (2026-08-25)**: the "not investigated further" line above is now out of date -- the
same underlying phenomenon recurred during Phase 2's real-browser-verification pass (this time via
`jac start`/`jac dev` rather than `jac run`: duplicate `Folder`/`Command` nodes surviving repeated
dev-server restarts and a `jac clean -a`), and this time it was root-caused for real, by reading the
runtime source directly rather than guessing.

**The actual mechanism**: `root`-attached graph state is persisted in an embedded PostgreSQL
cluster, not a JSON/pickle/SQLite file and not anywhere under the project's own `.jac/` directory.
`Session.postinit` (`jaclang/runtimelib/impl/session.impl.jac`) builds a `PgStore` backed by
`PgRuntime` unless `JAC_DB_URL` is set explicitly. The cluster's on-disk data directory is
`shared_pg_data_dir()` (`session.impl.jac`), which resolves to
`os.path.join(os.path.dirname(dist_cache_dir()), 'main')` -- and `dist_cache_dir()`
(`jaclang/runtimelib/impl/pgembed.impl.jac`) is `$JAC_CACHE_HOME/pg/dist` (default
`~/.cache/jac/pg/dist`), so the real Postgres data directory is **`~/.cache/jac/pg/main`** -- one
shared cluster for every jac project on the machine, entirely outside any single project's
directory tree. Within that cluster, each project gets its own database, named deterministically by
`project_db_name()` (`session.impl.jac`): `jac_<sanitized-project-name>_<sha1(realpath(base_path))
[:8]>` -- the same project path always resolves to the same database, across every `jac run`/
`jac start`/`jac dev` invocation, which is exactly why the inflation in the original finding above
kept compounding run over run.

**Why `jac clean`/`jac clean -a` never touches it**: `clean --all` only removes
`config.get_data_dir()` (`.jac/data`), `get_cache_dir()` (`.jac/cache`), `get_venv_dir()`
(`.jac/venv`), and `get_client_dir()` (`.jac/client`) -- all defined as
`project_root/.jac/{data,cache,venv,client}` in `jaclang/project/impl/config.impl.jac`, and removed
in `jaclang/cli/commands/impl/project.impl.jac`. None of these paths intersect
`~/.cache/jac/pg/main` at all -- it's not an oversight in what `clean` wipes, it's a fundamentally
different, machine-global location `clean` was never designed to reach.

**The actual way to get a clean slate**: the built-in `jac db` CLI (`jaclang/cli/commands/impl/
db.impl.jac`), not `jac clean` at all:
- `jac db list` -- lists every project database in the shared cluster, with size, last-used
  timestamp, and owning project path, so you can identify the exact database name for the project
  in front of you.
- `jac db drop <project_db_name> -y` -- drops just that one project's database (confirmed safe:
  every other project's database in the same shared cluster is untouched). Requires no other `jac`
  process to be holding a connection to it at the time (`jac start`/`jac dev` must be stopped
  first, or the drop fails with "another process may still be connected").
- Nuclear option, only if truly starting over machine-wide: delete `~/.cache/jac/pg/main` entirely
  (stop every running `jac` process first) -- wipes every project's graph state, not just one.

This directly answers the "not investigated further" gap the original entry above left open, and
supersedes the "not confirmed whether this is specific to `cli` projects, to `jac run`
specifically... or something else" line -- it isn't specific to any of those; it's the same
project-keyed Postgres database regardless of which `jac` subcommand is used to reach it.
