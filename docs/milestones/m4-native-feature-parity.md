# M4 — Native feature parity

**Status**: substantially complete, 2026-09-02

Search, source control, tasks/diagnostics, and real language intelligence, using only trusted,
in-process, build-time-loaded Jac modules.

## Shipped
| PR | What |
|---|---|
| #47 | Toast notifications + notification center. |
| #48 | Output panel with log-channel abstraction (`output_service.jac`'s `OutputChannel`, a plain `obj`). |
| #49 | Search-in-files, reading from the file graph. |
| #50 | SCM shell + git provider: status/diffs, stage/unstage/discard/commit, gutter + tree decorations. |
| #51 | Task runner with problem matchers, feeding the `Diagnostic` node type staged in M3. |
| #52–#58 | Native Jac LSP client against `jac lsp`: completion + diagnostics, hover, go-to-definition, find-references, rename with multi-file bulk-edit, outline sidebar, breadcrumb bar. |
| #60 | Native DAP client via `debugpy` against jaclang-compiled bytecode: breakpoints, step, call stack, variables. |
| #61 | Merge-conflict resolution UI. |
| #62–#67 | Polish from manual testing: sidebar `offcanvas` click-swallowing fix, Quick Input restyle + F1/Command Palette unification, breadcrumb bar cursor-tracking fix, debug-session failure diagnosis, `get_or_create_workspace` cache-invalidation fix. |

## Decisions
- [ADR 0043](../decisions/0043-vsix-as-phase-4-compatibility-test-case.md) (superseded by [0046](../decisions/0046-defer-vsix-compatibility-research.md)), [0044](../decisions/0044-native-feature-parity-before-extension-compatibility.md), [0045](../decisions/0045-native-lsp-client-against-jac-lsp.md), [0047](../decisions/0047-dap-client-is-native-infrastructure.md), [0050](../decisions/0050-debugpy-as-the-dap-adapter.md), [0051](../decisions/0051-lsp-and-dap-reuse-the-terminal-gate.md), [0052](../decisions/0052-contribution-registry-is-a-centralized-list.md).

## Deviations from plan
- The "zero changes to existing workbench code" exit criterion was not achieved: `command_registry.jac`'s `BUILTIN_COMMANDS` and `activity_bar.jac`'s `VIEWS` are centralized lists, not self-registering contributions — every feature this milestone added required editing them directly.
- The breadcrumb bar (#58) shipped with cursor-tracking that silently never worked; its own docstring described behavior the code never implemented. Neither `jac check` nor `jac test` caught it.
- PR #67's bug was misdiagnosed for a full day (4 fix attempts chasing a jaseci edge-durability theory) before the real one-line cache-invalidation cause was found.

## Blockers logged
- `2026-08-22-lsp-dap-client-unresearched` (major, resolved this milestone).
- `2026-08-31-jaclang-no-native-dap-server-but-debugpy-works-against-compiled-jac-source` (minor, workaround).
- `2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache` (blocker, workaround).
- `2026-08-31-open-read-return-must-be-inline-in-with-block-not-assigned` (minor, resolved).
- `2026-08-31-background-task-graph-writes-never-auto-committed` (blocker, workaround-found).
- `2026-08-31-client-import-of-server-function-always-compiles-async-regardless-of-sync-ness` (major, workaround).
- `2026-08-31-client-module-with-one-server-import-pulled-server-wholesale` (major, workaround-found).
- `2026-08-31-anchor-free-root-using-module-pulled-client-wholesale` (major, workaround).
- `2026-08-31-mount-once-hide-via-css-view-races-later-workspace-open` (major, resolved).
- `2026-08-31-useeffect-explicit-none-return-crashes-as-non-function-destroy` (minor, resolved).
- `2026-08-31-fixed-sidebar-overlaps-and-intercepts-clicks-on-bottom-panel`, `...also-intercepted-clicks-on-the-activity-bar` (both major, resolved).
- `2026-09-01-sse-generator-endpoint-runs-in-isolated-process-no-shared-glob-state` (major, workaround).
- `2026-09-01-folder-scan-flag-permanently-stuck-after-edge-loss` (major, resolved this milestone, corrected 2026-09-02).
- `2026-09-02-dap-client-generic-spawn-failure-hid-missing-debugpy` (minor, resolved).
- `2026-08-31-workspace-rescan-orphans-reports-edges-on-repeat-open` (major, **still open**) — a second request against an already-open workspace can fail to materialize the cached `Workspace` anchor, orphaning `Reports` edges.

## Left open
- `2026-08-31-workspace-rescan-orphans-reports-edges-on-repeat-open` needs a dedicated isolated repro.
- The contribution-model gap should be resolved or explicitly re-scoped before M11's dynamic extension loading.
- "Docstring describes correct behavior, code doesn't" is an unautomated failure class, hit twice this milestone.
- `vscode`-API compatibility scope and VS-Code theme extension support remain open in `architecture.md`.
