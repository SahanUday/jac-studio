# What VS Code has that jac-studio's plan doesn't yet cover

Status: v1 — 2026-08-22. A second, targeted pass over `/home/sahan/dev/vs/vscode`, specifically
enumerating `src/vs/workbench/contrib/*` (99 feature areas), `src/vs/editor/contrib/*` (59
editor-level feature areas), and `extensions/*` (106 built-in extensions), then checking each
against [`architecture.md`](architecture.md) and [`roadmap.md`](roadmap.md) for coverage. Sizes
are measured (`find | wc -l` on the real checkout), not estimated. This supersedes nothing in
those two docs — it's the gap list that should feed edits to them, and several have already been
applied (marked below).

## Tier 1 — foundational, should be scoped now (comparable in importance to the DAP client)

### Language intelligence (IntelliSense) — the biggest omission

Everything we'd written about language support so far was "syntax highlighting via a TextMate
grammar" (`architecture.md`, Phase 3). That is a completely different, much shallower thing from
what actually makes VS Code useful day to day: autocomplete, hover docs, go-to-definition,
find-references, rename-symbol, quick-fixes, signature help. In real VS Code this is:

- A **48-method provider API surface** in `vscode.d.ts` (`registerCompletionItemProvider`,
  `registerHoverProvider`, `registerDefinitionProvider`, `registerCodeActionsProvider`,
  `registerRenameProvider`, `registerDocumentFormattingEditProvider`,
  `registerReferenceProvider`, `registerSignatureHelpProvider`, `registerCodeLensProvider`,
  `registerDocumentSymbolProvider`, `registerFoldingRangeProvider`,
  `registerInlayHintsProvider`, ...) — extensions implement these, the workbench never has
  built-in per-language knowledge itself.
- A large **editor-level consumption layer** — `src/vs/editor/contrib/{suggest,hover,gotoSymbol,
  rename,codeAction,codelens,parameterHints,documentSymbols,semanticTokens,format,
  linkedEditing,peekView}` (suggest alone: 9,042 lines; hover: 5,392 lines) — the UI/UX that
  turns provider responses into the actual autocomplete popup, hover card, peek view, etc.
- In practice, this is almost always backed by the **Language Server Protocol** — VS Code's
  provider API is effectively an LSP client wrapper, and most language extensions
  (`typescript-language-features`, `html-language-features`, `css-language-features`,
  `json-language-features` — all present in `extensions/`) are thin bridges to a real language
  server process speaking LSP over stdio.

**This needs the same treatment we gave the Debug Adapter Protocol**: its own architecture
section and roadmap placement, not an assumption that it falls out of the general extension
model.

