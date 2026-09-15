# M2 — Workbench shell

**Status**: complete, 2026-08-25

A folder can be opened, browsed in a lazy tree, multiple files opened in tabs, the editor split
into resizable groups, and commands run via the palette or scoped keybindings.

## Shipped
| PR | What |
|---|---|
| #16, #17 | File tree sidebar: lazy, expand-on-demand over the `Workspace/Folder/File` graph (eager traversal measured ~3s at real scale). |
| #18 | Tabs, wired to the file tree. |
| #19 | Editor engine reversed to Monaco (`monaco-editor` npm package), replacing the ported piece-tree engine from M1. Native engine archived at `internal/native-editor-archive/`. |
| #21 | Editor-group splitting via shadcn `Resizable`. |
| #22 | Command palette (`Command`/`CommandDialog`) backed by a graph `CommandRegistry`. Execution stays client-side. |
| #23 | Status bar (cursor position only). |
| #24 | Integrated terminal: xterm.js, SSE-streamed process output, deny-by-default via `[terminal] enabled` in `jac.toml`. One process per Enter press, no persistent shell session. |
| #25 | Keybinding "when clause" context system: capture-phase keydown listener matches combos against `Command.keybindings`, evaluated against a flat `context` dict. |
| #26, #27 | First real-browser verification pass (`jac browse`) — found and fixed 7 real bugs: missing global stylesheet, `CommandDialog` missing its `cmdk` root wrapper, terminal sizing/CSS, dark mode never activated, `get_or_create_workspace` ignoring a changed root path, a graph-node duplication race, and Monaco's shared-model disposal on tab close. |

## Decisions
- [ADR 0006](../decisions/0006-root-spawn-instead-of-rpc-protocol.md), [0020](../decisions/0020-editor-engine-is-real-monaco.md), [0021](../decisions/0021-keep-current-model-for-shared-monaco-models.md), [0022](../decisions/0022-command-execution-stays-client-side.md), [0023](../decisions/0023-read-side-dedup-not-write-side-locking.md), [0024](../decisions/0024-jac-browse-is-required-verification.md), [0025](../decisions/0025-terminal-gate-is-jac-toml-flag.md), [0026](../decisions/0026-terminal-v1-one-process-per-command.md), [0027](../decisions/0027-keybinding-when-clause-system-in-phase-2.md).

## Deviations from plan
- No real browser verification happened until after all 8 roadmap bullets had shipped — PRs #26/#27 exist because of it.
- Regression tests were not written alongside the #26/#27 fixes.
- Real ARIA semantics were not built into the workbench-shell components as planned.
- Tracker entries for the browser-verification findings were logged only when this doc was written, not in the same sitting.

## Blockers logged
- `2026-08-22-graph-fanout-dedup` (resolved).
- `2026-08-24-client-dict-literal-variable-key-miscompiles` (workaround).
- `2026-08-24-client-import-alias-breaks-rpc-route-name` (workaround).
- `2026-08-24-jac-run-persists-state-jac-clean-does-not-reset` (resolved, corrected 2026-08-25).
- `2026-08-24-test-annex-self-import-breaks-unrelated-runs` (workaround).
- `2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale` (resolved).
- `2026-08-25-editor-core-decision-reversed-to-monaco` (resolved).
- `2026-08-25-root-test-sweep-crosses-internal-subproject-boundary` (workaround).
- `2026-08-25-shadcn-command-generator-missing-root-wrapper` (workaround-found).
- `2026-08-25-write-conflict-never-raised-session-commit-blind-retries` (workaround-found) — most significant finding of the milestone.

## Left open
- ARIA semantics retrofit for `file_tree.jac` and `editor_tabs.jac`.
- Regression tests for the #26/#27 fixes, especially read-side dedup in `list_commands`/`list_children_by_path`.
- `ResizeObserver loop completed with undelivered notifications` warning is mitigated, not root-caused.
- M3's persistence work must design around the `WriteConflict`-never-fires gap from the start.
- Quick Open (Ctrl+P) was scoped into this milestone by the triage doc but never built — carried into M3.
- Activity bar, title bar, auxiliary bar, and notifications (`workbench/browser/parts/*`) were never triaged at all — carried into M3/M4.
