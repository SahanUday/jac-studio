---
id: 2026-09-04-indefinite-sse-generator-worse-than-short-lived
date: 2026-09-04
category: resolved
severity: major
status: resolved
phase: 5
subsystem: workbench-shell
jac_version: "0.37.1"
related_vscode_ref: "src/vs/workbench/services/files (IFileService.onDidFilesChange), src/vs/workbench/contrib/files/browser/explorerService.ts"
upstream_issue: ""
tags: [sse, generator, isolation, streaming, polling, file-watching, real-user-qa]
---

## What happened

Building a general workspace-file-change watcher for the Explorer tree (`file_tree.jac` needed to
know when a file appeared/disappeared on disk from any cause -- an AI tool, a terminal command,
`git checkout`, another program), the first design was an indefinite SSE stream:
`watch_workspace_changes() -> Generator`, opened once when a workspace opens and left running,
polling the filesystem itself, for the whole remaining lifetime of the mounted component.

This was a real, live-reproduced regression: the moment that stream started running on a real
`jac run --serve --dev` process, `list_children_by_path` -- an unrelated, pre-existing function
this change never touched -- started failing server-wide with a graph-consistency error, for the
rest of that process's life. See tracker entry
`2026-09-04-list-children-by-path-crashes-on-unexpected-contains-target` for that error itself
(which turned out to be a separate, genuinely pre-existing bug once investigated further -- but the
*timing correlation* with the indefinite stream starting was strong enough to warrant real
investigation before ruling it out, and the indefinite-stream design was a real problem in its own
right regardless of that other bug's actual root cause).

## Why this matters beyond the one symptom

This project already has three tracker entries documenting that `Generator`-returning SSE endpoints
in this codebase can run isolated from ordinary `def:pub` calls in ways that produce unreliable
access to shared, `root`-keyed global/graph state
(`2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state`,
`2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run`,
`2026-09-05-sse-generator-root-scoped-graph-query-unreliable`). Every one of those was about a
*short-lived* stream -- one chat turn, one debug session -- that naturally disconnects once its
single unit of work finishes. This was the first *indefinite* one in this codebase: reconnected on
every workspace-open, otherwise left running for a whole browsing session, with no natural end.

Whatever mechanism produces that isolation risk, a connection that never disconnects gives it far
more opportunity to interfere with other requests than one that lasts seconds. This is a real,
actionable severity distinction worth keeping in mind for any future streaming endpoint in this
codebase: **short-lived, self-terminating SSE streams have an established, if imperfectly
understood, risk profile in this project; an always-on one is a materially different, more
dangerous shape**, not just "the same risk, more often."

## What VS Code does for the same underlying need (checked directly, real checkout)

Real VS Code's own `IFileService.onDidFilesChange` *is* effectively an always-on stream -- but it's
architecturally nothing like this project's SSE-over-HTTP mechanism. VS Code is a single-user
desktop (Electron) process: the file watcher lives in the same OS process as everything that
consumes it (or a dedicated watcher process communicating over IPC, not HTTP), with no separate
server, no per-request database transaction, and no multi-tenant `root`-keyed global state to
isolate. There is no analogous "SSE-generator isolation" risk for it to have, because the
architectural feature that creates that risk here (a real client/server HTTP boundary, a shared
process serving multiple users' `root`-scoped graph state) doesn't exist in VS Code's design at
all. This is not "VS Code solved this problem more cleverly" -- it's "VS Code's architecture never
has this problem in the first place." The applicable lesson isn't to copy VS Code's own always-on
stream; it's that *this* project's own streaming mechanism has a real, already-documented cost that
VS Code's doesn't, and that cost should weigh against reaching for an indefinite stream here even
when the same feature in VS Code itself happens to be one.

## The fix

Replaced the SSE stream with a plain, ordinary `def:pub check_workspace_changes(root_path,
last_snapshot) -> dict` function -- the identical request/response shape `list_children_by_path`
itself, and every other polled-from-the-client call in this codebase, already use safely.
`file_tree.jac` polls it on a client-side `setInterval`, passing its own last snapshot back each
call so the server side stays completely stateless: no lingering task, no connection to leak,
nothing to abort when a different workspace opens (`clearInterval` is the entire cleanup, simpler
than the `AbortController` the streaming version needed). Verified directly against the running
server with `curl`: creating a file mid-poll-window produces the correct `changed_dirs` on the next
call, and the function keeps succeeding under repeated calls with no degradation over time.

## Plan

This is `resolved`, not a stopgap: avoiding an indefinite `Generator`-returning endpoint for any
future feature in this codebase (client-side polling of an ordinary `def:pub` function instead,
wherever the underlying need doesn't genuinely require true push/streaming) is the correct,
permanent practice given this project's own demonstrated SSE-generator-isolation risk profile, not
something to revisit once that risk is better understood. If a future feature genuinely needs a
long-lived server-to-client push (not just "check periodically"), that would be the point to
properly investigate the isolation mechanism itself rather than route around it again.