**Resolved 2026-08-31 — the framing above ("real language intelligence is extension-contributed in
upstream VS Code too") led this document to file the work behind the extension system by analogy,
which turned out to be the wrong call for jac-studio specifically.** Checking jaclang's own source
directly (not just upstream's) found that a real LSP server already ships in jaclang core: `jac lsp`
(`jaclang/cli/commands/tools.jac`) starts `jaclang.lsp.server.server.run_lang_server()`, a genuine
server already implementing completion, hover, definition, references, rename, document-symbols,
semantic tokens, and formatting. The "first research task" this section used to pose — is there a
usable LSP client library reachable via interop — was aimed at the wrong half of the problem: the
*server* is already solved and Jac-native; what's left is an ordinary generic client speaking
stdio JSON-RPC to it, ontologically the same "spawn a subprocess, speak a wire format" pattern
already scoped for the terminal. This removes the dependency on the general extension system
entirely for the Jac case — see `architecture.md`'s "Language intelligence" section and
`roadmap.md`'s Phase 4 (promoted from "groundwork" to a flagship deliverable, alongside the DAP
client for the same reason). The *editor-side* consumption layer (completion popup, hover card,
go-to-definition, rename, bulk-edit apply) lands in the same phase now that there's a real backend
to build it against immediately, rather than waiting on a hypothetical future provider.

### Source control (SCM) + diff editor

`workbench/contrib/scm` (14,463 lines) is a first-class workbench part — its own activity-bar
icon, its own view, change decorations in the gutter and the file tree, not "a git status
indicator" as Phase 4 currently describes it in passing. The actual git logic lives in the
built-in `extensions/git` extension (which talks to the `git` CLI as a subprocess — same
mechanism as the terminal work already scoped for Phase 2), while `workbench/contrib/scm`
provides a source-control-*system-agnostic* UI shell that any VCS extension can plug into.
Separately, `multiDiffEditor` (1,461 lines) and the diff-editor mode of the editor core itself are
what render "compare these two versions" — a core editing capability, not an SCM-only feature (used
for merge conflicts, `git diff`, and comparing arbitrary files). **Recommendation**: scope a
diff-editor mode as part of the editor-core work (Phase 1/3, it's a rendering mode over the same
text-buffer model, not new infrastructure), and scope an SCM-provider-shell + a first git
implementation as a Phase 4 extension — a good, concrete second candidate alongside "search-in-
files" for proving the contribution registry isn't a toy.

### Tasks system + Problems panel

`workbench/contrib/tasks` (18,765 lines) is materially different from the ad-hoc terminal command
scoped for Phase 2: it's a declarative task-definition format (`tasks.json`-equivalent) plus
**problem matchers** — regexes that parse a build tool's stdout/stderr into structured
file/line/column diagnostics. Those diagnostics, plus every diagnostic a language server reports,
flow into `workbench/contrib/markers` (4,933 lines) — the unified Problems panel. Currently
nothing in our plan produces structured diagnostics at all; "run in terminal" only gives you raw
text output. **Recommendation**: scope both together as a Phase 3/4 addition — a `Diagnostic`
node type attached to `File` in the workspace graph (fits the existing data model directly, per
`architecture.md`), populated by both task problem-matchers and (once it exists) the language-
intelligence layer above.

### Keybinding "when clause" context system

We'd scoped keybindings as persisted *data* (`architecture.md`'s data model) but not the
*dispatch* mechanism — `src/vs/platform/contextkey` (4,484 lines, 229 uses of `ContextKeyExpr`
across the codebase) is what decides, at any given moment, which command a keystroke actually
triggers, based on a boolean expression over current UI state (`editorTextFocus &&
!suggestWidgetVisible`, `sideBarVisible`, etc.). Without this, keybindings can only be global,
which breaks the moment two features want the same key (e.g. `Escape` closing a suggestion popup
vs. exiting a modal). **Recommendation**: scope this as part of Phase 2's command-registry work —
it's the same registry the command palette already needs, just with a context-evaluation layer
added, so it's cheap to add now and expensive to retrofit later.

## Tier 2 — real, but appropriately later than MVP (confirm placement, don't forget)

- **Search** (`workbench/contrib/search`, 17,515 lines): find/replace *across* the workspace, not
  just within one file (that part, `editor/contrib/find`, is already implicit in editor-core
  scope). Not yet its own roadmap line item — recommend adding to Phase 4 as a third concrete
  contributed feature alongside SCM and "search-in-files" (already listed as an example in
  `roadmap.md` — this tier-2 entry is really just "make sure that example becomes a real scoped
  item, not just an example").
- **Testing framework** (`workbench/contrib/testing`, 24,094 lines): Test Explorer UI, inline
  run/debug-test affordances. Genuinely a Phase 6+ concern — needs the extension manifest system
  (the DAP client itself now lands earlier, Phase 4, per the 2026-08-31 re-prioritization). No
  action needed now beyond noting it exists.
- **Webviews + custom editors** (`webview` 3,258 + `customEditor` 2,493 lines): lets an extension
  render arbitrary HTML UI inside a panel or as a file's editor (Markdown preview, image/hex
  viewers). Needed for a real extension ecosystem eventually; not needed for Phases 1–3. Worth
  noting that this is architecturally easy for us relative to upstream — it's "render a jac-cl
  component inside a panel," which is close to native for a framework already built around
  JSX-like components, rather than upstream's iframe-sandboxing problem.
- **Snippets** (4,007 lines): small, self-contained, easy to add whenever — no urgency.
- **Settings Sync / Profiles** (`userDataSync`, 2,578 lines): cross-device sync of settings and
  installed extensions. Worth flagging as a place where Jac's persistence-by-reachability model
  might make this *easier* than upstream rather than harder — if settings already live in the
  graph reachable from a user's `root`, "sync across devices" starts to look like "the same root,
  reached from two machines," which is closer to Jac's native multi-user story than to a bespoke
  sync protocol. Not scoped, but worth a design spike whenever Phase 3 settings work lands.

