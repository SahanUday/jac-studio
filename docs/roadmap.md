# Jac Studio — roadmap

Status: proposal, v1 — 2026-08-22. Phases are ordered by dependency, not by calendar time; no
dates are attached yet on purpose (this is a research-heavy project on a moving-target language —
see the maturity gaps in [`research/jac-capabilities.md`](research/jac-capabilities.md)). Each
phase ends with a working, demoable artifact, per the MVP-first principle in
[`architecture.md`](architecture.md).

**Re-prioritized 2026-08-31, per explicit project-sponsor direction** (see `architecture.md`'s
Extension System section for the full reasoning): the milestone this roadmap is driving toward
next is **a complete, VS-Code-feature-equivalent editor — "jac-coder" — built entirely on
native/built-in Jac functionality, without depending on a general third-party extension ecosystem.**
That's the actual end goal, not a scaled-down substitute for it — full `.vsix`/marketplace
compatibility is still on this roadmap, just deliberately sequenced *after* that native milestone
(Phase 6 below), not interleaved with it. Concretely, this reorders Phases 4–8 below relative to
earlier drafts:

- Phase 4 now folds in **native language intelligence (a real Jac LSP client) and a Debug Adapter
  Protocol client** as flagship deliverables, promoted out of "future research" — both turn out to
  need nothing beyond the process-spawn mechanism Phase 2's terminal already established, and Jac's
  own `jac lsp` command already provides a real, working language server to build the LSP half
  against immediately (see `architecture.md`'s "Language intelligence" section).
- A new Phase 5 scopes **native integrations with a small, named set of external AI coding tools**
  (GitHub Copilot, OpenCode, Claude Code) as their own deliverable, distinct from both "port
  upstream's chat subsystem" (still excluded) and "wait for a general extension system" (no longer
  the assumption).
- What were Phases 5–7 (extension system Phase B, sandboxing, desktop packaging) shift to Phases
  6–8, explicitly framed as *later*, non-blocking to the native-feature-parity milestone above —
  not abandoned, just no longer gating "is jac-studio full-featured yet."

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
  - **Activity bar — done (2026-08-28)** (`src/workbench/activity_bar/activity_bar.jac`). The icon
    rail switching sidebar views (Explorer today; Search/SCM in Phase 4). No shadcn primitive
    fits (`Sidebar` is a container, not a switcher) — hand-built. `VIEWS` is a plain module-level
    list with one real entry today; the switching mechanism (`active_view_id` owned by
    `workbench.jac`, one `onSelectView` callback) is built end-to-end now so Phase 4's new views
    are a one-entry-plus-one-branch addition, not new plumbing under time pressure.
  - **Title bar — done (2026-08-28)** (`src/workbench/title_bar/title_bar.jac`). The custom title
    bar + Command Center search box; core to "looking like VS Code" and was undocumented before
    this pass. No window controls (a web app, not a native desktop host yet) and no menu bar
    (materially larger scope this bullet never named) — just the title bar chrome and a Command
    Center pill that opens the command palette. Building it surfaced a real gap:
    `command_palette.jac` had no way for anything outside itself to open it (its `open` state was
    private, set only by its own self-contained `Ctrl+Shift+P` listener). Fixed by moving that
    state to `workbench.jac` and registering `workbench.action.showCommands` in
    `command_registry.jac`, the same move `quick_open.jac` already made for the identical reason —
    the keyboard shortcut and the title bar's button now both dispatch through the one path.
  - **File-tree context menu — done (2026-08-28)** (new file/folder, rename, delete, plus a
    right-click "Select for Compare"/"Compare with Selected" pair mirroring the Alt+Click gesture)
    via the `ContextMenu` primitive (`jac install --shadcn context-menu`), previously earmarked in
    `architecture.md`'s mapping table but unused. `workspace_service.jac` gained
    `create_file`/`create_folder`/`rename_path`/`delete_path`. Found two real, previously-unknown
    jaseci persistence gaps building this — edge deletion not reliably committing across real HTTP
    requests, and a plain application-level dict `del` corrupting an unrelated node's edge
    reachability — see `architecture.md`'s service-registry section for the full record and both
    tracker entries.
  - **Tab affordances — done (2026-08-28)**: an unsaved-changes indicator (dot vs. close button)
    and file-type icons in the tree and tabs, the last Phase 3 bullet. `file_icons.jac` (new) is a
    single extension-bucketed `file_icon_class` helper shared by `file_tree.jac`'s rows and
    `editor_tabs.jac`'s tabs, so both surfaces pick the same glyph for the same file rather than
    drifting apart. Dirty tracking threads through all three layers the same "leaf reports, parent
    owns state" way cursor position already does: `monaco_editor.jac`'s new `onDirtyChange` (wired
    via `@monaco-editor/react`'s `onChange`, transitioning `False -> True` once per edit session,
    not per keystroke) reports up through `editor_tabs.jac` to `workbench.jac`'s new `dirty_paths`
    dict, which drives the dot-vs-close swap. Deliberately not part of the persisted session, since
    it describes in-memory Monaco content a reload can't recover anyway — see `workbench.jac`'s
    docstring. Found and fixed two real bugs building this, neither one a jaseci defect: (1) a
    `del` statement on a plain dict inside a client-lowered handler compiles clean under
    `jac check`/`jac test` but has no `jac2js` lowering at all, caught only by the real dev server
    build — logged as tracker entry `2026-08-28-client-dict-del-unsupported-by-jac2js`, worked
    around by overwriting the flag to `False` instead of deleting the key; (2) the first
    dot/close-button hide-on-hover implementation used Tailwind's `hidden`/`group-hover:` display
    toggling, which silently never applied because `@vscode/codicons`' own base rule
    (`.codicon[class*='codicon-']{display:inline-block}`) has higher CSS specificity than a plain
    Tailwind utility class — fixed by switching to opacity/`pointer-events` toggling instead, which
    the codicon rule never touches. This second one is a collision between two third-party
    stylesheets this project combines, not a Jac/jaseci gap, so it wasn't tracker-logged.

