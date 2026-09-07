---
id: 2026-09-04-list-children-by-path-crashes-on-unexpected-contains-target
date: 2026-09-04
category: workaround-found
severity: major
status: workaround
phase: 5
subsystem: workbench-shell
jac_version: "0.37.1"
related_vscode_ref: ""
upstream_issue: ""
tags: [graph, cache-consistency, isinstance, hasattr, file-tree, real-user-qa, hmr, upstream-jaclang]
---

## What happened

A real user (the project sponsor) reported that jac-studio's Explorer file tree would
intermittently disappear after the app had been running for a while, on a real, long-running
`jac run --serve --dev` process. Their own terminal log showed the exact failure repeating on every
subsequent action:

```
Executing function 'list_children_by_path' with params: {'parent_path': '/home/.../testing-workspace'}
  127.0.0.1 - "POST /function/list_children_by_path HTTP/1.1" 500
✖ Error: error[E7003]: Uncaught Exception in client code: Function list_children_by_path failed:
  {"ok": false, "type": "error", "data": null,
   "error": {"code": "EXECUTION_ERROR", "message": "'Workspace' object has no attribute 'path'"}}
```

Once triggered, every subsequent `list_children_by_path` call on that server process failed
identically, for the rest of that process's life -- the Explorer tree stayed permanently broken
until a restart.

## Investigation

Initially suspected a newly-added, always-on SSE watcher (`workspace_watcher.jac`,
`watch_workspace_changes() -> Generator`) added the same day, on the theory that this project's own
already-documented SSE-generator-isolation risk (see tracker entries
`2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state`,
`2026-09-02-sse-generator-glob-isolation-not-reproduced-single-process-dev-run`,
`2026-09-05-sse-generator-root-scoped-graph-query-unreliable`) might be interfering with
`list_children_by_path`'s own `_path_index`/`_cached_workspace_jid` globals, given that watcher was
the first *indefinite* Generator-returning endpoint in this codebase (every prior instance of that
risk was a short-lived stream -- one chat turn, one debug session -- that disconnects on its own).

**Ruled out directly, empirically**: a fresh `curl` call to the new watcher's own
`check_workspace_changes` function succeeded on the exact same request where `list_children_by_path`
failed. The user separately confirmed they had seen the file tree disappear *before* the watcher
ever existed. The watcher redesign (replacing the SSE stream with a plain polled `def:pub` function,
since an indefinite stream was a real regression in its own right regardless of this bug) was kept,
but is a separate fix, not this one.

