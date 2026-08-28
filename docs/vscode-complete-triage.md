# Complete triage: every upstream workbench feature area, one disposition each

Status: v3 — 2026-08-28. Direct answer to "have we documented all of VS Code, covered by a Jac
version?": **no, not fully designed — and that's intentional, per the MVP-first principle in
[`architecture.md`](architecture.md).** What this document provides instead is a different,
achievable bar: **every one of the 100 areas in `src/vs/workbench/contrib/*` (99 at v2's count —
`gh api repos/microsoft/vscode/contents/src/vs/workbench/contrib` now returns 100; see v3 below
for the three that weren't yet triaged), and every one of the 59 areas in `src/vs/editor/contrib/*`
(unchanged, reverified), has been looked at and assigned a disposition.** Nothing upstream is
silently unaddressed anymore, even where the honest disposition is "deferred, not designed yet."

**v3 (2026-08-28)**: reverified directly against the live `microsoft/vscode` source on GitHub
(`gh api repos/microsoft/vscode/contents/...`), not just re-read from this document — v1/v2 were
never checked against the actual upstream tree, only against research notes. That check found two
real gaps this document had missed entirely (`editSessions`, `update` — see their new rows below)
plus one trivial one (`commands`), and — more significantly — that this document's own stated scope
("`workbench/contrib` + `editor/contrib`") was itself incomplete: VS Code's activity bar, title bar,
auxiliary (secondary side) bar, and notifications center live in `workbench/browser/parts/*`, a
sibling tree this document never triaged at all. See the new "workbench/browser/parts" section
below for that gap, added rather than silently left for the next person to rediscover.

v1 of this document clustered all 59 `editor/contrib` areas under Language Intelligence as a
single group without checking them individually — on closer inspection that claim was wrong: about
half of them are basic text-editing operations (cursor movement, clipboard, multi-cursor, find-in-
file) that belong under core editor work, not language intelligence at all. Corrected below rather
than left standing.

Legend: **Scoped** = has real architecture + a roadmap phase. **Tracked** = named, disposition
decided, not yet designed in detail. **Excluded** = deliberate non-goal, with a reason. **New** =
found during this triage pass, not previously mentioned anywhere in the docs.

| Area | Disposition | Where |
|---|---|---|
| files | Scoped | Phase 2 — file tree on the workspace-as-graph model |
| folding, format | Scoped | Language intelligence cluster, `architecture.md` |
| terminal, terminalContrib, externalTerminal | Scoped | Phase 2 — integrated terminal |
| debug | Scoped | Phase 5 — DAP client |
| scm, git | Scoped | Phase 4 — SCM shell + git provider |
| multiDiffEditor | Scoped | Phase 3 — diff-editor mode |
| tasks | Scoped | Phase 4 — task runner + problem matchers |
| markers | Scoped | Phase 3/4 — `Diagnostic` node type + Problems panel |
| keybindings, keybindingsExport | Scoped | Phase 2/3 — context system + persisted keybindings |
| preferences | Scoped | Phase 3 — settings as graph-attached objects (this *is* the settings UI contrib) |
| quickaccess | Done | Command palette shipped Phase 2. Quick Open (Ctrl+P fuzzy file switcher), the distinct second provider under this same contrib, slipped from Phase 2 (documented but never built — see `docs/phases/phase-2-workbench-shell.md`'s "what's left") and shipped in Phase 3 instead (`src/workbench/quick_open/quick_open.jac`, 2026-08-28) — see `roadmap.md`'s Phase 3 section |
| search, searchEditor | Scoped | Phase 4 — search-in-files |
| extensions | Scoped, **partially New** | Phases 4–6 cover the extension *runtime*/trust model; this specific contrib is the Extensions *view* (browse/install/manage) — not previously called out as its own UI surface. Add to Phase 5: once extensions are dynamically loadable, they need a UI to install/enable/disable/uninstall from. Cheap addition to that phase, not a new one. |
| webview, webviewPanel, webviewView, customEditor | Tracked | Gap analysis Tier 2 — noted as architecturally easier for us than upstream (a jac-cl component in a panel vs. upstream's iframe sandbox) |
| snippets | Tracked | Gap analysis Tier 2 — small, no urgency |
| testing | Tracked | Gap analysis Tier 2 — Phase 5+, needs extension manifests + DAP |
| userDataSync, userDataProfile | Tracked | Gap analysis Tier 2 — flagged as possibly *easier* via Jac's graph model |
| notebook, replNotebook | Excluded | Gap analysis Tier 3 — 94,908 lines, no dependency from anything else planned |
| telemetry, editTelemetry, bracketPairColorizer2Telemetry, surveys, tags | Excluded | Gap analysis Tier 3 — deliberate, consistent with VSCodium's own choice |
| remote, remoteTunnel, remoteCodingAgents | Excluded | `roadmap.md` — remote development explicitly out of scope |
| accessibility, accessibilitySignals, speech, agentsVoice | Tracked | Gap analysis Tier 3 — deferred, but "build real ARIA semantics from day one" is already a Phase 2 note |
| chat, inlineChat, interactive, mcp, welcomeAgentSessions | Tracked | Gap analysis Tier 2.5 — 442,661 lines, deliberately not ported; revisit with `by llm()` as the starting point instead |
| **authentication** | **New — Tracked** | 1,356 lines. Auth-provider broker letting extensions share OAuth tokens (e.g. GitHub sign-in used by multiple extensions at once) rather than each prompting separately. Needed the moment any extension needs to authenticate against an external service. Add to Phase 5 alongside the extension manifest work — a natural pair with `encryption` below. |
| **encryption** | **New — Tracked** | 48 lines (thin wrapper over an OS keychain). SecretStorage API for extensions to store credentials safely instead of plaintext settings. Same phase as `authentication` — they're used together in practice. |
| **bulkEdit** | **New — Tracked** | 3,505 lines. Multi-file edit preview/apply — what actually executes a rename-symbol that touches 40 files, or a multi-file refactor from a code action. This is a real dependency of the Language Intelligence work, not a separate feature — a rename provider is useless without something to apply its result. Fold into the Phase 4+ language-intelligence work as a required piece, not an afterthought. |
| **callHierarchy, typeHierarchy, outline, languageStatus, languageDetection, codeActions, codeEditor** | **New — folded in** | All are workbench-side UI consumers of language-intelligence provider data (call-hierarchy panel, outline/breadcrumbs, the little language-mode indicator in the status bar) — the same family as the completion popup and hover card already mentioned in `architecture.md`'s Language Intelligence section, just not individually named there. No new phase; the existing placement already covers this cluster, this triage just makes the coverage explicit instead of implicit. |
| **comments** | **New — Tracked** | 8,588 lines. PR/code-review comment threads anchored to file ranges — what GitHub's PR extension builds on. Extension-ecosystem feature, not core; Tracked for whenever a review-tooling extension is wanted, no earlier. |
| **mergeEditor** | **New — Tracked** | 8,961 lines. Three-way merge-conflict resolution UI — genuinely distinct from the two-way diff editor already scoped for Phase 3. Real gap: add to Phase 4 alongside SCM/git, since conflicts only exist once real git integration does. |
| **themes** | **Split: Done (Phase 3) + open question (Phase 4/5)** | 1,631 lines. Upstream's installable, JSON-based color-theme/icon-theme extension model. Jac already has its own theming primitive (`jac retheme`, OKLCH-based, per `jac-shadcn-components.md`) — a *different* mechanism. Two separate questions, previously conflated: (1) **default visual identity** — should jac-studio's out-of-the-box look match VS Code's own default palette and Codicons, regardless of any extension system? **Decided and implemented 2026-08-28** — yes, via native `jac retheme` tokens plus hand-edited exact values, real `@vscode/codicons` icons (see `roadmap.md`/`architecture.md`). **Correction, same day**: the actual current default checked directly against the live `microsoft/vscode` source is "Dark 2026"/"Light 2026", not "Dark+"/"Light+" as first assumed here and in `architecture.md` — a real palette difference (the classic blue status bar is gone), not a naming nitpick; `architecture.md`'s Visual identity section carries the full correction. (2) **installable third-party `.vsix` theme-extension compatibility** — still a genuine open question, not decided; worth resolving once Phase 4/5 extensions exist to actually contribute a theme — see `architecture.md`'s open questions list. |
| **localization** | **New — Tracked** | i18n of the workbench UI itself (upstream ships ~14 languages via `vs/nls`). Not addressed anywhere in the docs so far. Tracked as a Tier 2/3 concern — real for a genuinely shippable product, not needed for any MVP phase. |
| **timeline, localHistory** | **New — Tracked** | 1,791 + 1,113 lines. File-history views — one git-backed, one local-auto-save-backed. Pairs naturally with SCM (Phase 4). Interesting note: local history might be closer to "free" for us than upstream, if old graph states are retained rather than requiring a bespoke revision-snapshot mechanism — worth a design spike when Phase 4 lands, not before. |
| **output, logs** | **New — Tracked** | 3,783 lines. The Output panel — log channels for extensions/language servers. Genuinely useful *earlier* than its upstream-scale suggests: you need this to debug your own extensions during Phase 4/5 development, not just as a user-facing feature. Recommend pulling this into Phase 4 as basic infra (a channel abstraction + a simple panel), not deferring it with the rest of Tier 2. |
| **workspace, workspaces** | **New — Tracked, cheap** | 2,136 + 297 lines. Multi-root workspaces (multiple top-level folders in one window, `.code-workspace`-equivalent files) — genuinely unaddressed until now. Good news found during this triage: the existing data model (`Workspace --Contains--> Folder`, `architecture.md`) already supports multiple `Folder` nodes under one `Workspace` with zero changes — this is a case where the graph model happens to already handle it. Low-cost addition to Phase 2/3, not a new subsystem. |
| dropOrPasteInto | New — Tracked | Minor editor feature (paste an image → insert markdown, etc.). Low priority, no phase assigned yet. |
| emmet | New — clarified | Not core infra at all — in upstream this ships as an ordinary built-in *extension* (`extensions/emmet`). Once the Phase 4 extension system exists, this is just "an extension someone could write," not a workbench feature to design. |
| externalUriOpener, opener, url | New — Tracked | URI-scheme handling (`vscode://`-equivalent, "open in browser"). Low priority. |
| share | New — Tracked | "Copy link to this line" sharing. Low priority, polish-tier. |
| issue | New — Tracked | Built-in issue reporter. Low priority — though there's a mildly interesting idea of wiring this into our own challenge tracker someday rather than building a generic reporter; not pursued now. |
| onboarding, welcomeBanner, welcomeGettingStarted, welcomeOnboarding, welcomeViews, welcomeWalkthrough | New — Tracked | The "Getting Started" walkthrough experience. Polish-tier, no phase assigned. |
| limitIndicator, meteredConnection, modernUI, emergencyAlert, relauncher, splash, performance, processExplorer, policyExport, scrollLocking, sash, list, browserView, imageCarousel | New — mostly not applicable | Internal plumbing/UI-kit details specific to VS Code's own Electron implementation (a splash screen, a "reload window" relauncher, a virtualized-list widget, Electron's own process explorer) or already covered by an existing choice (`sash` ≈ our `Resizable` shadcn primitive, per `architecture.md`'s workbench-shell mapping). Nothing to design here beyond what's already decided. |
| **commands** | **New (v3) — not applicable** | 4.8KB, `commands.contribution.ts` only. Just registers upstream's own built-in global commands (reload window, etc.) — the exact role `src/workbench/commands/command_registry.jac` already plays natively. Not a feature to port, confirms the existing design rather than adding to it. |
| **editSessions** | **New (v3) — Tracked** | ~110KB across 7 files. "Continue Working On" — syncs uncommitted changes across devices via a Microsoft-account-backed cloud store, so a user can pick up mid-edit on another machine. Genuinely missed by v1/v2 (never checked against the live upstream tree). Pairs with the already-Tracked `userDataSync`/`userDataProfile` and depends on the same `authentication` broker staged for Phase 5 — group with those, no earlier. |
| **update** | **New (v3) — Tracked, partially Scoped** | ~120KB across 8 files: in-app update UI (release-notes viewer, "Restart to Update" notification, title-bar update indicator) — distinct from `roadmap.md` Phase 7's "auto-update feed" bullet, which is the *packaging/build* side (the feed itself, code signing). Phase 7's bullet covers shipping updates; this is the in-app UI *telling the user* one's available — add as an explicit Phase 7 sub-bullet so it isn't assumed to fall out of the feed for free. |

## `workbench/browser/parts` — chrome & layout (a separate tree from `contrib`, newly triaged)

Found during the v3 (2026-08-28) live-source check: everything above is `workbench/contrib/*`, the
*feature* layer. VS Code's actual window chrome — the parts a user's eye lands on first, and
exactly what "match VS Code's default visual identity" (the decision recorded in `architecture.md`
following this document's earlier `themes` row) is about — lives in a sibling tree,
`workbench/browser/parts/*`, that neither v1 nor v2 of this document ever triaged. Confirmed via
`gh api repos/microsoft/vscode/contents/src/vs/workbench/browser/parts`:

| Part | Disposition | Notes |
|---|---|---|
| **activitybar** | **New — Scoped, Phase 3/4** | The icon rail down the left edge (Explorer/Search/SCM/Debug/Extensions, sidebar toggle). `architecture.md`'s primitive-mapping table previously folded this into one "Activity bar + sidebar → `Sidebar`" row — that's wrong: `activitybarPart.ts` is its own module upstream, distinct from `sidebar`, because it's a multi-view *switcher*, not a container. Hasn't mattered yet since Phase 2 shipped exactly one sidebar view (Explorer); becomes load-bearing the moment Phase 4 adds Search/SCM views with nowhere else to mount. Scope it explicitly now (Phase 3, alongside the other visual-identity work) rather than retrofitting it under Phase 4 time pressure. |
| **titlebar** | **New — Tracked** | The custom title bar (window controls + centered Command Center search box + menu). Directly relevant to the default-visual-identity decision — this is one of the most visually distinctive pieces of "looking like VS Code," and was completely unmentioned in any doc before this pass. No phase assigned yet; natural fit alongside `activitybar` once Phase 3's chrome work is underway. |
| **auxiliarybar** | **New — Tracked** | The secondary/right-side dockable panel (upstream uses it for Chat/Copilot and any view a user drags there). Generic dockable-panel infra, useful independent of chat (which stays Tier 2.5/excluded per the `chat` row above) — e.g. as a second home for Search results or SCM. No phase assigned; revisit once Phase 4/5 has more than one panel-worthy view competing for space. |
| **notifications** | **New — Tracked** | Toast notifications + the notification-center bell icon. Previously only glancingly referenced as a backend `IFooService` in the "Not covered" section below, never as its own UI surface. Real prerequisite for Phase 4's task runner and SCM work (both need to report background success/failure to the user) — add as infra alongside those, not deferred further. |
| **banner** | **New — Tracked, low priority** | Dismissible in-app banner messages (e.g. upstream's workspace-trust prompt). Small, polish-tier, no phase assigned. |
| statusbar, sidebar, panel, editor, dialogs, views, compositeBar/paneCompositePart (the shared multi-view-container machinery `activitybar`/`panel`/`auxiliarybar` all sit on) | Already covered | `statusbar`/`sidebar`/`editor`/`panel` already map onto existing choices (`StatusBar` component, `Sidebar` primitive, the Monaco embed, the terminal's bottom panel) per `architecture.md`. `dialogs`/`views` are generic UI-kit plumbing shadcn already provides (`Dialog`, the view-container pattern itself). |

## Editor-level feature areas (`src/vs/editor/contrib`, 59 areas)

Corrected, per the note above — split by what they actually are, not clustered as one group.

**Core editor UX — Phase 1 (Editor core), expanding on the deliberately-basic MVP** (basic
insert/delete/cursor was explicitly scoped for Phase 1; these are the natural next increment, not
a new subsystem): `clipboard`, `caretOperations`, `cursorUndo`, `lineSelection`,
`linesOperations`, `multicursor` (Phase 1 explicitly deferred this — this confirms it as the
right thing to defer, not an oversight), `wordOperations`, `wordPartOperations`, `anchorSelect`,
`smartSelect`, `indentation`, `find` (in-file find/replace — distinct from the workspace-wide
`search` already Scoped in Phase 4), `dnd`, `bracketMatching`, `inPlaceReplace`,
`insertFinalNewLine`, `unusualLineTerminators`, `unicodeHighlighter`, `longLinesHelper` (text-
buffer edge cases — tie directly to the Phase 1 piece-tree/text-model port, same translator work).

**Language-intelligence cluster — Phase 4+, consuming provider data** (this is what the original
v1 clustering was gesturing at, correctly for this subset): `codeAction`, `codelens`,
`colorPicker`, `documentSymbols`, `folding`, `format`, `gotoError` (jumps between diagnostics —
ties to `markers`/Problems), `gotoSymbol`, `hover`, `inlayHints`, `linkedEditing`, `links`,
`parameterHints`, `peekView`, `rename`, `semanticTokens` (language-server-driven highlighting,
richer than TextMate grammars), `snippet` (expansion engine — ties to the already-Tracked
`snippets` workbench contrib), `suggest`, `wordHighlighter` (highlight other occurrences of the
selected symbol), `quickAccess` (editor-level "Go to Symbol in File"), `sectionHeaders`,
`stickyScroll` (both need code-structure awareness, i.e. symbol/outline data), `symbolIcons`
(icon set for symbol kinds, cosmetic layer on top of the same data).

**AI-adjacent, cross-reference not duplicate**: `inlineCompletions` (ghost-text suggestions) is
architecturally the same category as `chat`/`inlineChat` in the workbench-level triage above —
Tier 2.5, deliberately not scoped as a port target, revisit alongside that decision since Jac's
`by llm()` may give it a different natural shape than upstream's.

**Chrome/plumbing — build as needed, no dedicated design**: `contextmenu` (uses the `ContextMenu`
primitive already in the workbench-shell mapping), `message`, `inlineProgress`, `placeholderText`,
`readOnlyMessage`, `floatingMenu`, `zoneWidget`, `comment` (toggle-line-comment — a command, not a
feature), `fontZoom`, `toggleTabFocusMode`, `middleScroll`, `editorState` (ties to the Phase 3
session-persistence work already scoped), `diffEditorBreadcrumbs` (ties to the Phase 3 diff-editor
mode), `tokenization` (the base layer under both TextMate-grammar highlighting and semantic
tokens — already implicit in Phase 1/3, not a separate feature), `dropOrPasteInto` (already listed
in the workbench table above — it's the same feature, cross-cutting both layers), `gpu`
(Monaco's Canvas/WebGL rendering backend — a performance detail specific to upstream's renderer
choice, revisit only if our own rendering performance requires it, not a feature to port).

## What this settles vs. what it doesn't

**Settled — the two `contrib` trees (159 areas total: 100 workbench + 59 editor) plus
`workbench/browser/parts`'s five user-visible chrome components**: no feature area in either
`contrib` tree is unaccounted for anymore — everything has a name, a disposition, and (where
relevant) a phase. Nine real gaps have come out of this document's two passes now: v2's workbench
pass found six (`authentication`+`encryption`, `bulkEdit`, `mergeEditor`, `themes`, `localization`,
`workspace`/multi-root); v3's live-source check (2026-08-28, checked directly against
`microsoft/vscode` on GitHub rather than only against research notes) found three more
(`editSessions`, `update`, and the entire `workbench/browser/parts` tree, which neither v1 nor v2
had ever triaged at all — `commands` was also new but not a real gap, see its row). The editor pass
found no new gaps, only corrected a wrong v1 claim. This is genuinely complete triage of the parts
of VS Code a user directly interacts with, now source-verified rather than notes-verified.

**Not covered by this document, and worth being explicit about rather than implying otherwise**:

- **`extensions/`** — the 106 built-in extensions (language grammars, `git`, `github-
  authentication`, `emmet`, `markdown-language-features`, `docker`, `ipynb`, ...) have been listed
  (`research/vscode-architecture.md`) but not individually triaged the way the two `contrib` trees
  were. Most of them aren't independent design problems for us — they're proof that, once the
  Phase 4/5 extension system and Phase 3 syntax-highlighting exist, each of these becomes "an
  ordinary extension someone writes" rather than core infrastructure to design. A few
  (`github-authentication`, `microsoft-authentication`) are the real-world consumers of the
  `authentication` broker above, and `debug-auto-launch` is a small DAP-adjacent convenience.
  Not triaged item-by-item because the payoff is low relative to the two `contrib` trees — say so
  if you want that done anyway.
- **`platform/`** (580,107 lines, 2,338 files) — only the DI mechanism and IPC transport were
  investigated (`research/vscode-architecture.md`), not a service-by-service inventory (there are
  dozens of `IFooService` interfaces — configuration, storage, quick-input, notifications,
  progress, workspace trust, policy, request/HTTP, extension management, ...). Most back a
  workbench feature already triaged above (e.g. `ISecretStorageService` backs `encryption`,
  `IExtensionGalleryService` backs the Extensions view) rather than being independently
  user-facing — but this hasn't been verified service-by-service, only assumed. The honest
  disposition is: architecturally covered (the root-graph-as-registry proposal is meant to replace
  this whole layer's *pattern*, per `architecture.md`), not feature-by-feature triaged.

Not settled, and not meant to be yet: most "Tracked" rows above have a one-paragraph rationale, not
an architecture section like the Tier 1 items in
[`vscode-feature-gap-analysis.md`](vscode-feature-gap-analysis.md) got. That's the correct amount
of investment for something several phases away — full design work for a feature happens when its
phase is about to start, not years of roadmap in advance. Re-run this triage (or at least reread
it) before starting each new phase, the same instruction the gap-analysis doc already gives itself.
