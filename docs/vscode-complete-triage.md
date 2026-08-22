# Complete triage: every upstream workbench feature area, one disposition each

Status: v1 — 2026-08-22. Direct answer to "have we documented all of VS Code, covered by a Jac
version?": **no, not fully designed — and that's intentional, per the MVP-first principle in
[`architecture.md`](architecture.md).** What this document provides instead is a different,
achievable bar: **every one of the 99 areas in `src/vs/workbench/contrib/*` has been looked at and
assigned a disposition.** Nothing upstream is silently unaddressed anymore, even where the honest
disposition is "deferred, not designed yet." `src/vs/editor/contrib/*` (59 areas) is not
re-triaged item-by-item here — nearly all of it falls under **Language intelligence**
(`architecture.md`) as a single cluster, noted once below rather than 59 times.

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
| quickaccess | Scoped | Phase 2 — folds into command palette; **New** clarification: Quick Open (Ctrl+P fuzzy file switcher) is a distinct provider under this same contrib, not automatically covered by "command palette" alone — same phase, same registry, just note it as a second provider, not a separate phase |
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
| **themes** | **New — open question** | 1,631 lines. Upstream's installable, JSON-based color-theme/icon-theme extension model. Jac already has its own theming primitive (`jac retheme`, OKLCH-based, per `jac-shadcn-components.md`) — a *different* mechanism. Genuine open question, not yet decided: does jac-studio adopt a VS-Code-compatible installable-theme-extension model (ecosystem-compatible, more work) or lean entirely on Jac's native retheme system (simpler, native, but not compatible with existing VS Code themes)? Worth a real decision once Phase 4/5 extensions exist — add to `architecture.md`'s open questions list. |
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

## What this settles vs. what it doesn't

Settled: no upstream feature area is unaccounted for anymore — everything above has a name, a
disposition, and (where relevant) a phase. Six real gaps came out of this pass that hadn't been
written down anywhere before (`authentication`+`encryption`, `bulkEdit`, `mergeEditor`, `themes`,
`localization`, `workspace`/multi-root) — folded into existing phases where cheap, left as open
questions where genuinely undecided (`themes`).

Not settled, and not meant to be yet: most "Tracked" rows above have a one-paragraph rationale, not
an architecture section like the Tier 1 items in
[`vscode-feature-gap-analysis.md`](vscode-feature-gap-analysis.md) got. That's the correct amount
of investment for something several phases away — full design work for a feature happens when its
phase is about to start, not years of roadmap in advance. Re-run this triage (or at least reread
it) before starting each new phase, the same instruction the gap-analysis doc already gives itself.