**The exact trigger for a `Workspace` node ending up where `list_children_by_path` expects a
`Folder`/`File` (a `Contains`-edge target under the open workspace's own root) was not pinned down.**
A targeted `jac test` reproducing the most obvious candidate -- opening a second workspace root,
then reopening the first, then listing -- passed cleanly. Given `get_or_create_workspace`'s own
docstring already documents a real, acknowledged-but-not-closed race ("`_workspace_lock` narrows but
doesn't close" the gap between this project's per-function lock releasing and the underlying
Postgres commit actually landing, confirmed via `command_registry.jac`'s own root-cause writeup),
the most likely explanation is a variant of that same class of issue -- a real overlapping-HTTP-
requests timing window `jac test`'s single-process synchronous execution structurally cannot
reproduce, the same limitation that file's own docstring already states for the sibling race.

## The fix

`list_children_by_path` (`src/workbench/workspace/workspace_service.jac`) now skips any
`Contains`-edge target that isn't actually a `Folder`/`File`, instead of crashing on it -- the same
"the read path is the actual source of truth, regardless of what the graph underneath holds" stance
this function already takes for a duplicate-node case and a stale-edge-deletion case (see its own
docstring, and tracker entries `2026-08-28-edge-deletion-not-committed-across-real-http-requests`).

**A genuinely surprising secondary finding along the way**: the natural way to write this guard,
`isinstance(child, (Folder, File))`, raised the *identical* `'Workspace' object has no attribute
'path'` error -- one line earlier than the crash it was meant to prevent. `hasattr(child, "path")`
does not. Confirmed both ways directly: a regression test constructing a `Workspace` as a `Contains`
target (`ws +>:Contains():+> Workspace(root_path="/somewhere/else")`) was written, confirmed it
raises the exact production error with no guard, then confirmed it still fails at the `isinstance`
line specifically when that form is used, and only passes with `hasattr`. The mechanism wasn't
investigated further (outside this fix's scope), but the practical lesson holds: don't assume
`isinstance()` against a Jac node archetype behaves like a plain Python `type()` check when the
value being tested might not have the fields the checked-against type declares.

## Plan

The underlying cache-vs-commit consistency question in `get_or_create_workspace` is still open --
this entry documents the crash-prevention fix (a real, permanent, correct practice regardless of
the root cause, matching this file's own established stance) and the `isinstance`/`hasattr` gotcha,
not a closure of the underlying race. If a *reliable* repro for the actual trigger is ever found
(most likely something exercising real concurrent HTTP requests against `open_workspace`/
`get_or_create_workspace`, which `jac test` cannot do on its own), that's the next real step --
either tightening `_workspace_lock`'s guarantee, or moving `_path_index` consistency checks to
always re-verify against fresh graph state (`jobj(jid(...))`) rather than trusting a cached
Python object reference, the pattern this project's own top-of-file docstring already prescribes
for exactly this class of staleness.

## CORRECTION / STRONG NEW CANDIDATE, 2026-09-07: a real trigger mechanism found, source-confirmed,
not yet controlled-repro-confirmed

A separate real-user report (asking the AI Chat to edit `testing-workspace/hello.jac`) included a
terminal log with a detail this entry's original investigation didn't have: the exact crash was
directly preceded by `[HMR] Reloaded: .../testing-workspace/hello.jac` followed by this server's
own full startup banner (`Admin portal endpoints registered`, `LLM telemetry...`, etc.) -- i.e., a
real, in-place **server process restart**, triggered by the AI's own edit to a file inside the
*open workspace*, not by anything in this app's own source changing.

Traced into `/home/sahan/dev/jaseci/jac` (the jaclang compiler itself, a separate project, run here
in dev mode) to confirm this isn't a misreading: `jac run --dev`'s own hot-reload watcher
(`jaclang/server/watcher.jac`'s `JacFileWatcher`, wired up in
`jaclang/cli/commands/impl/execution.impl.jac`) is constructed as
`JacFileWatcher(watch_paths=[base])`, where `base` (`cli_helpers.jac`'s `proc_file`) is simply
`os.path.split(filename)` on the entry-point file (`main.jac`) -- **the whole project root
directory**, watched recursively for `*.jac`/`*.tsx`/`*.js`/`*.css`/`*.png`/`*.jpg`/`*.jpeg`, with
no exclusion mechanism at all beyond `.jac/` (the build-cache dir), `node_modules`, and
`__pycache__` (`watcher.impl.jac`'s `_on_change`). `testing-workspace/` -- this project's own
gitignored fixture, deliberately kept at the repo root per `jac-studio-implementation`'s own
documented convention -- sits directly under that watched root, so **any AI Chat write to a `.jac`
file inside the currently-open workspace is indistinguishable, to jaclang's own dev-mode watcher,
from an edit to jac-studio's own application source**, and triggers the identical hot-reload path a
real source change would.

This would fully explain the original crash here: a hot-reload restart mid-flight, while other
requests are still in-progress against the pre-reload process/module state, is exactly the kind of
window that could leave `_path_index`/`_cached_workspace_jid` (plain in-process globals, keyed to a
specific loaded module's own class identity) holding a reference that no longer matches what a
freshly-reloaded module considers a `Folder`/`File`/`Workspace` to be -- a much more concrete
candidate than the vague "concurrent HTTP requests" theory this entry originally proposed, and one
that also cleanly explains why `jac test`'s synchronous, single-process execution could never
reproduce it (there's no hot-reload watcher running under `jac test` at all).

**Important scope note, also confirmed from source**: `base` is jac-studio's own project root
(wherever `main.jac` lives), not whatever folder a user opens through the app's own "Open workspace"
picker. A real end user running an installed jac-studio pointed at their own, separate project
elsewhere on disk would never hit this -- their project's directory doesn't overlap with
jac-studio's own served root at all. This is specific to *this project's own dev/testing setup*,
where the fixture workspace happens to be nested inside the same repo being served in `--dev` mode.

**Not yet a fully closed, controlled repro** (the standard this project holds itself to) -- the
correlation is from a real user's own terminal log, and the mechanism is confirmed from actual
jaclang source, but no one has yet deliberately triggered an AI-Chat edit to a `.jac` file inside
`testing-workspace/` under a fresh `--dev` server and watched the exact same crash follow, isolated
from every other variable. Immediate, low-cost mitigation recommended regardless of that gap: run
the dev server *without* `--dev` while doing this kind of AI Chat / workspace-editing QA (jaclang's
own watcher setup is entirely gated behind `if dev { ... }`, so omitting the flag removes the
hot-reload path -- and therefore this entire trigger class -- outright), at the cost of losing
client-bundle HMR for jac-studio's own source changes during that session. A real fix would need to
happen upstream in jaclang itself (an exclude-patterns option for `JacFileWatcher`/`watch_paths`,
or scoping the default watch root to the entry-point's own package rather than the whole project
directory) -- outside this repo's own ability to patch, and not attempted here.
