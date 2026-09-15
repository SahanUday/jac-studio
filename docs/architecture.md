# Architecture

How jac-studio is put together **now**. Why it ended up this way is in [`decisions/`](decisions/);
what's next is in [`roadmap.md`](roadmap.md).

## Principles

1. **Reuse proven libraries for solved problems.** Monaco, xterm.js, Radix, the real `git`. Jac
   effort goes to architecture, Jac-specific workflows and the AI layer.
   [ADR 0067](decisions/0067-reuse-proven-libraries-for-solved-problems.md)
2. **Where VS Code's shape comes from a TypeScript/Electron limitation, redesign it in Jac.** The
   graph instead of a DI container; `root spawn` instead of an RPC protocol; a capability gate
   instead of always-on OS access. [ADR 0001](decisions/0001-rewrite-dont-mirror.md)
3. **Log every real Jac limitation** to the challenge tracker instead of silently working around it.
4. **Web app first.** Desktop is the same client bundled later. [ADR 0009](decisions/0009-desktop-packaging-deferred.md)

## Shape

| VS Code layer | jac-studio |
|---|---|
| `base` | Ordinary Jac modules |
| `platform` (DI + services) | Services resolved from the graph under `root` |
| `editor` (Monaco) | The real `monaco-editor` package behind a thin Jac wrapper |
| `workbench` | jac-cl components over shadcn-in-Jac primitives |
| Extension host | None yet — see M11/M12 |
| `code` (Electron main) | `jac nacompile` + OS webview, deferred |

```
browser (jac-cl client bundle)
  └─ workbench shell ─ Monaco ─ xterm.js ─ AI chat
        │ def:pub RPC / SSE streams
server (jac, one process per user root)
  └─ services on the graph ─ workspace, settings, session, commands, diagnostics
        │ subprocesses
  └─ jac lsp · debugpy (DAP) · git · task shells · claude_code_launcher.py
```

## Services and data

- **A service is an `obj` by default**, promoted to a `node` only if it must survive a restart, be
  reached by traversal, or take part in permissions. [0015](decisions/0015-default-services-to-obj-not-node.md)
- **Cache the jid, not the node**, keyed by `jid(root)`, and resolve with `jobj()` before any
  mutation. A field write through a cached node object is silently never committed.
  [0029](decisions/0029-cache-the-jid-not-the-node.md)
- **Every cached service exports `_reset_<x>_cache_for_tests()`.** `jid(root)` is shared across
  tests in a worker. [0014](decisions/0014-service-cache-test-reset-hook.md)
- **The workspace is the graph**: `Workspace → Folder → File`, loaded lazily on expand — eager
  traversal measured ~3s at 2,974 nodes. [0004](decisions/0004-workspace-is-the-graph.md),
  [0019](decisions/0019-file-tree-loads-lazily.md)
- **Reads are authoritative, writes are not trusted.** Edge deletion doesn't reliably commit across
  HTTP requests and check-then-create can't be made atomic, so the file tree checks the filesystem
  and reads de-duplicate. [0030](decisions/0030-filesystem-authoritative-file-tree-reads.md),
  [0023](decisions/0023-read-side-dedup-not-write-side-locking.md)
- **Settings and session persist by reachability** — no serialization code.
  [0028](decisions/0028-persist-state-by-graph-reachability.md) Ephemeral UI state (dirty flags,
  pending prompts) is deliberately not persisted.

## Editor

`src/editor/client/monaco_editor.jac` mounts Monaco; content loads once on open and saves on
`Ctrl+S` — no per-keystroke server traffic. One editor instance per open tab, hidden with CSS so undo
history survives. Language intelligence is five Monaco providers calling the LSP client.
Integration traps and unused capabilities: [`libraries/monaco.md`](libraries/monaco.md).

`.jac` highlighting is a scoped Monarch tokenizer, a stopgap next to the extension's full TextMate
grammar. [0035](decisions/0035-register-a-monarch-tokenizer-for-jac.md)

## Workbench

- **Chrome** composes shadcn-in-Jac primitives; the activity bar, title bar and tab row are
  hand-built where no primitive fits. Look matches VS Code's "Dark 2026"/"Light 2026" with real
  `@vscode/codicons`. [0033](decisions/0033-target-dark-2026-and-real-codicons.md)
- **`workbench.jac` owns shared state** (open groups, cursors, active view) and leaves report up.
- **Commands** live in a centralized registry with a when-clause layer for scoped keybindings.
  Editor chords register once globally and dispatch by focus.
  [0052](decisions/0052-contribution-registry-is-a-centralized-list.md),
  [0059](decisions/0059-global-keybinding-registry-for-monaco-chords.md)

## Processes and gates

| Subsystem | Runs as | Gated by `[terminal] enabled`? |
|---|---|---|
| Terminal | one server process per command, output over SSE | Yes |
| Tasks | shell with `shell=True` | Yes |
| LSP | `jac lsp` over stdio JSON-RPC | Yes |
| Debugging | `debugpy` as the DAP adapter | Yes |
| AI chat | `claude_code_launcher.py` subprocess | Yes |
| SCM | `git` with fixed argument lists | **No** — no arbitrary strings reach a shell |

- **SSE-streamed functions need a top-level import in `main.jac`**, or their route never registers.
- **Nothing runs inside an SSE generator that needs `root`-scoped graph state** — resolve it in the
  caller and pass it in. [0064](decisions/0064-resolve-cwd-in-the-caller-not-the-generator.md)
- **Cross-process decisions use a file-based command channel** (DAP commands, tool approvals).
  [0049](decisions/0049-file-based-command-channel-for-sse-generators.md)
- **SDKs with large dependency closures stay in plain Python subprocesses** — importing
  `claude_agent_sdk` into `.jac` breaks the compiler. [0053](decisions/0053-claude-code-launcher-is-plain-python.md)

## AI layer

One provider today (Claude Code), several UI entry points on the same `start_chat_turn` stream:
the sidebar, `Ctrl+I` inline chat, and AI code actions. Every tool call needs approval, with a diff
preview for edits. Tool calls are three events joined by `tool_use_id`. The model is pinned to
`haiku`. [0054](decisions/0054-build-ai-ui-entry-points-not-more-integrations.md),
[0056](decisions/0056-explicit-approval-for-every-agent-tool-call.md),
[0061](decisions/0061-pin-claude-model-to-haiku.md)

## What a passing check does not prove

- **`jac check`/`jac test` never build the client bundle.** jac2js miscompiles, broken RPC route
  names and dead event wiring all pass. UI changes need `jac browse`. [0024](decisions/0024-jac-browse-is-required-verification.md)
- **Single-`root` tests don't prove multi-user correctness.** Anything `root`-scoped needs a
  two-user `JacTestClient` test.

## Open questions

- How much `vscode` API compatibility the extension system targets (M11).
- Whether installable third-party theme extensions are supported, or themes stay native.
- Whether `ChatProvider` splits into agent identity and model backend (M9).
- Sandboxing untrusted extension code — no Jac precedent (M12).
