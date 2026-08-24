---
id: 2026-08-24-jac-run-persists-state-jac-clean-does-not-reset
date: 2026-08-24
category: doc-gap
severity: minor
status: workaround
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
