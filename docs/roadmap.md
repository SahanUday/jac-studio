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

**Update, mid-Phase-2 (2026-08-25)**: the decision below was reversed. Phase 1's native prototype
did meet this exit criteria and the "continue native" call was made in good faith — but the
project has since switched to embedding the real `monaco-editor` npm package as the actual editor
engine for v1, a reuse-over-reinvention call, not a verdict that native failed. The ported
piece-tree/interval-tree engine and its client component are archived, not deleted, at
`internal/native-editor-archive/` for a possible future revival. See `architecture.md`'s Editor
Core section and tracker entry `2026-08-25-editor-core-decision-reversed-to-monaco`.

## Phase 2 — Workbench shell MVP

Goal: the app *looks* like an editor, using the shadcn-in-Jac primitives already available.

- File tree sidebar (backed by the workspace-as-graph model from `architecture.md`, validated at
  scale by `internal/workspace-graph-spike/` before this phase started) using `Sidebar` +
  `ScrollArea` (+ a hand-built tree component, since shadcn doesn't ship one). **Must load lazily,
  expand-on-demand** — the spike measured ~3 seconds combined to eagerly scan-and-traverse a
  real-sized project (2,974 nodes), too slow to feel instant on open; populate a folder's children
  only when the UI actually expands it.
- Tabs (`Tabs`) for open files, editor-group splitting (`Resizable`/`ResizablePanel`).
- Command palette (`Command`) wired to a minimal command registry (the first real consumer of the
  contribution-registry pattern from `architecture.md`).
- Basic status bar, no contributions yet beyond cursor position.
- **Integrated terminal** (per `architecture.md`'s Process Execution section) — raw OS process
  spawn + streamed output, gated behind the `shell` desktop capability. This is core, not an
  extension, so it belongs here, not in a later extension phase — you should be able to run
  something from a terminal in the earliest usable build, same as upstream VS Code.
- **Keybinding context ("when clause") system** (per
  [`vscode-feature-gap-analysis.md`](vscode-feature-gap-analysis.md)) — a context-evaluation layer
  on top of the same command registry the palette already needs, so keybindings can be scoped
  (e.g. "only when the editor has focus") instead of only ever global. Cheap now, expensive to
  retrofit once multiple features want the same key.

Exit criteria: can open a folder, browse files in a tree, open multiple files in tabs, split the
editor, run a handful of commands via the palette — a genuinely usable single-user local editor.

**Complete (2026-08-25).** All bullets shipped (PRs #17–#25) and the exit criteria above are met.
The editor engine was reversed to embedding real `monaco-editor` mid-phase (see the Phase 1 update
above and `architecture.md`'s Editor Core section) — a reuse-over-reinvention call, not a scope
change to this phase's own bullets. A first-ever real-browser verification pass (PRs #26/#27, using
`jac browse`) then found and fixed seven real bugs that no amount of `jac check`/`jac test`/
compiled-bundle inspection had caught, including a significant, still-open jaseci runtime gap
(`WriteConflict` never firing — see tracker entry
`2026-08-25-write-conflict-never-raised-session-commit-blind-retries`) that changes how any future
Phase 3 persistence code must be written. See
[`docs/phases/phase-2-workbench-shell.md`](phases/phase-2-workbench-shell.md) for the full record,
including deviations from plan (browser verification came too late, ARIA semantics deferred,
tracker entries logged late) carried forward rather than silently dropped.

## Phase 3 — Settings, persistence, and workspace state

Goal: the app remembers things, using Jac's persistence-by-reachability instead of hand-rolled
serialization.

- Settings and keybindings as graph-attached `obj`s (per `architecture.md`'s data model).
- Workspace state (open tabs, cursor positions, panel layout) persisted the same way — restoring
  a session on reopen "for free" via the graph, no explicit save/load code.
- **Basic syntax highlighting — confirmed live (2026-08-28), not just assumed free.** Verified
  (`jac browse`, `monaco.editor.colorize`/`tokenize`) that Python, JavaScript, CSS, JSON, and
  Markdown all get real, multi-class tokenization for free from `monaco-editor`'s bundled
  languages — the earlier "reach a TextMate tokenizer through Python/npm interop" question this
  bullet used to pose no longer applies for those. But `.jac` itself (and `.toml`) are not among
  Monaco's bundled languages, so this project's own dominant file type rendered as flat plaintext
  until now — `src/editor/client/jac_language.jac` registers a real, scoped Monarch tokenizer for
  Jac (keywords, comments, strings, `->`/`::`) so opened `.jac` files actually highlight. See
  `architecture.md`'s new "Syntax highlighting and the minimap" section for the full finding.
- **A diff-editor rendering mode** — via `@monaco-editor/react`'s `DiffEditor`
  (`src/editor/client/monaco_diff_editor.jac`), confirmed live to compose with this project's
  document-service model, with two corrections found while confirming the syntax-highlighting
  bullet above (2026-08-28): per-side language auto-detection from `originalModelPath`/
  `modifiedModelPath` only works when a diffed file already has a model from an open regular tab —
  a cold diff needs the fix `monaco_diff_editor.jac`'s `handle_before_mount` now applies (pre-create
  each side's model itself) — and the diff view has no per-pane minimap at all, hardcoded off by
  `monaco-editor` itself regardless of options, matching real VS Code's own diff view. The diff
  editor's own, differently-named model-retention props
  (`keepCurrentOriginalModel`/`keepCurrentModifiedModel`, not `keepCurrentModel`) are set correctly
  — see `architecture.md`'s Editor Core section for the full finding. Triggered via the file tree's
  Alt+Click "select for compare" gesture; a real file-tree context-menu entry for the same action
  is the separate context-menu bullet below.
- **A `Diagnostic` node type** attached to `File` in the workspace graph, with no producer yet —
  just the data model, so Phase 4's task/problem-matcher work and later language-intelligence work
  have somewhere to write to from day one.
- **Match VS Code's default visual identity — done (2026-08-28)**, see `architecture.md`'s Visual
  identity section for the full record. Rethemed the Phase 2 workbench chrome (sidebar, tabs,
  editor groups, command palette, status bar, terminal) from shadcn's stock look to VS Code's
  *actual* current default palette — checking the live `microsoft/vscode` source directly found
  this is "Dark 2026"/"Light 2026", not the "Dark+"/"Light+" pair this bullet originally assumed,
  a real correction, not a naming nitpick (the 2026 default drops the classic blue status bar
  entirely). Driven as native `jac retheme` OKLCH tokens (`--baseColor zinc --theme sky --radius
  small` scaffold) plus hand-edited exact values for the tokens `jac retheme`'s presets can't reach
  precisely, per its own documented one-off-custom-color escape hatch. Icon set swapped to the real
  `@vscode/codicons` package (not just "Codicons-style") in place of the removed `@hugeicons`
  dependency. Native token authoring, not a VS-Code-theme-format compatibility shim — that remains
  the separate, still-open installable-theme-extension question in `architecture.md`'s open
  questions.
- **Close the gap between what Phase 2 documented and what it actually shipped, plus what a
  2026-08-28 pass against the live `microsoft/vscode` source found missing entirely** (see
  `vscode-complete-triage.md` v3 and `docs/phases/phase-2-workbench-shell.md`'s "what's left"):
  - **Quick Open (Ctrl+P fuzzy file switcher) — done (2026-08-28)**
    (`src/workbench/quick_open/quick_open.jac`). Explicitly scoped into Phase 2 as a second
    `quickaccess` provider alongside the command palette, but never built there — delivered now as
    the documented-but-undelivered item it always was, not new scope. Reuses the same shadcn
    `Command` primitives and cmdk's built-in fuzzy filter the command palette already relies on;
    its file list comes from `workspace_service.jac`'s new `list_all_files` (a plain `os.walk`,
    never touching the `Workspace`/`Folder`/`File` graph, so it doesn't pay the eager-graph-scan
    cost `architecture.md`'s workspace section already ruled out). Registered in
    `command_registry.jac`'s `BUILTIN_COMMANDS` (`workbench.action.quickOpen`, `ctrl+p`) and
    dispatched through `workbench.jac`'s existing generic keybinding mechanism rather than a second
    bespoke keydown listener — a deliberate departure from `command_palette.jac`'s own
    self-contained `Ctrl+Shift+P` handling, which predates that mechanism.
  - **Minimap** — decided on (2026-08-28), matching VS Code's default: `monaco_editor.jac` now
    sets `"minimap": {"enabled": True}`. The diff editor deliberately does not get the same flip —
    see the diff-editor bullet above.
  - **Activity bar** — the icon rail switching sidebar views (Explorer today; Search/SCM in
    Phase 4). Not a shadcn primitive (`Sidebar` is a container, not a switcher) — hand-build it now
    so Phase 4's new views have somewhere to mount instead of retrofitting under time pressure.
  - **Title bar** — the custom title bar + Command Center search box; core to "looking like
    VS Code" and was undocumented before this pass.
  - **File-tree context menu** (new file/folder, rename, delete) via the `ContextMenu` primitive
    already earmarked for this in `architecture.md`'s mapping table but unused so far.
  - **Tab affordances**: an unsaved-changes indicator (dot vs. close button) at minimum; file-type
    icons in the tree and tabs.

Exit criteria: closing and reopening the app restores the previous session exactly; settings
persist across restarts; opened files show syntax highlighting for at least a few common languages;
two versions of a file can be diffed; the workbench chrome matches VS Code's default look and feel,
including the activity bar, title bar, minimap, and Quick Open.

## Phase 4 — Extension system, Phase A (trusted, in-process)

Goal: prove the contribution-registry design end to end without solving sandboxing first (see
`architecture.md`'s phased extension trust model).

- "Extensions" are Jac modules loaded at build time, contributing commands/views/menus to the
  same registry the built-in workbench features use.
- Port 3 genuinely useful built-in features this way, chosen deliberately (not arbitrarily) to
  cover three different contribution shapes at once:
  1. **Search-in-files** — a workspace-wide feature reading from the file graph.
  2. **Source control (SCM) shell + a first git implementation** — a provider-agnostic SCM view
     that any VCS could plug into, with git as the first real provider, talking to the `git` CLI
     the same way the terminal work talks to any other process (per
     [`vscode-feature-gap-analysis.md`](vscode-feature-gap-analysis.md); not "a status indicator,"
     a real first-class workbench part with gutter/tree decorations).
  3. **A task runner with problem matchers** — writes into the `Diagnostic` node type staged in
     Phase 3, feeding a Problems panel. Proves the contribution model handles a feature with its
     own persistent config format (a task-definitions equivalent to `tasks.json`), not just UI.
- **Language-intelligence groundwork**: research whether a Python (or npm) LSP *client* library is
  usable via interop — the same open question as the DAP client in Phase 5, worth answering once
  for both. Build the editor-side consumption UI (completion popup, hover card) as a Phase
  4-or-later increment once that research lands; don't block this phase's exit on it.
- **Investigate real VS-Code-extension-API compatibility, using the actual published Jac extension
  as the test case** (decided 2026-08-28, prompted by Phase 3's syntax-highlighting work) — the
  real `jaseci-labs.jaclang-extension` (on the VS Code Marketplace, source at
  `jaseci/jac/support/vscode_ext/jac`) ships a genuinely complete `jac.tmLanguage.json` TextMate
  grammar (4,937 lines, 224 repository entries) plus a real language server, both far more complete
  than the hand-rolled Monarch tokenizer `src/editor/client/jac_language.jac` shipped as a Phase 3
  stopgap. Answer, in order: (1) can jac-studio load this `.vsix` largely unmodified (full
  `vscode` module shim, activation events, contribution loading)? If yes, this single effort also
  resolves `architecture.md`'s still-open "how much vscode-API compatibility to target" question
  and replaces the Phase 3 stopgap tokenizer with the authoritative, jaseci-team-maintained grammar
  in one move. (2) If full compatibility isn't feasible, investigate the narrower fallback:
  reusing just the bundled TextMate grammar via a `vscode-textmate` + `vscode-oniguruma` bridge
  into Monaco's token provider (the same technique vscode.dev/StackBlitz use), decoupled from the
  extension-API question entirely — unverified whether this project's Vite/jac-cl toolchain handles
  the WASM grammar-engine asset cleanly, so spike it rather than assume. Either outcome replaces
  `jac_language.jac`; until this lands, the Phase 3 tokenizer stays as the working baseline.
- **An Output panel with a log-channel abstraction** — moved earlier than its upstream scale would
  suggest, because it's needed to debug the extensions being written *in this phase*, not just as
  a later user-facing feature (per [`vscode-complete-triage.md`](vscode-complete-triage.md)'s
  `output`/`logs` row).
- **A merge-conflict UI** alongside the SCM work above — real conflicts only exist once real git
  integration does, so this is the natural phase for it, distinct from the two-way diff editor
  already shipped in Phase 3.
- **Toast notifications + a notification center** (`workbench/browser/parts/notifications`, found
  2026-08-28 — see `vscode-complete-triage.md`'s "workbench/browser/parts" section, previously
  undocumented as a UI surface). Genuine prerequisite here, not polish deferred further: both the
  task runner and SCM operations above need a way to report background success/failure to the
  user, and there's currently no UI surface for that at all.

Exit criteria: a fourth built-in feature can be added purely by writing a new contributing module,
with zero changes to existing workbench code — the actual test of whether the contribution model
is real; SCM shows real git status/diffs and can resolve a merge conflict; a build task's errors
show up in a Problems panel; extension output is visible in a log channel; a background task's
completion surfaces as a toast notification.

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
- **Extensions view** (browse/install/enable/disable/uninstall) — now that extensions load
  dynamically, they need a management UI; not previously called out as distinct from the trust
  model itself (per [`vscode-complete-triage.md`](vscode-complete-triage.md)'s `extensions` row).
- **An auth-provider broker + secret storage** — an extension needing to authenticate against an
  external service (git hosting, a language server needing a license token, anything) needs
  somewhere to request/share OAuth tokens and store credentials safely rather than each extension
  reinventing it in plaintext settings. Small (upstream's `encryption` contrib is 48 lines, a thin
  OS-keychain wrapper) but a real dependency once any auth-requiring extension is written.
- **Auxiliary bar** (`workbench/browser/parts/auxiliarybar`, found 2026-08-28 — see
  `vscode-complete-triage.md`) — the secondary/right-side dockable panel. Upstream uses it for
  Chat (excluded here, see `chat`'s Tier 2.5 disposition) but it's generic dockable-panel infra
  independent of that — worth building once Search/SCM/Extensions views are competing for the
  same sidebar real estate, which is true by this phase.
- **"Continue Working On" / edit-session sync** (`editSessions`, found 2026-08-28) — syncs
  uncommitted changes across devices via the same account the auth broker above manages. Natural
  pairing with that broker and with `userDataSync`/`userDataProfile` (already Tracked); include if
  time allows, not exit-blocking.

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
- **The in-app update UI** (`update` contrib, found 2026-08-28 — see `vscode-complete-triage.md`):
  release-notes viewer, "Restart to Update" notification, title-bar update indicator. Distinct
  from the auto-update *feed* bullet above — that's the packaging/build side; this is the surface
  that actually tells the user an update is available, and doesn't fall out of the feed for free.

Exit criteria: a signed, installable binary for at least one OS, built via a repeatable CI
pipeline (not a manual `jac nacompile` on a developer's machine).

## Explicitly out of scope for now (revisit later, not decided against)

- Remote/server development (VS Code's remote-SSH-style architecture) — no research done yet.
- A public extension marketplace/registry — depends entirely on Phase 5/6 outcomes.
- Collaborative real-time editing — the multi-user access-control primitives exist in Jac
  (`root.shared`, `grant`/`revoke`) and would make this more tractable than in a from-scratch
  stack, but it's not on the critical path to a usable single-user MVP.
