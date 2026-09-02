# Phase 4 — Native built-in features + language intelligence (extension system Phase A)

Status: **substantially complete** — 2026-09-02. Every feature `roadmap.md` scoped into this phase
has shipped and been live-verified: search-in-files, a real git SCM shell with a merge-conflict UI,
a task runner feeding a Problems panel, a full native Jac LSP client (completion, hover,
go-to-definition, find-references, rename with real multi-file bulk-edit, outline, breadcrumbs), a
native DAP client (breakpoints, step, call stack, variable inspection), an Output panel with a
log-channel abstraction, and toast notifications + a notification center. One exit criterion —
"a fourth built-in feature can be added purely by writing a new contributing module, with zero
changes to existing workbench code" — was **not** achieved as literally worded; see "Deviations"
below for what was actually built instead and why that's a real, worth-tracking gap rather than a
rounding error. Read this before touching search, SCM, tasks, the LSP/DAP clients, or the
contribution registries (`command_registry.jac`, `activity_bar.jac`'s `VIEWS`) — it's the fastest
way to get oriented without re-reading 21 PRs from scratch.

## Goal (from roadmap.md)

Reach real VS-Code feature parity for the features that make an editor useful day to day — search,
source control, tasks/diagnostics, and genuine language intelligence — using only trusted,
in-process, build-time-loaded Jac modules, with zero dependency on dynamic loading, a manifest
format, or any `.vsix`/`vscode`-API compatibility work.

## What was actually built (PRs #47–#67)

**Toast notifications + a notification center** (PR #47) — `workbench/browser/parts/notifications`
territory, found missing from the original architecture proposal only by checking VS Code's live
source directly (see Phase 3's own closing doc). A genuine prerequisite, not polish: SCM, the task
runner, and the LSP client below all need a way to report background success/failure with no other
UI surface for it.

**Output panel with a log-channel abstraction** (PR #48) — `output_service.jac`'s `OutputChannel`
is a plain, `jid(root)`-keyed `obj`, not a graph node (per `architecture.md`'s "not every service
needs to be a node" rule) — moved earlier than upstream's own scale would suggest specifically
because it's needed to surface `jac lsp`'s and the DAP client's own logs, both landing later in
this same phase.

**Search-in-files** (PR #49) — workspace-wide text search reading from the file graph.

**Source control (SCM) shell + a git provider** (PR #50) — a provider-agnostic SCM view with git as
the first real implementation, talking to the `git` CLI the same way the terminal talks to any
other process. Real status/diffs, stage/unstage/discard/commit, gutter + tree decorations — "a real
first-class workbench part," not a status indicator.

**Task runner with problem matchers** (PR #51) — writes into the `Diagnostic` node type Phase 3
staged with no producer, feeding a Problems panel. First real prototype of "the contribution model
handles a feature with its own persistent config format," per the roadmap's own framing.

**Native Jac LSP client** (PRs #52–#58) — the phase's flagship deliverable, built directly against
`jac lsp` (a real, already-shipped language server in `jaclang.lsp.server.server`), not against any
external client library:
- #52 — completion + live diagnostics (spawns `jac lsp` as a subprocess, LSP JSON-RPC-over-stdio)
- #53 — hover
- #54 — go-to-definition
- #55 — find-references
- #56 — rename, including real multi-file bulk-edit application (a rename provider that can't
  apply its own result isn't done, per the roadmap's own framing)
- #57 — an outline sidebar view (call-hierarchy explicitly out of scope — `jac lsp` has no
  call-hierarchy handler to wire up against, not silently dropped)
- #58 — a breadcrumb bar tracking the cursor's symbol chain (its cursor-tracking wiring shipped
  with a real bug — see "Blockers" below — caught and fixed later in the phase, PR #65)

**Native Debug Adapter Protocol client** (PR #60) — confirmed live, end to end, before writing a
line of the client: `jaclang` ships no DAP server of its own, but `debugpy` works directly against
jaclang-compiled bytecode (`co_filename`/line tables map 1:1 to real `.jac` source), so no
source-translation step was needed. Set a breakpoint, start a session, step through, inspect the
call stack and variables — a real DAP adapter, not a `pdb` shim exposed as if it were one.

**Merge-conflict resolution UI** (PR #61) — alongside the SCM work above, since real conflicts only
exist once real git integration does. Distinct from the two-way diff editor Phase 3 already shipped.

**Polish and bugfixes found via real manual testing** (PRs #62–#67) — this phase's own version of
Phase 2's "first-ever real browser verification" pass:
- #62 — the sidebar's `offcanvas` positioning was overlapping and swallowing clicks in the Activity
  Bar's own column; fixed with `<Sidebar collapsible="none">`, the vendored primitive's own
  persistent-in-flow-panel variant.
- #63 — Command Palette/Quick Open restyled to match real VS Code's actual dark Quick Input chrome
  (the shipped shadcn scaffold rendered as a plain light dialog), plus unifying Monaco's own
  built-in `F1` action with the real workbench Command Palette.
- #64 — that F1 unification actually registered a *second*, independent context-menu entry rather
  than replacing Monaco's built-in one (two different Monaco menu-registration mechanisms, confirmed
  by reading Monaco's own source); fixed by re-registering the built-in command id in
  `CommandsRegistry` directly. Same PR also fixed a debug-session restart hang (a trailing SSE
  `event: end` frame crashing `JSON.parse` before `session_active` could reset).
- #65 — the breadcrumb bar from PR #58 never actually updated on cursor move: its own module
  docstring always described `handle_cursor_change` calling `update_breadcrumb`, but the real
  function body only ever reported the position to the status bar. One-line fix, plus a matching
  Outline-panel restyle (chevrons/indent parity with the file tree, current-symbol highlighting).
- #66 — a debug session that failed to start (missing `debugpy`) surfaced as a silent 15-second
  timeout ending in a generic "Failed to start the debug session," with zero diagnosis possible from
  the UI. Now checks explicitly and reports the real reason.
- #67 — `get_or_create_workspace` (called by every SCM function just to resolve the repo root)
  unconditionally wiped the Explorer's whole cache of already-expanded folders on every call, even
  when nothing needed to reset — simply having the SCM panel open silently emptied out the file
  tree. Root-caused via direct terminal-log inspection, not guesswork; corrects a tracker entry that
  had spent 4 failed attempts chasing an unrelated jaseci edge-durability theory (see "Blockers").

## Key decisions made

**Language intelligence needed no client library research at all — the LSP/DAP "unresearched"
question from `2026-08-22-lsp-dap-client-unresearched` was answered by discovering both servers
already existed.** `jac lsp` is a real, first-party, already-shipped language server; `debugpy`
works unmodified against jaclang bytecode. The actual work in both cases was "spawn a subprocess,
speak a JSON-RPC wire format" — the same shape the terminal already used for arbitrary processes,
not a new integration pattern. This is why the LSP+DAP work moved from "future research" to
flagship-phase status in the 2026-08-31 re-prioritization (`roadmap.md`'s top-of-doc note).

**Gated behind the same `[terminal] enabled` flag as the terminal, for both the LSP and DAP
clients.** Spawning `jac lsp`/`python -m debugpy` is a subprocess execution — the same trust class
already gated project-wide, not a new capability boundary invented for this phase.

**`rename`'s bulk-edit application was treated as part of the same deliverable as the rename
provider itself**, not a separately-scoped follow-up — matching the roadmap's own explicit framing
that "a rename provider that can't apply its own result isn't done."

**The breadcrumb bar and outline view intentionally share one containment primitive**
(`breadcrumb_symbols.jac`'s `symbol_path_at_position`), not two parallel implementations — PR #65's
Outline restyle reused it for current-symbol highlighting, the same pure function the breadcrumb bar
already computed its chain from.

## Deviations from the original plan (found by actually building, not assumed upfront)

**The "self-registering contribution model" `architecture.md` describes was not actually built this
way, and the roadmap's "zero changes to existing workbench code" exit criterion was never
achieved as literally worded.** What's real: `command_registry.jac`'s `BUILTIN_COMMANDS` and
`activity_bar.jac`'s `VIEWS` are each a single, centralized, hardcoded list — every new command or
sidebar view this phase added (search, SCM, tasks, outline, debug console, ...) required editing
that shared list directly, plus a render/wiring line in `workbench.jac`. This is a real,
low-friction pattern (`outline.jac`'s own docstring calls it "a one-entry addition... no new
plumbing," and that held true in practice for every feature added this phase) but it is not a
module that self-registers into the graph the way `architecture.md`'s "Extension nodes ... Contribute
Command/View/Menu nodes" framing describes — no feature this phase shipped went in without touching
`command_registry.jac`/`activity_bar.jac`/`workbench.jac`. Worth a deliberate look before Phase 6
(dynamic extension loading) tries to build real third-party contribution on top of whatever this
pattern currently is — a centralized list works fine for build-time-only, trusted, first-party
features; it's not obviously the right foundation for a manifest-driven extension marketplace.

**Two features shipped with real, live-only bugs that `jac check`/`jac test` couldn't catch, caught
only by manual testing after the fact, not before shipping.** The breadcrumb bar (PR #58) shipped
with cursor-tracking that silently never worked at all — the module's own docstring described
correct behavior that the code never actually implemented, and nothing short of moving the cursor
in a real browser session would have caught it. The debug session's generic failure message (fixed
in #66) is the same class of gap: a real, correctly-guarded error path that was technically
"working" but gave a user nothing to act on. Both are now fixed, but the pattern — a docstring
describing intended behavior that drifted from the actual implementation, undetected by the type
checker or test suite — is worth watching for, not assumed closed by these two fixes alone.

**One bug (PR #67) was misdiagnosed for a full extra day before the real fix was found**, and the
misdiagnosis consumed four separate fix attempts (tracker entry
`2026-09-01-folder-scan-flag-permanently-stuck-after-edge-loss`, now corrected) chasing a jaseci
`Contains`-edge read-after-write theory that was very likely never the actual cause of the reported
symptom. The real bug was a one-line application-level cache-invalidation mistake in
`get_or_create_workspace`, found only once a terminal log showed the SCM panel's own background RPC
calls sitting right next to the reported failure. Worth internalizing: when a "same symptom,
different session" bug resists a plausible-sounding theory across multiple attempts, checking what
*else* was happening around the failure (not just re-attempting variations on the leading theory) is
worth doing earlier, not as a last resort.

## Blockers logged during this phase

- `2026-08-22-lsp-dap-client-unresearched` (major, **resolved this phase**) — the doc-gap this
  entry raised was fully answered by shipping both clients; see "Key decisions" above.
- `2026-08-31-jaclang-no-native-dap-server-but-debugpy-works-against-compiled-jac-source` (minor,
  workaround) — the concrete recipe PR #60's DAP client is built on; see "What was actually built"
  above.
- `2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache` (blocker, workaround) — found
  building search-in-files: a `glob` cache reused across modules read empty across a cross-module
  call in a way a same-module call didn't. Real jaseci-level surprise, worked around in
  `search_service.jac`.
- `2026-08-31-open-read-return-must-be-inline-in-with-block-not-assigned` (minor, resolved) — also
  found building search-in-files: `with open(...) as f { return f.read(); }` needed the return
  inlined inside the `with` block, not assigned then returned after — a real, narrow compiler
  gotcha, not a design choice.
- `2026-08-31-background-task-graph-writes-never-auto-committed` (blocker, workaround-found) — found
  verifying the LSP client live: a background `asyncio.create_task`'s graph writes need an explicit
  `Jac.commit()`, since there's no request boundary to auto-commit against. This project's own
  established fix for the class of problem, reused directly.
- `2026-08-31-client-import-of-server-function-always-compiles-async-regardless-of-sync-ness` (major,
  workaround) and `2026-08-31-client-module-with-one-server-import-pulled-server-wholesale` (major,
  workaround-found) — two real `jac2js` placement-solver surprises found wiring the LSP client's
  purely-client-side helpers, both now documented as standing gotchas (`jac-language` skill).
- `2026-08-31-anchor-free-root-using-module-pulled-client-wholesale` (major, workaround) and
  `2026-08-31-mount-once-hide-via-css-view-races-later-workspace-open` (major, **resolved**) — found
  building the Output panel; the second is the same "view mounts once, hidden via CSS, races a later
  workspace open" shape `scm.jac`/`outline.jac` had already established a fix pattern for.
  `2026-08-31-useeffect-explicit-none-return-crashes-as-non-function-destroy` (minor, resolved) —
  also found in the Output panel's polling `useEffect`.
- `2026-08-31-fixed-sidebar-overlaps-and-intercepts-clicks-on-bottom-panel` and
  `2026-08-31-fixed-sidebar-also-intercepted-clicks-on-the-activity-bar` (both major, resolved) —
  two earlier band-aid attempts at the sidebar overlap bug PR #62 actually fixed at the root.
- `2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state` (major,
  workaround) — the DAP client's own real finding: a `Generator`-returning SSE endpoint runs in a
  genuinely separate execution context from every other function in the same module; no shared
  `glob` reaches it. Worked around with a file-based command channel
  (`dap_client.jac`'s `_DAP_COMMAND_FILE`).
- `2026-09-01-folder-scan-flag-permanently-stuck-after-edge-loss` (major, **resolved this phase**,
  corrected 2026-09-02) — see "Deviations" above for the full misdiagnosis-then-real-fix story.
- `2026-09-02-dap-client-generic-spawn-failure-hid-missing-debugpy` (minor, resolved) — PR #66's own
  finding, see "What was actually built" above.
- `2026-08-31-workspace-rescan-orphans-reports-edges-on-repeat-open` (major, **still open, not
  addressed this phase**) — a genuinely separate bug from the `_path_index` one above: a second
  request against an already-open workspace can apparently fail to `jobj()`-materialize the cached
  `Workspace` anchor, silently tripping the "different root" rescan branch and orphaning any
  `Reports` edges attached to the old `File` node identities (first made visible by this phase's own
  `Diagnostic`/`Reports` data, the first feature to attach durable per-file state at all). Not fixed
  — `get_or_create_workspace` is core, heavily-depended-on infrastructure, and the entry's own author
  judged a rushed fix riskier than the bug. See its Plan section for the isolated repro this needs
  before a real attempt.

## What's left / suggested next steps

Phase 4's *features* are all shipped and live-verified, but two things should happen before
calling the phase truly closed, and a few real gaps carry forward regardless:

1. **`2026-08-31-workspace-rescan-orphans-reports-edges-on-repeat-open` is still open** and sits in
   exactly the same file (`workspace_service.jac`) this phase's own PR #67 just finished fixing a
   different bug in. Worth a dedicated, isolated repro (the entry's own Plan section) before any
   future feature attaches more durable per-file state via a custom edge type — diagnostics is the
   first, not the last, feature that will make this kind of silent data loss visible.
2. **The contribution-model gap (see "Deviations" above) should be resolved, or explicitly
   re-scoped, before Phase 6's dynamic extension loading starts.** A manifest-driven,
   runtime-loaded extension needs a real way to contribute commands/views without a maintainer
   hand-editing `command_registry.jac`/`activity_bar.jac` for every third-party extension —
   the current centralized-list pattern doesn't obviously extend to that. Either build the real
   self-registering mechanism `architecture.md` originally described, or update that doc to reflect
   what was actually built and why the centralized-list approach is the deliberate, permanent
   choice for first-party features.
3. **Watch for more "docstring describes correct behavior, code doesn't actually do it" gaps** —
   found twice this phase (breadcrumb cursor-tracking, the debug-session error message), neither
   caught by `jac check`/`jac test`, both only found by a human actually using the feature. Nothing
   currently automates this class of check; manual verification against a real running server stays
   load-bearing, not a formality.
4. **The still-open questions from `architecture.md` remain genuinely open**: how much VS Code
   `vscode`-API compatibility to target for the extension system, whether jac-studio ever supports
   installing VS-Code-compatible third-party theme extensions, and which native AI coding-tool
   integrations get built in what order (Phase 5, next).
5. Per `roadmap.md`, **Phase 5 (native AI coding-tool integrations) is next** — Copilot, OpenCode,
   and Claude Code, each via the same subprocess/SDK pattern the LSP and DAP clients already
   established in this phase, each needing its own auth/licensing scoping pass before
   implementation starts.
