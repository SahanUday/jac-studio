# Architecture decision records

This directory holds one file per architectural decision made in jac-studio — the reasoning,
measurements, live reproductions and reversals that `docs/architecture.md`, `docs/roadmap.md` and
`docs/milestones/*.md` accumulated as narrative, extracted so that rewriting those documents cannot
lose it.

Entries are corrected by **superseding**, never by editing history away: when a decision turns out
to be wrong, the original keeps its number and gets a `superseded by` / `reversed` status pointing
at the replacement. The record of having been wrong is the valuable part — several entries here
exist only because a passing test suite lied and a live reproduction found the truth.

| # | Title | Date | Status |
|---|---|---|---|
| [0001](0001-rewrite-dont-mirror.md) | Rewrite, don't mirror | 2026-08-22 | accepted |
| [0002](0002-redesign-translate-build-fresh.md) | Redesign / translate / build-fresh decision procedure | 2026-08-22 | accepted |
| [0003](0003-graph-as-service-registry.md) | The graph reachable from `root` is the service registry | 2026-08-22 | accepted |
| [0004](0004-workspace-is-the-graph.md) | The workspace is the graph | 2026-08-22 | accepted |
| [0005](0005-shadcn-primitives-for-workbench.md) | Compose the workbench from shadcn-in-Jac primitives | 2026-08-22 | accepted |
| [0006](0006-root-spawn-instead-of-rpc-protocol.md) | Cross-boundary calls are `root spawn`, not an RPC protocol | 2026-08-22 | accepted |
| [0007](0007-terminal-is-core-deny-by-default.md) | The integrated terminal is core, deny-by-default | 2026-08-22 | superseded by [0025](0025-terminal-gate-is-jac-toml-flag.md) |
| [0008](0008-extension-system-phased-trust-model.md) | Extension system: phased trust model A → B → C | 2026-08-22 | accepted |
| [0009](0009-desktop-packaging-deferred.md) | Desktop packaging is deliberately last | 2026-08-22 | accepted |
| [0010](0010-do-not-port-upstream-chat-subsystem.md) | Do not port upstream's chat/agent subsystem | 2026-08-22 | accepted |
| [0011](0011-jac-first-tooling-with-named-exceptions.md) | Jac-first tooling, with narrow confirmed exceptions | 2026-08-23 | superseded by [0067](0067-reuse-proven-libraries-for-solved-problems.md) |
| [0012](0012-translator-supervision-by-risk-tier.md) | Translator supervision scales with risk tier | 2026-08-23 | accepted |
| [0013](0013-cache-service-node-keyed-by-jid-root.md) | Cache each service node once per `root`, keyed by `jid(root)` | 2026-08-23 | superseded by [0029](0029-cache-the-jid-not-the-node.md) |
| [0014](0014-service-cache-test-reset-hook.md) | Every service module exports a test-only cache reset hook | 2026-08-23 | accepted |
| [0015](0015-default-services-to-obj-not-node.md) | Default a service to `obj`; promote to `node` on need | 2026-08-23 | accepted |
| [0016](0016-merge-circularly-importing-modules.md) | Merge circularly-importing modules | 2026-08-23 | accepted |
| [0017](0017-translate-real-dependencies-when-they-are-the-job.md) | Translate real dependencies when that data is the job | 2026-08-23 | accepted |
| [0018](0018-editor-core-continues-native.md) | Editor core continues native | 2026-08-23 | reversed by [0020](0020-editor-engine-is-real-monaco.md) |
| [0019](0019-file-tree-loads-lazily.md) | The file tree loads lazily, expand-on-demand | 2026-08-24 | accepted |
| [0020](0020-editor-engine-is-real-monaco.md) | The editor engine is the real `monaco-editor` package | 2026-08-25 | accepted |
| [0021](0021-keep-current-model-for-shared-monaco-models.md) | Set `keepCurrentModel` so a shared model survives a tab close | 2026-08-25 | accepted |
| [0022](0022-command-execution-stays-client-side.md) | Command execution stays client-side; metadata server-side | 2026-08-25 | accepted |
| [0023](0023-read-side-dedup-not-write-side-locking.md) | Read-side dedup, not write-side locking | 2026-08-25 | accepted |
| [0024](0024-jac-browse-is-required-verification.md) | `jac browse` is required verification for UI work | 2026-08-25 | accepted |
| [0025](0025-terminal-gate-is-jac-toml-flag.md) | The terminal's gate is `[terminal] enabled` in `jac.toml` | 2026-08-25 | accepted |
| [0026](0026-terminal-v1-one-process-per-command.md) | Terminal v1 spawns one process per command | 2026-08-25 | accepted |
| [0027](0027-keybinding-when-clause-system-in-phase-2.md) | Build the keybinding when-clause system up front | 2026-08-25 | accepted |
| [0028](0028-persist-state-by-graph-reachability.md) | Persist settings and workspace state by reachability | 2026-08-28 | accepted |
| [0029](0029-cache-the-jid-not-the-node.md) | Cache the jid, resolve via `jobj()` before any mutation | 2026-08-28 | accepted |
| [0030](0030-filesystem-authoritative-file-tree-reads.md) | Make the file-tree read path filesystem-authoritative | 2026-08-28 | accepted |
| [0031](0031-never-del-a-graph-significant-cache-key.md) | Never `del` a cache key with graph-edge significance | 2026-08-28 | accepted |
| [0032](0032-match-vscode-default-identity-natively.md) | Match VS Code's default identity natively (Dark+/Light+) | 2026-08-28 | superseded by [0033](0033-target-dark-2026-and-real-codicons.md) |
| [0033](0033-target-dark-2026-and-real-codicons.md) | Target "Dark 2026"/"Light 2026" and real `@vscode/codicons` | 2026-08-28 | accepted |
| [0034](0034-rely-on-monaco-bundled-tokenizers.md) | Rely on Monaco's bundled tokenizers for common languages | 2026-08-28 | accepted |
| [0035](0035-register-a-monarch-tokenizer-for-jac.md) | Register a scoped Monarch tokenizer for `.jac` | 2026-08-28 | accepted |
| [0036](0036-diffeditor-model-retention-props.md) | `DiffEditor` needs its own model-retention props | 2026-08-28 | accepted |
| [0037](0037-pre-create-diff-models-for-language-detection.md) | Pre-create both diff sides' models | 2026-08-28 | accepted |
| [0038](0038-minimap-on-in-editor-off-in-diff.md) | Minimap on in the editor; diff panes have none by design | 2026-08-28 | accepted |
| [0039](0039-quick-open-uses-os-walk.md) | Quick Open lists files with `os.walk`, not the graph | 2026-08-28 | accepted |
| [0040](0040-activity-bar-is-a-hand-built-switcher.md) | The activity bar is a hand-built view switcher | 2026-08-28 | accepted |
| [0041](0041-reverify-triage-against-live-upstream.md) | Re-verify the triage docs against live upstream source | 2026-08-28 | accepted |
| [0042](0042-stage-diagnostic-node-before-any-producer.md) | Stage the `Diagnostic` node type before any producer | 2026-08-28 | accepted |
| [0043](0043-vsix-as-phase-4-compatibility-test-case.md) | Use the published `.vsix` as the compatibility test case | 2026-08-28 | superseded by [0046](0046-defer-vsix-compatibility-research.md) |
| [0044](0044-native-feature-parity-before-extension-compatibility.md) | Native feature parity before extension compatibility | 2026-08-31 | accepted |
| [0045](0045-native-lsp-client-against-jac-lsp.md) | Build a native LSP client against `jac lsp` | 2026-08-31 | accepted |
| [0046](0046-defer-vsix-compatibility-research.md) | Defer `.vsix` compatibility research; it blocks nothing | 2026-08-31 | accepted |
| [0047](0047-dap-client-is-native-infrastructure.md) | The DAP client is native infrastructure | 2026-08-31 | accepted |
| [0048](0048-named-ai-coding-tool-integrations-in-scope.md) | A small, named set of AI coding-tool integrations | 2026-08-31 | accepted |
| [0049](0049-file-based-command-channel-for-sse-generators.md) | File-based command channel for SSE generators | 2026-09-01 | accepted |
| [0050](0050-debugpy-as-the-dap-adapter.md) | Use `debugpy` directly as the DAP adapter | 2026-09-02 | accepted |
| [0051](0051-lsp-and-dap-reuse-the-terminal-gate.md) | LSP and DAP reuse the terminal's capability gate | 2026-09-02 | accepted |
| [0052](0052-contribution-registry-is-a-centralized-list.md) | The contribution registry is a centralized list | 2026-09-02 | accepted |
| [0053](0053-claude-code-launcher-is-plain-python.md) | `claude_code_launcher.py` stays plain Python | 2026-09-03 | accepted |
| [0054](0054-build-ai-ui-entry-points-not-more-integrations.md) | Build AI UI entry points, not more integrations | 2026-09-03 | accepted |
| [0055](0055-point-claude-code-at-the-jac-mcp-server.md) | Point the Claude Code provider at `jac mcp` | 2026-09-03 | accepted |
| [0056](0056-explicit-approval-for-every-agent-tool-call.md) | Gate every agent tool call behind an approval card | 2026-09-03 | accepted |
| [0057](0057-multi-file-edit-review-is-a-diff-preview.md) | Edit review v1 is a per-file diff preview | 2026-09-03 | accepted |
| [0058](0058-inline-chat-uses-a-content-widget.md) | Inline chat is a content widget, not a `ZoneWidget` | 2026-09-04 | accepted |
| [0059](0059-global-keybinding-registry-for-monaco-chords.md) | Register editor chords once globally, dispatch by focus | 2026-09-04 | accepted |
| [0060](0060-tool-lifecycle-is-three-events.md) | A tool call is three events joined by `tool_use_id` | 2026-09-04 | accepted |
| [0061](0061-pin-claude-model-to-haiku.md) | Pin the model to `"haiku"`, permanently | 2026-09-04 | accepted |
| [0062](0062-close-phase-5-and-defer-remaining-tools.md) | Close the AI phase; defer the remaining tools | 2026-09-04 | accepted |
| [0063](0063-do-not-split-chatprovider-yet.md) | Do not split `ChatProvider` until a second provider exists | 2026-09-04 | accepted |
| [0064](0064-resolve-cwd-in-the-caller-not-the-generator.md) | Resolve the workspace path in the caller | 2026-09-05 | accepted |
| [0065](0065-panel-identity-is-ai-chat.md) | The panel's identity is "AI Chat" | 2026-09-05 | accepted |
| [0066](0066-maximize-is-a-css-overlay-not-a-remount.md) | Maximize is a CSS overlay, not a remount | 2026-09-05 | accepted |
| [0067](0067-reuse-proven-libraries-for-solved-problems.md) | Reuse proven libraries for solved problems | 2026-09-15 | accepted |
| [0068](0068-paint-theme-colors-at-the-root-div.md) | Paint background/color from CSS vars at the one root div | 2026-09-04 | accepted |
| [0069](0069-ai-chat-fully-isolates-from-host-claude-md.md) | The AI chat subprocess fully isolates from the host's global CLAUDE.md | 2026-09-15 | accepted |
| [0070](0070-ai-launcher-sets-explicit-system-prompt-preset.md) | The AI launcher sets an explicit system prompt preset | 2026-09-15 | accepted |
| [0071](0071-workspace-watched-via-os-level-events.md) | Workspace changes are watched via OS-level events, polled from the client | 2026-09-15 | accepted |
| [0072](0072-auto-reload-clean-tabs-on-external-change.md) | Auto-reload open tabs on a clean external change, never a dirty one | 2026-09-15 | accepted |
| [0073](0073-sidebar-width-override-via-style-not-classname.md) | Route the sidebar width override through `style`, not `className` | 2026-09-15 | accepted |
| [0074](0074-null-check-monaco-getposition-everywhere.md) | Null-check `editor.getPosition()` everywhere, matching upstream | 2026-09-15 | accepted |
| [0075](0075-auto-mode-sends-bypasspermissions.md) | Auto mode sends `bypassPermissions`; real `auto` confirmed inert in this CLI build | 2026-09-15 | accepted |
| [0076](0076-resolve-chat-attachments-server-side-before-sending.md) | Resolve chat file attachments server-side before sending | 2026-09-15 | accepted |
| [0077](0077-inline-chat-uses-fixed-permission-mode.md) | Inline chat uses fixed model/permission-mode/effort, not a second picker set | 2026-09-15 | accepted |
