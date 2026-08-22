# Jac Studio — roadmap

Status: proposal, v1 — 2026-08-22. Phases are ordered by dependency, not by calendar time; no
dates are attached yet on purpose (this is a research-heavy project on a moving-target language —
see the maturity gaps in [`research/jac-capabilities.md`](research/jac-capabilities.md)). Each
phase ends with a working, demoable artifact, per the MVP-first principle in
[`architecture.md`](architecture.md).

## Phase 0 — Foundations

Goal: de-risk the two biggest architectural bets before building anything on top of them.

- Scaffold the jac-studio project (`jac scaffold`), `jac.toml`, basic CI (`jac test` on push).
- Stand up the [challenge tracker](challenge-tracking.md) — data format, static site, deploy
  pipeline. Needed from day one since every later phase feeds it.
- **Spike: root-graph-as-service-registry.** Build a real three-service slice (config service +
  command registry + a toy file-tree service, interacting) using the pattern proposed in
  `architecture.md`. Either it holds up, or we fall back to `glob` singletons — decide with real
  code, not in the abstract.
- **Spike: translator on the algorithmic core.** Run the [translator workflow](translator-strategy.md)
  against `prefixSumComputer.ts` and `intervalTree.ts` (smallest, purest targets) end to end,
  including ported tests. This is the first real signal on whether the translator approach is
  worth continuing to the piece tree.

Exit criteria: service-registry pattern decided (validated or replaced), translator workflow
proven on two small modules with passing ported tests, tracker live with real entries from this
phase's own friction.

## Phase 1 — Editor core MVP (headless, then minimal render)

Goal: a single text buffer that can be created, edited, and displayed — no workbench chrome yet.

- Port the piece-tree text buffer via the translator, with parity against VS Code's own test
  suite for that module.
- Build a minimal Jac client component that renders the buffer's content and accepts keyboard
  input (insert/delete/cursor movement) — deliberately basic, no syntax highlighting, no
  multi-cursor, no undo/redo UI beyond what the ported edit-stack module gives us.
- **Decision point**: is this fast enough / far enough along to keep going natively, or do we
  stand up the Monaco-embed bridge described in `architecture.md` to unblock later phases while
  the native editor matures in parallel? Make this call with the working prototype in hand, and
  record it as a tracker entry either way.

Exit criteria: can open a file's content into a buffer, type, delete, save — as a standalone demo,
no surrounding app.

## Phase 2 — Workbench shell MVP

Goal: the app *looks* like an editor, using the shadcn-in-Jac primitives already available.

- File tree sidebar (backed by the workspace-as-graph model from `architecture.md`) using
  `Sidebar` + `ScrollArea` (+ a hand-built tree component, since shadcn doesn't ship one).
- Tabs (`Tabs`) for open files, editor-group splitting (`Resizable`/`ResizablePanel`).
- Command palette (`Command`) wired to a minimal command registry (the first real consumer of the
  contribution-registry pattern from `architecture.md`).
- Basic status bar, no contributions yet beyond cursor position.
- **Integrated terminal** (per `architecture.md`'s Process Execution section) — raw OS process
  spawn + streamed output, gated behind the `shell` desktop capability. This is core, not an
  extension, so it belongs here, not in a later extension phase — you should be able to run
  something from a terminal in the earliest usable build, same as upstream VS Code.

Exit criteria: can open a folder, browse files in a tree, open multiple files in tabs, split the
editor, run a handful of commands via the palette — a genuinely usable single-user local editor.

## Phase 3 — Settings, persistence, and workspace state

Goal: the app remembers things, using Jac's persistence-by-reachability instead of hand-rolled
serialization.

- Settings and keybindings as graph-attached `obj`s (per `architecture.md`'s data model).
- Workspace state (open tabs, cursor positions, panel layout) persisted the same way — restoring
  a session on reopen "for free" via the graph, no explicit save/load code.
- Basic syntax highlighting via a TextMate-grammar-compatible tokenizer reached through Python/npm
  interop (evaluate before committing to a from-scratch tokenizer, per `architecture.md`).

Exit criteria: closing and reopening the app restores the previous session exactly; settings
persist across restarts; opened files show syntax highlighting for at least a few common languages.

## Phase 4 — Extension system, Phase A (trusted, in-process)

Goal: prove the contribution-registry design end to end without solving sandboxing first (see
`architecture.md`'s phased extension trust model).

- "Extensions" are Jac modules loaded at build time, contributing commands/views/menus to the
  same registry the built-in workbench features use.
- Port 2–3 genuinely useful built-in features this way (e.g., a simple search-in-files feature, a
  basic git-status indicator) to prove the pattern isn't just a toy.

Exit criteria: a third built-in feature can be added purely by writing a new contributing module,
with zero changes to existing workbench code — the actual test of whether the contribution model
is real.

## Phase 5 — Extension system, Phase B (dynamic, still trusted)

Goal: extensions become separate packages with a manifest, loaded at runtime.

- Design the manifest format (deliberately deferred in `architecture.md` — resolve the
  vscode-API-compatibility question here, before this phase, since it changes the manifest shape
  significantly).
- Dynamic loading at runtime, still fully trusted — no isolation yet.
- **Debug Adapter Protocol client** (per `architecture.md`'s Process Execution section) — a
  from-scratch scoped design effort, not something that falls out of the general contribution
  model. First step: check whether a Python DAP client library is usable via Python interop
  before building one from the wire protocol up.

Exit criteria: an extension can be installed/removed without a rebuild of the app itself, and a
language extension can register a debug adapter that gets real breakpoint/step/inspect support.

## Phase 6 — Extension sandboxing (Phase C) — treat as its own research track

Goal: untrusted third-party extension code, safely isolated.

This is explicitly R&D, not integration work (see `architecture.md`). Do not start this before
Phase 4/5 have validated the extension-API surface against real usage. Likely built on Jac's
native+WASM compilation path; expect this phase to produce the largest volume of tracker entries
in the whole project, since there's no existing Jac precedent to lean on at all.

## Phase 7 — Desktop packaging

Goal: a real, installable, cross-platform binary — deliberately last, per `architecture.md`
principle 4 (no cost to deferring it, since the desktop shell is a thin wrapper over the same
client bundle used elsewhere).

- `jac nacompile` + native webview shell for a single-OS dev build first.
- Per-OS installers, code signing (Windows Authenticode, macOS notarization), auto-update feed —
  expect to build this pipeline largely from scratch, per
  [`research/vscodium-packaging.md`](research/vscodium-packaging.md); Jac doesn't ship one yet
  (tracked upstream gap #6436).

Exit criteria: a signed, installable binary for at least one OS, built via a repeatable CI
pipeline (not a manual `jac nacompile` on a developer's machine).

## Explicitly out of scope for now (revisit later, not decided against)

- Remote/server development (VS Code's remote-SSH-style architecture) — no research done yet.
- A public extension marketplace/registry — depends entirely on Phase 5/6 outcomes.
- Collaborative real-time editing — the multi-user access-control primitives exist in Jac
  (`root.shared`, `grant`/`revoke`) and would make this more tractable than in a from-scratch
  stack, but it's not on the critical path to a usable single-user MVP.