Exit criteria: closing and reopening the app restores the previous session exactly; settings
persist across restarts; opened files show syntax highlighting for at least a few common languages;
two versions of a file can be diffed; the workbench chrome matches VS Code's default look and feel,
including the activity bar, title bar, minimap, and Quick Open.

## Phase 4 — Native built-in features + language intelligence (extension system Phase A)

Goal: reach real VS-Code feature parity for the features that make an editor useful day to day —
search, source control, tasks/diagnostics, and genuine language intelligence — using only trusted,
in-process, build-time-loaded Jac modules (extension-system "Phase A" per `architecture.md`'s
phased trust model), with **zero dependency on dynamic loading, a manifest format, or any
`.vsix`/`vscode`-API compatibility work.** This is the flagship phase of the native-feature-parity
milestone described at the top of this document.

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
- **A native Jac LSP client — promoted from "groundwork research" to a flagship deliverable
  (re-scoped 2026-08-31)**: jaclang already ships a real, working language server, started via the
  first-party `jac lsp` CLI command (`jaclang/cli/commands/tools.jac`,
  `jaclang.lsp.server.server.run_lang_server()`), implementing completion, hover, go-to-definition,
  find-references, rename, document-symbols, semantic tokens, and formatting against real Jac
  source. There is no "is a usable LSP client library reachable via interop" research question left
  to answer — the server already exists. The actual work is: (1) spawn `jac lsp` as a subprocess
  the same way the terminal spawns any other process (`root spawn`, the same `shell`-capability
  gate), (2) build a generic client speaking LSP's JSON-RPC-over-stdio wire format, (3) build the
  editor-side consumption UI (completion popup, hover card, go-to-definition, rename, a peek view)
  against a provider interface generic enough that a second language server is a second client
  instance later, not a rewrite. Ship the Jac case first — it's this project's own dominant file
  type. **Bulk-edit application** (applying a multi-file rename/refactor result) and the
  **outline/call-hierarchy/breadcrumbs views** are required parts of this same effort, not separate
  features discovered later (per `vscode-complete-triage.md`'s `bulkEdit`/`callHierarchy`/`outline`
  rows) — a rename provider that can't apply its own result isn't done.
