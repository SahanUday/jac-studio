# M3 — Persistence and identity

**Status**: complete, 2026-08-28

Closing and reopening the app restores the previous session; settings persist; opened files show
real syntax highlighting; two file versions can be diffed; the workbench chrome matches VS Code's
current default look.

## Shipped
| PR | What |
|---|---|
| #34 | `Diagnostic` node type attached to `File` — data model only, no producer yet. |
| #35 | Persisted settings and keybinding overrides (`settings_service.jac`, `KeybindingOverrides`). |
| #36 | Workspace-state persistence and restore (`session_service.jac`) — groups, active group, terminal state, cursor positions. |
| #37 | Diff-editor rendering mode (`monaco_diff_editor.jac`), Alt+Click "select for compare". |
| #38 | Syntax highlighting confirmed live via `jac browse`; `jac_language.jac` Monarch tokenizer for `.jac`; minimap enabled. |
| #39 | Retheme to VS Code's actual default ("Dark 2026"/"Light 2026", not "Dark+"/"Light+") via native `jac retheme` OKLCH tokens; icons swapped to `@vscode/codicons`. |
| #40 | Quick Open (Ctrl+P) — a documented-but-undelivered M2 item, shipped here. |
| #41 | Activity bar — hand-built view switcher. |
| #42 | Title bar with a Command Center pill. |
| #43 | File-tree context menu (new/rename/delete, compare pair); finished the codicons swap for shadcn-generated primitives. |
| #44 | Tab affordances: file-type icons, unsaved-changes indicator. |

## Decisions
- [ADR 0028](../decisions/0028-persist-state-by-graph-reachability.md), [0029](../decisions/0029-cache-the-jid-not-the-node.md), [0030](../decisions/0030-filesystem-authoritative-file-tree-reads.md), [0031](../decisions/0031-never-del-a-graph-significant-cache-key.md), [0032](../decisions/0032-match-vscode-default-identity-natively.md) (superseded by [0033](../decisions/0033-target-dark-2026-and-real-codicons.md)), [0034](../decisions/0034-rely-on-monaco-bundled-tokenizers.md), [0035](../decisions/0035-register-a-monarch-tokenizer-for-jac.md), [0036](../decisions/0036-diffeditor-model-retention-props.md), [0037](../decisions/0037-pre-create-diff-models-for-language-detection.md), [0038](../decisions/0038-minimap-on-in-editor-off-in-diff.md), [0039](../decisions/0039-quick-open-uses-os-walk.md), [0040](../decisions/0040-activity-bar-is-a-hand-built-switcher.md), [0041](../decisions/0041-reverify-triage-against-live-upstream.md), [0042](../decisions/0042-stage-diagnostic-node-before-any-producer.md).

## Deviations from plan
- Roughly half the milestone's scope (retheme, Quick Open, activity bar, title bar, context menu) was added mid-milestone, found via conversation and a live-source check against `microsoft/vscode`, not present in the original bullet list.
- The field-mutation persistence bug (below) was only caught because the exit criteria forced a real restart test — every earlier milestone's persistence code had only run against a continuously-running server.
- `jac install --shadcn <name>` reintroduced `@hugeicons` for every new primitive pulled in after #39 thought the icon migration was done.

## Blockers logged
- `2026-08-28-field-mutation-on-cached-node-not-persisted` (blocker, workaround) — this milestone's most significant finding; a `has`-field mutation on a cached node was never durably committed.
- `2026-08-28-jac-db-cli-wrong-database-multiple-top-level-jac-files` (minor, open).
- `2026-08-28-edge-deletion-not-committed-across-real-http-requests` (blocker, workaround).
- `2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability` (major, workaround).
- `2026-08-28-shadcn-command-dialog-leaks-dialog-root-props-onto-content` (minor, open).
- `2026-08-28-client-dict-del-unsupported-by-jac2js` (major, workaround).

## Left open
- Edge-deletion durability is a workaround (filesystem-authoritative reads), not a fix; the underlying jaseci gap is still open.
- `jac install --shadcn` will keep reintroducing `@hugeicons` for new primitives.
- `jac-db-cli-wrong-database` tooling gap still open.
- Extension-system `vscode`-API compatibility scope and VS-Code-theme-extension support remain open questions in `architecture.md`.
- No regression tests exist for cache-the-jid-not-the-node or the edge-deletion workaround beyond manual `jac browse` restart tests.
