# Technology choices

Where jac-studio reuses something proven, where it builds its own, and why. This replaces the
"use library X" advisory list with one grounded in what the project actually runs.

**The principle**: don't rebuild solved problems. Engineering effort goes to the architecture,
Jac-specific workflows, and the AI layer — not to re-deriving a text editor, a terminal emulator or
a git implementation. Where a library is adopted, `docs/libraries/<name>.md` records what it gives
us.

This is a change from the project's original stance ("everything in Jac unless genuinely blocked").
Building Monaco from scratch was attempted, worked, and was still the wrong trade — see
`docs/decisions/`.

## Adopted

| Area | Choice | Notes |
|---|---|---|
| Editor engine | `monaco-editor` via `@monaco-editor/react` | Text model, cursor/IME, undo, tokenizers, diff. [notes](libraries/monaco.md) |
| Terminal rendering | `@xterm/xterm` + `addon-fit` | Rendering only — there is no PTY. [notes](libraries/xterm.md) |
| UI primitives | shadcn-in-Jac over Radix | Sidebar, Resizable, Tabs, Command, ContextMenu, Tooltip, ScrollArea |
| Icons | `@vscode/codicons` | The actual font VS Code ships |
| Language intelligence | `jac lsp` over stdio JSON-RPC | A real, first-party jaclang LSP server — no extension host needed |
| Debugging | Debug Adapter Protocol client | Same subprocess/JSON-RPC shape as the LSP client |
| Source control | the real `git` CLI as a subprocess | No git reimplementation, no library shim |
| AI assistance | `claude-agent-sdk` as a subprocess | Never imported into `.jac` — it explodes the compiler |
| Markdown | `react-markdown` | Chat and hover rendering |
| Styling | Tailwind v4 + `jac retheme` OKLCH tokens | Matching VS Code's "Dark 2026"/"Light 2026" default |

## Candidates, not yet adopted

Real options for when the current approach hits a wall. None are blocking.

| Area | Candidate | Adopt when |
|---|---|---|
| Workspace search | `ripgrep` as a subprocess | Current search is in-process; switch when repo-scale search gets slow |
| File tree at scale | `react-arborist` | Current tree is hand-built and must stay lazy-loading; switch if virtualization becomes the bottleneck |
| Panel docking | `flexlayout-react` | If drag-to-dock layouts are wanted beyond the current Resizable panes |
| Real shell sessions | a PTY backend | When interactive programs and job control are needed in the terminal |
| Semantic search | a vector store (e.g. Qdrant) | Only if AI context-building outgrows lexical search |
| Extension marketplace | Open VSX | Only once an extension host exists to consume it |

## Considered and rejected

| Option | Why not |
|---|---|
| **Eclipse Theia as the foundation** | It's a complete IDE framework, so adopting it means jac-studio is no longer a Jac application — it would discard the architecture, the graph-backed services, and the reason the project exists. Reuse libraries, not frameworks that own the whole shell. |
| **Tauri / Electron for desktop** | Jac's own native path (`jac nacompile` + OS webview) bundles the same client we already ship. Adding a second desktop runtime buys nothing. |
| **isomorphic-git** | We shell out to the real `git` binary, which is faster, complete, and already installed. A JS git implementation would be a downgrade. |
| **Porting upstream's chat subsystem** | 442k lines, and the useful surface (code actions, inline chat, completions) is generic Monaco API we already reach directly. |

## Desktop, deliberately last

The target is a local-run web app with full capability first. Desktop packaging is then bundling
that same client — not a parallel codebase. Nothing in the roadmap is gated on it.
