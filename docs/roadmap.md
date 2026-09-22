# Roadmap

**Goal**: VS Code's capabilities, UX and feel, as a Jac web app — AI-first, so not a literal clone.
A local-run web app with full capability comes first; desktop is the same client, bundled, last.

Milestones are small and ordered by dependency, not dates. Each ends with something demoable.
Upcoming scope is proposed and gets confirmed when the milestone starts — decisions made along the
way land in [`decisions/`](decisions/), not in this file.

## Shipped

| # | Milestone | Delivered | Record |
|---|---|---|---|
| M0 | Foundations | Service registry on the graph validated; translator proven on two modules; challenge tracker live | [m0](milestones/m0-foundations.md) |
| M1 | Editor core | Native piece-tree editor met its exit criteria, then archived when Monaco took over ([ADR 0020](decisions/0020-editor-engine-is-real-monaco.md)) | [m1](milestones/m1-editor-core.md) |
| M2 | Workbench shell | Lazy file tree, tabs, split groups, command palette, terminal, keybinding when-clauses | [m2](milestones/m2-workbench-shell.md) |
| M3 | Persistence and identity | Session and settings restore, syntax highlighting, diff editor, Quick Open, activity bar, title bar, VS Code default look | [m3](milestones/m3-persistence-and-identity.md) |
| M4 | Native feature parity | Search, SCM with merge conflicts, tasks and Problems, Output, notifications, LSP client on `jac lsp`, DAP client | [m4](milestones/m4-native-feature-parity.md) |
| M5 | AI integration | Claude Code chat with tool approval, edit diff review, MCP, AI code actions, inline chat, step cards | [m5](milestones/m5-ai-integrations.md) |
| M7 | Terminal: real PTY sessions | Persistent, reconnectable shell per session (ADR 0078), replacing the one-shot-subprocess model; copy/paste, links, search, correct Unicode/TUI rendering via previously-unwired xterm.js addons | [m7](milestones/m7-terminal-real-pty-sessions.md) |

**Carried over, not done**: M4's "a fourth feature needs zero workbench changes" criterion is unmet
— the contribution registry is a centralized list ([ADR 0052](decisions/0052-contribution-registry-is-a-centralized-list.md)).
M5 named Copilot and OpenCode; only Claude Code was built. M7 shipped ahead of M6 — no dependency
between them, and milestones are ordered by dependency, not sequence number.

## Next

### M6 — Quality floor

Make "it works" checkable by something other than a person.

- CI on `main`: `jac check` and `jac test src` on every PR.
- First tests for workbench state — the entire UI layer has none today.
- Resolve the M4 contribution-model criterion: make the registry genuinely open, or accept the
  centralized list and retire the criterion in an ADR.

**Exit**: a PR that breaks a check or a test fails CI; at least the shell's session-restore logic
is under test.

### M8 — Editor correctness

Close the gaps a daily user hits. See [`known-limitations.md`](known-limitations.md).

- Move the cursor when navigating into an already-open tab (search, problems, definition, outline).
- Wire what `jac lsp` already serves but the editor doesn't consume: signature help, formatting,
  semantic tokens.
- Outline reads the live buffer, not the last save.

**Exit**: every navigation lands on the right line whether or not the tab was open; formatting and
signature help work on `.jac` files.

### M9 — AI-first editing

The features that make this AI-first rather than an editor with a chat panel.

- Ghost-text inline completions via Monaco's `registerInlineCompletionsProvider`.
- Cancel a turn mid-flight.
- Persisted per-tool trust ("always allow"), so approval cards don't become noise.

**Exit**: inline suggestions appear while typing and accept on Tab; a running turn can be stopped.

### M10 — AI providers

- A native provider on `by llm(tools=[...])` using the services already built — no external CLI.
- A second external provider (Copilot or OpenCode), after its own auth/licensing scoping.
- Revisit splitting `ChatProvider` into agent identity and model backend, once there is a second
  data point ([ADR 0063](decisions/0063-do-not-split-chatprovider-yet.md)).

**Exit**: a user can switch between at least two providers in the same chat UI.

### M11 — Remaining VS Code parity

Work down [`vscode-complete-triage.md`](vscode-complete-triage.md) for what's still uncovered.
Likely candidates: settings and keybindings editors, menu bar, auxiliary bar, multi-root workspace
UI.

**Exit**: no triaged "Scoped" feature area is still missing.

### M12 — Extensions: dynamic loading

Extension-system Phase B ([ADR 0008](decisions/0008-extension-system-phased-trust-model.md)):
still trusted, but loaded at runtime.

- Manifest format, and the decision on how much `vscode` API compatibility to target.
- Runtime loading, an Extensions view, an auth broker with secret storage.

**Exit**: an extension installs and uninstalls without rebuilding the app.

### M13 — Extensions: sandboxing

Phase C. A research track, not integration work — likely built on Jac's WASM target. Don't start
before M12 has validated the extension API against real use.

### M14 — Desktop

`jac nacompile` plus the OS webview, bundling the same client. Then per-OS installers, signing, an
update feed and the in-app update UI.

**Exit**: a signed installable binary for one OS, built by CI.

## Not planned yet

Revisit later; not decided against.

- Remote development (SSH-style).
- A marketplace — consuming Open VSX only makes sense after M12.
- Collaborative editing — Jac's `grant`/`revoke`/`root.shared` make it more tractable than usual,
  but it's off the path to a complete single-user editor.
- `.claude-plugin/` bundle discovery and install.