## Tier 2.5 — a genuine strategic surprise, not just a missing feature

**`workbench/contrib/chat` is 442,661 lines — larger than the entire `src/vs/editor` layer
(279,192 lines).** This wasn't a hypothesis; it's a measured fact from this pass. VS Code's
chat/agent infrastructure (inline chat, agent sessions, voice input, prompt/tools services) has
become its single largest subsystem, bigger than Monaco itself — a real signal of where the
product has actually gone since the "text editor with extensions" framing this whole
reimplementation is scoped around.

This is deliberately **not** filed as a roadmap gap to close by porting 442K lines of chat UI.
Jac already has `by llm()` and `sem` annotations as first-class language features
(`jac-by-llm.md`) — an AI-assist story for jac-studio likely looks architecturally different from
upstream's bolted-on chat panel (which exists because TypeScript has no native LLM-call syntax to
build on). Flagging this now so it's a deliberate future design decision — "what does AI
assistance look like when the host language has LLM calls built in" — rather than something
rediscovered late and defaulted into a copy of upstream's approach.

**Sharpened 2026-08-31, per explicit project-sponsor direction**: rather than leaving this as an
indefinitely-deferred design question, a small, explicitly-named set of native integrations with
*existing* external AI coding tools (GitHub Copilot, OpenCode, Claude Code) is now a scoped
roadmap deliverable — `roadmap.md`'s Phase 5, `architecture.md`'s "AI coding tool integrations"
section. The port-upstream's-chat-subsystem non-goal above is unchanged; what's new is that
jac-studio no longer treats "wait for a general extension system to make arbitrary chat extensions
pluggable" as the implicit path to AI assistance either — these three tools get direct,
subprocess/SDK-driven integrations (the same shape already used for the terminal and, now, the LSP
and DAP clients), while `by llm()`/`sem` remain the native, first-class path for anything
jac-studio builds itself.

## Tier 3 — confirmed, deliberate non-goals (not forgotten, just out of scope)

- **Remote development** (SSH/Containers/WSL/Tunnels, `workbench/contrib/remote*`): already
  correctly listed as out of scope in `roadmap.md`. This pass found nothing to change that
  decision on.
- **Telemetry**: VS Code ships an opt-out telemetry pipeline (`workbench/contrib/telemetry`,
  `editTelemetry`); VSCodium's own first move is stripping it entirely
  (`research/vscodium-packaging.md`). Consistent with that precedent and with not needing it for
  any planned feature, jac-studio should default to none rather than "add it later" — a deliberate
  choice, not an oversight to fix.
- **Notebooks** (`workbench/contrib/notebook`, 94,908 lines — genuinely huge, bigger than the
  entire `workbench/services` layer would be on its own): Jupyter-style cell editing is a
  substantial, mostly self-contained subsystem with no dependency from anything else in this
  plan. Explicitly out of scope until there's a specific reason to want it — noting its real size
  here so it's a deliberate exclusion, not a surprise later.
- **Accessibility infrastructure** (`accessibility`, `accessibilitySignals`, `speech`,
  `agentsVoice`): real and important for a genuinely shippable product, appropriately after MVP.
  Listed here so it doesn't get silently forgotten past the phases where it'd be natural to add
  it (screen-reader semantics belong in the workbench-shell components from the start, even if
  full support lands later) — worth a one-line reminder in Phase 2's component work: build
  workbench components with real ARIA semantics from day one, even before dedicated
  accessibility features are scoped, since retrofitting is much more expensive than building in.

## What this changes in the existing docs

Applied directly to `roadmap.md` and `architecture.md` in the same pass as this document (see
those files for the actual phase placements): language-intelligence provider layer and SCM/diff
editor added to Phase 3/4, tasks+problems and the keybinding context system added to Phase 2/3.
Everything in Tier 2/2.5/3 is recorded here rather than folded into the roadmap yet — deliberately,
so the roadmap doesn't grow line items faster than the team can actually reason about sequencing
them. Revisit this document each time a new phase is about to start, not just once.