- **A Debug Adapter Protocol client — moved here from the old Phase 5 (re-scoped 2026-08-31)**:
  the same category of problem as the LSP client for the same reason (a debug adapter is just
  another subprocess speaking a JSON wire protocol), so it belongs in the same native-infrastructure
  phase rather than waiting on the extension system. First step: check whether a Python DAP client
  library is usable via Python interop before building one from the wire protocol up (still
  unresearched — see `architecture.md`'s open questions).
- **The real published `jaseci-labs.jaclang-extension` `.vsix` compatibility question is explicitly
  deferred, non-blocking research, not a phase deliverable (downgraded 2026-08-31 from its
  2026-08-28 Phase-4 placement)** — the language-server half of that extension's value is already
  captured by the `jac lsp` client above, without needing to load the `.vsix` at all. What's left
  (whether jac-studio could eventually load the extension's richer TextMate grammar, or the whole
  `.vsix` unmodified) is real but stays a "someday, once Phase 6 investigates `.vsix` compatibility
  generally" question — the Phase 3 Monarch tokenizer stays the working baseline until then.
- **An Output panel with a log-channel abstraction** — moved earlier than its upstream scale would
  suggest, because it's needed to debug the extensions being written *in this phase*, not just as
  a later user-facing feature (per [`vscode-complete-triage.md`](vscode-complete-triage.md)'s
  `output`/`logs` row). Also the natural place to surface `jac lsp`'s and the DAP client's own
  logs.
- **A merge-conflict UI** alongside the SCM work above — real conflicts only exist once real git
  integration does, so this is the natural phase for it, distinct from the two-way diff editor
  already shipped in Phase 3.
- **Toast notifications + a notification center** (`workbench/browser/parts/notifications`, found
  2026-08-28 — see `vscode-complete-triage.md`'s "workbench/browser/parts" section, previously
  undocumented as a UI surface). Genuine prerequisite here, not polish deferred further: the task
  runner, SCM operations, and language server above all need a way to report background
  success/failure to the user, and there's currently no UI surface for that at all.

Exit criteria: a fourth built-in feature can be added purely by writing a new contributing module,
with zero changes to existing workbench code — the actual test of whether the contribution model
is real; SCM shows real git status/diffs and can resolve a merge conflict; a build task's errors
show up in a Problems panel; extension output is visible in a log channel; a background task's
completion surfaces as a toast notification; **opening a `.jac` file gets real completion, hover,
go-to-definition, find-references, and rename against `jac lsp` — not just syntax highlighting**;
a debug session can set a breakpoint and step through at least one language's code via a real DAP
adapter.

## Phase 5 — Native AI coding-tool integrations

Goal: a small, explicitly-named set of external AI coding tools work natively inside jac-studio,
without building a generic mechanism for arbitrary third-party chat/agent extensions to plug in
(that remains deferred to the extension-system Phase B/C track below). See `architecture.md`'s "AI
coding tool integrations" section for the full reasoning — this phase turns that design into a
scoped deliverable.

- **Claude Code — done (2026-09-03, PR #69).** `claude_code_client.jac` (subprocess-only, gated
  behind `[terminal] enabled`, real streaming + multi-turn continuity via the SDK's own `resume`
  mechanism) + `ai_chat.jac`'s sidebar panel. Live-verified end to end via a real `jac run` +
  `jac browse` session, not just `jac check`. Meets this phase's original exit criterion below on
  its own.
- **GitHub Copilot** — realistic shape: the same subprocess/JSON-RPC pattern as the LSP/DAP clients
  above, since Copilot's own inline-completion path runs a bundled `copilot-language-server`
  subprocess in real VS Code too, not primarily through chat-extension APIs. Needs its own scoping
  pass first (auth/licensing model, exact protocol surface). Not started.
- **OpenCode** — CLI-first, SDK/subprocess-drivable agentic tool; the realistic integration shape is
  a spawned, capability-gated process (the terminal's own mechanism) with output streamed back via
  the SSE/`Generator` pattern already used for LLM-token streaming. Needs its own scoping pass
  before implementation, same as Copilot. Not started.
- **`by llm()`/`sem`-based native features** (inline suggestions, a native chat panel jac-studio
  owns outright) are a legitimate parallel track here too, not superseded by the external
  integrations above — build whichever gives the fastest real signal first.

**Reframed 2026-09-03, still within this phase, not a scope change to the bullets above**: two real
research passes (a live `microsoft/vscode` checkout's actual Copilot Chat source, and jaseci's own
native agentic capabilities — see `architecture.md`'s "AI coding tool integrations" section, "Reframed
2026-09-03" for the full reasoning and both linked research docs) found that VS Code's own AI UI/UX
(the "Fix"/"Explain" quick-fix menu, inline chat, inline completions) is built entirely on generic,
backend-agnostic Monaco/editor APIs — meaning richer AI UX in jac-studio is achievable as new *UI
entry points* against the `start_chat_turn` mechanism already shipped, not new integrations per se.
Added to this phase's scope:

- **AI code actions** (Monaco `CodeActionProvider` contributing "Fix"/"Explain"/"Modify", same
  category as the LSP client's existing providers) — smallest lift, total backend reuse.
- **Inline chat** (a Ctrl+I popover, a Monaco content-widget anchored at cursor/selection) — medium
  lift, same backend reuse.
- **A native, dependency-free agent provider** built on `by llm(tools=[...])` using jac-studio's own
  already-built Phase 4 service functions as tools (`create_file`, `run_in_terminal`,
  `search_in_files`, ...) — a fourth provider option needing no external CLI, just a model API key.
  Not a replacement for the external-tool integrations (an external agentic CLI brings permission
  prompting, context management, and a curated tool set a from-scratch `by llm()` loop starts
  without) — a real parallel option, per the research doc's own caveats.
- **MCP wiring for the Claude Code provider — done (2026-09-03).** `jac mcp` is a real, working
  MCP server (confirmed: `jac mcp --inspect` lists 140 resources/19 tools/9 prompts) that
  `claude_agent_sdk.ClaudeAgentOptions.mcp_servers` (a real, introspected field) now points at,
  landing in `claude_code_launcher.py` (not `claude_code_client.jac` as this bullet originally
  said — that module never touches `ClaudeAgentOptions` at all, for the same import-explosion
  reason the launcher exists as its own plain-Python process; `mcp_servers={"jac": {"command":
  "jac", "args": ["mcp"]}}` only needed adding where the options object is actually built).
  Live-verified end to end, not just wired and assumed: a real turn against Claude Code sees and
  correctly names all 19 `mcp__jac__*` tools, and a direct SDK call with permissions granted
  confirms one (`validate_jac`) genuinely executes over the stdio connection and returns a real
  result. **A real, honest finding from that verification, not a gap in this change**: by default
  the SDK blocks calling *any* MCP tool without prior approval, identically to how it already
  gates Bash/Edit/Write — invisible to jac-studio's UI today for the same reason those are. That's
  the tool-approval gap this phase already tracks as its own, separate, higher-priority item
  below, not something this bullet needed to solve to be complete.

**A second, more systematic pass (same day) went through all 84 top-level entries in upstream's
`chat/browser/`, not just what one screenshot led to — see the research doc's own "full audit"
section for the complete categorized list.** Two real, currently-missing capabilities surfaced,
higher priority than the UI items above since they're trust/safety and data-loss gaps, not just
polish:

- **Tool approval/confirmation — done (2026-09-03).** `ClaudeAgentOptions.can_use_tool` is wired up
  in `claude_code_launcher.py`, gating Edit/Write/Bash/MCP calls behind a real approve/deny card in
  `ai_chat.jac` instead of the SDK's own silent default (confirmed live, before this change: a
  denied-by-default `Write` and a denied-by-default MCP tool call, neither ever asking). The
  decision crosses the same file-based cross-process channel `dap_client.jac`'s command file
  already established, for the same reason (the launcher and the RPC handling the decision are
  different OS processes). Live-verified end to end via `jac browse`: Allow lets a real write land
  on disk and the turn continue; Deny blocks it. See `architecture.md`'s item 4 for the full record,
  including a real concatenation bug found and fixed during that same live verification pass.
- **Multi-file edit review — done (2026-09-03), v1-scoped as this bullet already named.** A real
  Monaco diff (new `ai_tool_diff_preview.jac`) now renders inside each `Edit`/`Write` approval card
  from the tool-approval item above, computed in `claude_code_launcher.py` before the tool call ever
  runs. Not upstream's checkpoint/timeline scope, deliberately, per this bullet's own original call
  — a per-file before/after preview closes the actual risk (a silent overwrite) without it.
  Live-verified end to end via `jac browse`: both a `Write` and a chained `Edit` produced a correct
  diff card, confirmed by screenshot against what actually landed on disk. See `architecture.md`'s
  item 5 for the full record.
- **A portable AI-plugin format worth supporting, not inventing**: VS Code natively parses
  `.claude-plugin/plugin.json` bundles (`hooks`/`commands`/`skills`/`agents`/`mcpServerDefinitions`)
  — the exact format Claude Code's own plugin system already uses. Since jac-studio's Claude Code
  provider already talks to real Claude Code, a discovery/install feature for these bundles needs
  no new format design.

Exit criteria (unchanged, already met): at least one of the three named tools is usable end to end
inside jac-studio for a real coding task (not a mock/demo), with its own auth flow and output
surfaced through the Output/notification infra Phase 4 already built. The reframed items above are
this phase's next concrete steps, not new exit-criteria — Copilot/OpenCode and the UI/native-agent
expansion remain open work within this same phase.

## Phase 6 — Extension system, Phase B (dynamic, still trusted)

Goal: extensions become separate packages with a manifest, loaded at runtime — the first phase of
the *later*, non-blocking third-party-extension track (see the 2026-08-31 re-prioritization at the
top of this document). Nothing in Phases 1–5's native-feature-parity milestone depends on this
phase shipping.

- Design the manifest format (deliberately deferred in `architecture.md`) — this is also where the
  vscode-API-compatibility question (how much of VS Code's actual `vscode` module to shim, using
  the real `jaseci-labs.jaclang-extension` `.vsix` as the concrete test case per `architecture.md`'s
  open questions) finally needs answering, since it changes the manifest shape significantly. Not
  needed any earlier — Phase 4's language intelligence got the useful part of that extension's
  value already, without this.
- Dynamic loading at runtime, still fully trusted — no isolation yet.
- **Extensions view** (browse/install/enable/disable/uninstall) — now that extensions load
  dynamically, they need a management UI; not previously called out as distinct from the trust
  model itself (per [`vscode-complete-triage.md`](vscode-complete-triage.md)'s `extensions` row).
- **An auth-provider broker + secret storage** — an extension needing to authenticate against an
  external service (git hosting, a language server needing a license token, anything) needs
  somewhere to request/share OAuth tokens and store credentials safely rather than each extension
  reinventing it in plaintext settings. Small (upstream's `encryption` contrib is 48 lines, a thin
  OS-keychain wrapper) but a real dependency once any auth-requiring extension is written — and by
  this phase, Phase 5's Copilot/OpenCode/Claude Code integrations already need something like it,
  worth checking whether their auth needs can reuse this broker rather than each rolling its own.
- **Auxiliary bar** (`workbench/browser/parts/auxiliarybar`, found 2026-08-28 — see
  `vscode-complete-triage.md`) — the secondary/right-side dockable panel. Upstream uses it for
  Chat (excluded here, see `chat`'s Tier 2.5 disposition) but it's generic dockable-panel infra
  independent of that — worth building once Search/SCM/Extensions views are competing for the
  same sidebar real estate, which is true by this phase.
- **"Continue Working On" / edit-session sync** (`editSessions`, found 2026-08-28) — syncs
  uncommitted changes across devices via the same account the auth broker above manages. Natural
  pairing with that broker and with `userDataSync`/`userDataProfile` (already Tracked); include if
  time allows, not exit-blocking.

Exit criteria: an extension can be installed/removed without a rebuild of the app itself.

## Phase 7 — Extension sandboxing (Phase C) — treat as its own research track

Goal: untrusted third-party extension code, safely isolated.

This is explicitly R&D, not integration work (see `architecture.md`). Do not start this before
Phase 6 has validated the extension-API surface against real usage. Likely built on Jac's
native+WASM compilation path; expect this phase to produce the largest volume of tracker entries
in the whole project, since there's no existing Jac precedent to lean on at all.

## Phase 8 — Desktop packaging

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
- A public extension marketplace/registry — depends entirely on Phase 6/7 outcomes.
- Collaborative real-time editing — the multi-user access-control primitives exist in Jac
  (`root.shared`, `grant`/`revoke`) and would make this more tractable than in a from-scratch
  stack, but it's not on the critical path to a usable single-user MVP.
