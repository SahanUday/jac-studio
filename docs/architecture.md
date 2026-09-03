# Jac Studio — proposed architecture

Status: **proposal, v1** — 2026-08-22. This is the first pass at mapping VS Code's architecture
onto Jac's grain. It will change as Phase 0/1 work (see [`roadmap.md`](roadmap.md)) surfaces real
constraints; treat every "proposed" below as a hypothesis to be tested, not a commitment carved
in stone. Grounded in [`research/vscode-architecture.md`](research/vscode-architecture.md),
[`research/jac-capabilities.md`](research/jac-capabilities.md),
[`research/jac-examples-patterns.md`](research/jac-examples-patterns.md), and
[`vscode-feature-gap-analysis.md`](vscode-feature-gap-analysis.md) (a second, targeted pass
identifying upstream capabilities this document had not yet scoped — several of its findings are
folded in below), and [`vscode-complete-triage.md`](vscode-complete-triage.md) (every one of
upstream's 99 workbench feature areas, triaged to a disposition — the definitive answer to "is
anything upstream unaccounted for").

## Principles

1. **Jactastic over literal.** We are not transliterating VS Code's TypeScript into Jac
   syntax line-by-line. VS Code's patterns (constructor-injected services, event-driven
   contributions, a separate extension process talking over RPC) exist because TypeScript/
   Electron have no persistent graph, no inferred codespace placement, and no automatic
   client/server RPC. Jac already gives us the last three for free. We should use them, not
   rebuild DI and IPC by hand out of habit.
2. **Everything in Jac unless it's genuinely blocked — and every block gets logged, not
   silently worked around.** Where a component *can* be built natively in Jac, it should be,
   even where an existing JS library (Monaco, a syntax-highlighting engine) would be faster to
   integrate. Where it truly can't (see the open risks below), we track why in the
   [challenge tracker](challenge-tracking.md) and make a deliberate, documented call — not a
   silent shortcut.
3. **MVP, then widen.** Ship a single-pane editor before a workbench; a workbench before an
   extension system; trusted in-process extensions before a sandboxed marketplace; a working dev
   build before a signed cross-platform installer. See [`roadmap.md`](roadmap.md) for the actual
   sequencing — this document describes target-state shape, not build order.
4. **Desktop packaging is a late-stage concern.** Jac's webview-based desktop shell is a thin
   layer over the same client bundle the browser target uses (unlike Electron, there's no separate
   "desktop app" codebase to maintain in parallel) — so there's no cost to deferring it.

## "Rewrite, don't mirror" — principle 1, made concrete

Principle 1 isn't just a philosophical stance — it has already produced specific design decisions
throughout this document, listed together here so the pattern is visible as one consistent stance
rather than scattered individual calls:

- **Service registry**: the graph reachable from `root`, instead of a hand-built DI container
  (`IInstantiationService`/`createDecorator`) — see below.
- **Cross-boundary calls**: `root spawn SomeWalker(...)`, instead of a hand-maintained RPC
  protocol file (`extHost.protocol.ts`) — see IPC section below.
- **Terminal process execution**: a deny-by-default `shell` capability, instead of Electron's
  always-on OS access from the main process — a genuine security *improvement* over upstream, not
  just a different way to do the same thing.
- **Multi-root workspaces**: fall out of the existing `Workspace --Contains--> Folder` graph model
  for free (multiple `Folder` nodes under one `Workspace`), instead of a bespoke
  `.code-workspace` file format.
- **Settings Sync and Local History** (both currently open design spikes, not built): the native
  shape is visibly "the same root reached from two machines" / "retained prior graph states,"
  instead of upstream's bespoke sync protocol and revision-snapshot mechanism, respectively.
- **Chat/AI assistance**: `by llm()` and `sem` as the starting point (Tier 2.5 in the gap
  analysis, tracked as `2026-08-22-chat-subsystem-scale.md`), instead of porting upstream's
  442,661-line bolted-on chat subsystem — inline completions are tracked in the same family.
  **Sharpened 2026-08-31**: a small, named set of native tool integrations (GitHub Copilot,
  OpenCode, Claude Code) is now explicitly in scope alongside `by llm()`, not a substitute for it
  — see the new "AI coding tool integrations" section below.
- **Language intelligence (completion, hover, go-to-definition, rename, ...)**: a native LSP
  *client* built as core workbench infrastructure, talking to `jac lsp` — a real language server
  already shipped in jaclang core — over stdio, instead of waiting on a general third-party
  extension host to make a language extension pluggable. Decided 2026-08-31, see "Language
  intelligence" section below.

**This does not conflict with the [TS→Jac translator](translator-strategy.md) — the two apply to
different kinds of problem, and it's worth being precise about the boundary.** Everything above is
a case where VS Code's *solution shape* is a consequence of TypeScript/Electron's limitations (no
persistent graph, no inferred RPC, no native LLM calls, an untrusted-process boundary hand-built
because the language has no capability system) — Jac removes the limitation, so the shape should
change too. The translator, by contrast, is scoped only to problems whose solution shape is
dictated by the *problem itself*, not by the source language: a piece-table text buffer is an
O(log n) piece-table in any language, and reinventing that algorithm from scratch in the name of
"Jactastic" would just be re-deriving the same wheel, slower and with more bugs. Even there, the
translator targets idiomatic Jac (`obj`, not a transliterated `class`; Jac collection operations;
no DI wiring the algorithm never needed) rather than syntax-for-syntax transliteration — so it's
an application of the same principle at the algorithm level, not an exception to it.

### The actual decision procedure, applied per-feature at the start of its phase

Not a one-time upfront judgment call for all 158 triaged feature areas — applied lazily, to
whatever's in scope right as its phase begins (consistent with the MVP-first principle: design
when the work starts, not years ahead). Two questions, in order:

1. **Why is this complicated in VS Code — a TypeScript/Electron limitation, or the problem
   itself?** If VS Code had to build a workaround because the language/runtime forced it (no
   persistent graph → a hand-built DI container; no inferred cross-process calls → a hand-written
   RPC protocol; no capability system → an always-on-access terminal; no native LLM syntax → a
   442K-line bolted-on chat subsystem) → **redesign**, using whatever Jac primitive already
   answers the underlying need. If the difficulty is inherent to the problem in any language (text
   storage that supports fast edits, a diffing algorithm, offset/line math) → go to question 2.
2. **(Only for "inherent to the problem") Is it small, self-contained, and does upstream have
   tests to verify against?** Yes → **translate** it (the translator's own target-selection
   criteria in `translator-strategy.md`) — genuinely close to free once the workflow exists, since
   the algorithm doesn't need reinventing, only re-expressing idiomatically. No (large, tangled
   with DOM/Electron, untested) → don't mechanically translate it; read it for understanding, then
   **build fresh** — translating a mess just produces a Jac-flavored mess.

That third outcome, **build fresh**, is worth naming as its own bucket, distinct from both: neither
question resolves it "for free." The editor's rendering/interaction layer (cursor rendering,
selection, keyboard/IME handling — see Editor Core below) is the clearest example: not TS-shaped
(question 1 doesn't apply cleanly), not a clean translatable unit either (question 2 fails — it's
DOM-coupled, not a pure algorithm) and no existing Jac primitive already does it. So it's simply
new design work, informed by reading Monaco's approach rather than copying or translating it.

Summary: **redesign** when Jac already has (or trivially could build) a better answer to the same
underlying need; **translate** when it's pure, solved, testable math worth reusing as-is;
**build fresh** when neither applies.

## Layer mapping

| VS Code layer | Size (measured) | Jac Studio equivalent |
|---|---|---|
| `src/vs/base` | 154k lines | Ordinary Jac stdlib/utility modules — no special treatment needed; Jac's own base language (collections, async, `obj` helpers) already covers most of what `base` exists to provide in a language that has no such primitives. |
| `src/vs/platform` (DI + services) | 580k lines | **The root-graph-as-registry pattern** (below) instead of a hand-built DI container. |
| `src/vs/editor` (Monaco) | 279k lines | **The real `monaco-editor` npm package**, embedded via a thin Jac client wrapper (decided 2026-08-25, see Editor Core below) — not reimplemented. An earlier from-scratch port of Monaco's algorithms (piece tree, interval tree, prefix-sum) via the [translator](translator-strategy.md), plus a hand-built native rendering component, met its own Phase 1 exit criteria and is preserved at `internal/native-editor-archive/` for a possible future revival, not deleted. |
| `src/vs/workbench` (shell + contrib) | 1.42M lines | jac-cl components, overwhelmingly built on the **shadcn-in-Jac** primitive set (Sidebar, Resizable, Tabs, Command, ContextMenu, Tooltip, ScrollArea already exist) — see Workbench Shell below. This is the layer where Jac's built-in component library does the most work for us relative to upstream's line count. |
| Extension host (`workbench/api`, `workbench/services/extensions`) | — | No Jac equivalent exists today. Biggest open risk in the project — see Extension System below. |
| `src/vs/code` (Electron main) | 6k lines | `jac nacompile` native desktop host + OS webview — deferred to a late roadmap phase. |

## Service registry: the graph replaces the DI container

VS Code needs `IInstantiationService` + `createDecorator` because TypeScript objects have no
persistent identity and no built-in registry. Jac has one already: **the graph reachable from
`root` is the service registry.** A "service" (configuration, file-system access, the extension
registry, the command registry) is modeled as a `node`, created once and attached to `root` (or
`root.shared` for deployment-wide singletons), and reached by any walker or `def:pub` via a graph
query — `[root--][?:ConfigService][0]` — rather than injected through a constructor chain.

**Validated in Phase 0** (`internal/service-registry-spike/`, tracker entries
`2026-08-23-service-registry-query-cost.md` and `2026-08-23-service-cache-test-isolation.md`) —
with two caveats that change how the pattern must be implemented, not whether to use it. A real
three-service slice (`ConfigService` + `CommandRegistry` + `FileTreeService`, interacting through
the graph exactly as proposed) confirmed get-or-create idempotency and cross-service interaction
hold up. But a fresh `[root-->[?:Type]]` query measured **~600us/call** under `jac run` — real, not
hypothetical, and too slow to call on every access on a hot path like keystroke handling (a single
lookup alone eats ~4% of a 16ms/60fps frame budget; a real command dispatch chains several).

The fix, now a project-wide rule, not optional: **every service accessor resolves its node once
per `root` and caches the reference in a module-level `glob` keyed by `jid(root)`** —
`glob _cache: dict[str, ServiceType] = {}`, never a single bare `X | None = None`, and never a
bare `[root-->[?:Type]]` at the call site. The keying is load-bearing, not stylistic: `root` is
bound to whoever is calling, not a process-wide constant (a served app resolves a different `root`
per authenticated user). A single non-keyed cached value was tried first, shipped as "resolved,"
and then verifiably leaked one user's node into another user's request in a long-lived server
process — reproduced with two logged-in users via `JacTestClient` before being caught. Keying by
`jid(root)` fixes it: repeat reads within one user's session/request still hit the fast cached
path (~0.06us/call, indistinguishable from a plain attribute read), and different users never see
each other's cached instance. Unbounded growth of that dict (one entry per distinct root ever
seen) is a known, unaddressed gap — fine for now, worth an eviction strategy before any long-lived
production deployment.

Separately: this keyed cache does **not** by itself fix test isolation. `jac test` reuses a worker
process across multiple tests, and `jid(root)` turns out to be the *same* identity across
different tests in one worker even though each test's graph *content* is otherwise isolated —
verified directly, keying by root alone still leaked a value from one test into the next. Every
service module must additionally export a `_reset_<x>_cache_for_tests()` hook (clearing the whole
keyed dict), and every test exercising the accessor must call it. Two different problems, two
different fixes; neither substitutes for the other. See `internal/service-registry-spike/README.md` for the
full writeup and measured numbers.

**Correction (2026-08-28) — the rule above is incomplete for anything the accessor will *mutate*,
not just read.** "Caches the reference" was written assuming a cached node object stays valid to
write through indefinitely; a real Phase 3 restart test (`jac browse` against a genuine
`jac run --serve --dev` process kill + restart, not just a page reload) found that it doesn't. A
`has`-field mutation made through a node object that was cached from an *earlier, separate*
request is never durably committed — the mutation is visible to every read for the rest of that
process's life (the illusion that let this ship in `settings_service.jac`'s first version, verified
surviving a page reload), but the underlying row's `version` never advances, and a real restart
reverts to whatever was last committed before the cache started serving stale-but-plausible reads.
Confirmed narrow: edge creation *and* traversal reads through that same kind of cached object are
unaffected (verified separately, both survive a real restart) — only field mutation on a reused
object is broken. The fix, verified live: **cache the jid (a `dict[str, str]`), not the node, and
resolve via `jobj(cached_jid)` — the `jac-sv-persistence` guide's own canonical "UPDATE" pattern —
immediately before any mutation.** `jobj()` is documented O(1), so this keeps the original rule's
whole point (avoiding the ~600us/call traversal) while actually being correct; reads may keep using
the raw cached object (traversal-based reads are unaffected), or resolve via `jobj()` too for
uniformity — `settings_service.jac`, `session_service.jac`, `workspace_service.jac`, and
`command_registry.jac`'s `KeybindingOverrides` all now do the latter. See tracker entry
`2026-08-28-field-mutation-on-cached-node-not-persisted` for the full repro (including the exact
server-side log line that first pointed at the real mechanism, and the false leads chased before
finding it) and `docs/phases/phase-3-*.md` for which modules this affected.

**Second correction (2026-08-28) — edge *deletion* has an analogous gap "edge creation is
unaffected" above does not cover.** Found building the file-tree context menu's delete/rename
operations: `del` on an edge object (from `[edge node ->:Type:->]`/`<-:Type:<-]`) inside a `def:pub`
does not reliably take effect for a *later, separate* real HTTP request's traversal, even though
the identical code passes every `jac test` (which never crosses that real request/response commit
boundary at all). Confirmed live: deleting a file via the context menu removed it from disk
correctly, but the detached graph node kept reappearing in the next `list_children_by_path` call,
indefinitely, across a real `jac run --serve --dev` process. `get_or_create_workspace`'s own
root-switch edge cleanup (just above) was only ever verified for "the *new* root re-scans
correctly," never for "the *old* root's detached children stay gone if re-queried" — this finding
means that path may carry the same latent gap, simply never triggered in practice. **Workaround
shipped in `workspace_service.jac`'s `list_children_by_path`**: make the *read* path authoritative
against the real filesystem (`os.path.exists`) rather than trusting graph edge state for
correctness, the same stance already taken there for the pre-existing duplicate-node de-dup. See
tracker entry `2026-08-28-edge-deletion-not-committed-across-real-http-requests` (blocker severity —
this affects any future feature that needs to durably detach an edge and trust that on a later,
separate request, not just the file tree) and the sibling entry
`2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability` for a second, distinct
`del`-related surprise found in the same investigation (a plain application-level dict `del`, not a
graph operation at all, corrupting an unrelated node's edge reachability).

### Not every service needs to be a node

The spike above (and the rules just described) validated the pattern for services that are graph
nodes. But being a `node` at all is itself a choice, not the default every service must take —
only make something a node if at least one of these is actually true:

1. It needs to **survive a process restart** without hand-written save/load code (Jac's
   persistence-by-reachability gives this for free to anything reachable from `root`).
2. It needs to be **discoverable by other nodes via graph traversal/edges** (e.g. `Workspace
   --Contains--> Folder`).
3. It needs to **participate in the graph's permission model** (`:priv`, `grant`/`revoke`) for
   per-user access control.

If none of those apply, use a plain `obj`, created lazily and cached the same way —
`glob _cache: dict[str, T] = {}` keyed by `jid(root)` — but never attached to the graph at all.
This isn't a hypothetical alternative: `src/editor/document_service.jac`'s `DocumentBuffer` is
exactly this shape (an `obj`, not a `node`, cached in a `jid(root)`-keyed dict), arrived at after
an unrelated bug (a self-referential field structure crashing graph-persistence serialization —
see the tracker) forced the question, but it holds up on the merits independent of that bug: a
document buffer doesn't need to survive a restart independent of the file it mirrors on disk,
isn't traversed to from another node, and needs no permission scoping beyond what the `jid(root)`
key already gives it.

The payoff isn't just conceptual cleanliness — it's the ~600us/call raw graph-query cost measured
above. A cached `obj` never issues that query even once, not even the one-time per-root hit a
cached node still pays; a plain object construction is the entire cost. For a service with a real
persistence need (open tabs, file tree, cursor state — the Phase 3 candidates), that one-time
per-`root` cost is negligible in practice — jac-studio runs as a long-lived, single-user, locally
run process (`jac start`, or eventually the packaged desktop app), so the cost lands once at first
interaction after launch, not once per call. So: default new services to `obj` + keyed cache;
promote to `node` only when one of the three needs above is concretely present, not preemptively.

## Data model: the workspace is the graph

Files, folders, open editor groups, tabs, and cursor/selection state are **nodes and edges**, not
in-memory arrays owned by a "workbench model" object:

- `Workspace` (root-attached) `--Contains-->` `Folder` `--Contains-->` `File` — this already
  supports multiple top-level `Folder` nodes under one `Workspace` with no changes, i.e.
  multi-root workspaces (VS Code's `.code-workspace` equivalent) fall out of the data model for
  free; add UI for managing multiple roots whenever it's convenient, not as its own subsystem
  (see [`vscode-complete-triage.md`](vscode-complete-triage.md)'s `workspace`/`workspaces` row)
- `EditorGroup` `--Shows-->` `Tab` `--Displays-->` `File`, with `Tab` carrying `has cursor: ...`,
  `has scrollPosition: ...` etc. as plain fields
- `Extension` nodes attached to a per-user `root`, `--Contributes-->` `Command`/`View`/`Menu`
  nodes (the graph *is* the contribution registry — see below)
- Settings/keybindings as `obj`s attached via edges from `Workspace`/`root`, which gives us
  persistence-by-reachability for free: no settings-file serialization code to write or maintain.

This directly follows the pattern proven in littleX/day_planner (root-anchored per-user graphs,
`:priv` for isolation) and gets us multi-user/collaborative-editing groundwork essentially for
free later, since Jac's access-control primitives (`grant`/`revoke`/`root.shared`) already exist
for exactly this shape of problem — years before we'd need to build it by hand.

**Validated at scale before Phase 2** (`internal/workspace-graph-spike/`) — the `Workspace`/
`Folder`/`File` shape holds up structurally at real scale (2,974 real nodes scanned from the
`jaclang` compiler repo, every node reached exactly once, no duplicates), but eager
scan-and-traverse of the whole tree measured ~3 seconds combined at that scale — too slow to feel
instant on open. The file-tree feature this data model supports must load lazily, populating a
`Folder`'s children only when the UI expands it, not by eagerly walking the whole workspace up
front. See the spike's own README and tracker entry
`2026-08-24-workspace-graph-eager-traversal-too-slow-at-scale` for the full numbers.

## Workbench shell: shadcn-in-Jac primitives, not hand-rolled chrome

VS Code's workbench parts map almost directly onto existing Jac shadcn primitives:

| Workbench part | Jac primitive |
|---|---|
| Sidebar (Explorer view) | `Sidebar` |
| Activity bar (icon rail switching sidebar views) | No direct shadcn primitive — a small icon-strip component we build ourselves, since `Sidebar` is a container, not a view-*switcher*. Built 2026-08-28, Phase 3 (`src/workbench/activity_bar/activity_bar.jac`). |
| Title bar (Command Center search) | No direct shadcn primitive — hand-built chrome. Built 2026-08-28, Phase 3 (`src/workbench/title_bar/title_bar.jac`) — no window controls (web app, not a native desktop host yet) and no menu bar (separate, larger scope). |
| Editor groups (split panes) | `Resizable` / `ResizablePanel` / `ResizableHandle` |
| Tabs | `Tabs` |
| Command palette | `Command` |
| Right-click menus | `ContextMenu` |
| Status bar hints, hover info | `Tooltip` |
| File tree, output panels | `ScrollArea` (+ a tree component we likely build ourselves — not in the ~50-primitive shadcn set) |
| Toast notifications + notification center | No direct shadcn primitive equivalent to VS Code's notification center; shadcn's `Sonner`/toast pattern covers the toast half. Not yet built. |

Because the primitive layer already exists for most of this, the workbench-shell phase of the
roadmap is realistically a composition/layout effort, not a from-scratch UI-toolkit-building effort
for the *majority* of parts — but the activity bar, title bar, and notifications rows above are a
real exception, found only by checking VS Code's actual `workbench/browser/parts/*` source
directly (2026-08-28) rather than assuming shadcn already covered them; see
`vscode-complete-triage.md`'s new "workbench/browser/parts" section and `roadmap.md`'s Phase 3/4
bullets for where these land.

Following the self-registering **contribution model** VS Code uses (rather than one monolithic
layout file), each workbench feature (file explorer, search, settings UI, later: debug/terminal)
should be its own set of Jac modules that attach `Command`/`View`/`Menu` nodes to the registry
graph on load — the direct Jac analog of VS Code's `workbench/contrib/*` self-registration, and
the mechanism that lets `workbench` scale to 4,000 files without a central switchboard.

### Visual identity: match VS Code's default look, natively (decided 2026-08-28)

**Decided**: jac-studio should look like VS Code out of the box — the same default experience a
user gets opening [vscode.dev](https://vscode.dev) with zero extensions installed (Dark+/Light+
palette, Codicons-style iconography, the same chrome proportions/spacing) — not shadcn's own
default aesthetic. This is separate from, and does not require resolving, the installable-theme-
extension question below; it's about the *baseline* look every jac-studio user sees, regardless of
whether third-party themes are ever supported.

Get there the Jactastic way, consistent with principle 1: reproduce VS Code's default color/type
tokens as `jac retheme`'s own OKLCH CSS variables (configured via `jac.toml`'s `[jac-shadcn]`
table — currently `style = "nova"`, `baseColor = "neutral"`, `theme = "neutral"`, shadcn's stock
look, not VS Code's), not by importing VS Code's actual theme JSON format or building a
compatibility shim for it. Concretely:

- Derive an OKLCH token set from VS Code's default Dark+/Light+ colors and drive `jac retheme`
  with it, the same mechanism already styling every shadcn-in-Jac primitive — no new theming
  machinery needed, just the right token values.
- Replace the icon set. `jac.toml` currently pulls `@hugeicons/react` (see `editor_tabs.jac`'s
  split-editor icon) — a fine general-purpose icon set, but not what makes a workbench read as
  VS Code. Move to Codicons (or a Codicons-equivalent) for anything standing in for a VS Code chrome
  element (file-tree/tab icons, activity bar, status bar).
- Scope this against the actual chrome that exists so far: sidebar, tabs, resizable editor groups,
  command palette, status bar, terminal (all shipped in Phase 2) — not a hypothetical full surface.

This does not change the Editor core section below — Monaco already ships its own
`vs-dark`/`vs-light` themes matching VS Code's editor colors; the work here is the *workbench
chrome around* Monaco, which Monaco has no opinion on.

**CORRECTION (2026-08-28): "Dark+/Light+" is not actually VS Code's current default — "Dark 2026"/
"Light 2026" is.** Found by checking the live `microsoft/vscode` source directly rather than
assuming, the same discipline the "workbench/browser/parts" gap above was found with:
`ThemeSettingDefaults.COLOR_THEME_DARK`/`COLOR_THEME_LIGHT` in
`src/vs/workbench/services/themes/common/workbenchThemeService.ts` resolve to `'Dark 2026'`/
`'Light 2026'`, not `'Dark+'`/`'Light+'` — VS Code shipped a new default theme pair at some release
before this document's original 2026-08-28 decision was written, and that decision's "Dark+/Light+"
framing was simply wrong, not a deliberate choice. The two are materially different, not a minor
palette tweak: "Dark 2026" drops the classic bright-blue status bar entirely
(`statusBar.background: #191A1B`, the same flat near-black as every other chrome surface — blue
(`#3994BC`) only appears for the debugging-session state now), uses a muted teal-blue accent
(`#297AA0`) instead of the classic vivid blue (`#007acc`), and leans on translucent white/black
overlays for hover/selection states (`list.hoverBackground: #FFFFFF14`) rather than flat swapped
colors. Values pulled directly from `extensions/theme-defaults/themes/2026-{dark,light}.json` in
the same repo. `styles/global.css` and the workbench components' literal chrome colors
(`status_bar.jac`, `editor_tabs.jac`, `file_tree.jac`, `workbench.jac`) now match this real
default, hand-edited in per `jac retheme`'s own documented escape hatch for one-off custom colors
(`jac retheme` was still run first, with `--baseColor zinc --theme sky --radius small` as the
closest preset scaffold, since its OKLCH inputs are presets only, not arbitrary custom values).
Icon set swapped to the actual `@vscode/codicons` package (the real font VS Code itself ships, not
just "Codicons-style") — `@hugeicons/react`/`@hugeicons/core-free-icons` removed entirely, since
the only usage was the split-editor icon.

## Editor core: embed the real thing, don't reimplement it

**Status (2026-08-25): the editor engine is the real `monaco-editor` npm package**, embedded via a
thin Jac client wrapper (`src/editor/client/monaco_editor.jac`), not a from-scratch Jac
text-editing core. This reverses Phase 1's "continue native" call — see
`2026-08-25-editor-core-decision-reversed-to-monaco` for the full record, and read it before
assuming the section below was always the plan.

**Why the reversal, and why it isn't a verdict against Phase 1's work**: Phase 1's from-scratch
attempt (porting Monaco's piece-tree text buffer, interval tree, and prefix-sum computer via the
[translator](translator-strategy.md), plus a hand-built native rendering component) genuinely
worked — it met its own exit criteria, round-tripped real keyboard input correctly, and is a solid
answer to "can Jac build a real text-editing widget." The reversal is a *reuse-over-reinvention*
call, not a "native failed" call: once `monaco-editor` is available as an ordinary npm dependency
(jac-cl's npm interop already supports this), maintaining a second, competing text-editing engine
in parallel has no real payoff for v1 — Monaco already owns a battle-tested text model,
cursor/selection/IME handling, line-by-line virtualized rendering, undo/redo, and (unlike the
from-scratch path) a bundled tokenizer/language-service layer that makes Phase 3's syntax
highlighting and diff-editor bullets largely free instead of new work (see `roadmap.md`'s Phase 3
section).

**The from-scratch engine is archived, not deleted**, at `internal/native-editor-archive/`
(`git mv`'d with history intact, README explains what's there and what a revival would need to
touch) — per the explicit call that a future need (a licensing constraint, wanting full control
over the text engine, a desktop/native-JS story that doesn't fit Monaco well) could bring native
back. Nothing about the reversal invalidates that work; it just isn't v1's path.

**What jac-studio's own code owns now, with Monaco doing the rest**:

1. **A thin mounting/lifecycle wrapper** (`src/editor/client/monaco_editor.jac`) — Monaco's API is
   imperative (`monaco.editor.create(domNode, options)`), not JSX-declarative, so this component
   holds a DOM ref, creates/disposes a Monaco instance on mount/unmount, and re-syncs Monaco's
   model when its `path` prop changes. This is the first Jac `app` component to do raw DOM-ref +
   imperative third-party-library mounting — the vendored shadcn primitives use `useEffect` too
   (`components/ui/sidebar.jac`'s `useIsMobile`), but always as a plain function, never inside the
   `has`/`impl` component idiom; validate this pattern carefully rather than assuming it composes
   the same way.
2. **Load/save at the document boundary only.** `document_service.jac` reads a file's content into
   Monaco once on open and writes it back to disk on save — Monaco owns the live edit/undo/cursor
   state entirely client-side in between. No per-keystroke RPC round-trip: unlike the archived
   native path, there's no ported buffer for the server to keep in sync with on every keystroke.
3. **Workbench-level wiring stays jac-studio's job**, unchanged in shape: which files are open, in
   what tabs, in which editor group (`editor_tabs.jac`/`workbench.jac`) is still ordinary Jac
   client state — Monaco owns *one open document's* editing surface, not the surrounding shell.

**A load-bearing detail found in Phase 2, not obvious from Monaco's own docs alone**:
`@monaco-editor/react`'s `path` prop shares one underlying Monaco text model across every `<Editor>`
instance mounted with the same path (`monaco.editor.getModel(uri) || createModel(...)`, confirmed
by reading the package's own source, not just its docs) — which is exactly what makes Phase 2's
editor-group splitting work at all, since two groups showing the same file need to render the same
live buffer, not two independent copies. But the package's *default* unmount behavior disposes that
shared model (`keepCurrentModel` defaults to `false`, assuming one editor owns one model 1:1), so
without `keepCurrentModel={True}` set explicitly, closing the tab in either group destroys the model
the other group's still-mounted editor is rendering — reproduced live, not a hypothetical, see
`docs/phases/phase-2-workbench-shell.md`. `monaco_editor.jac` sets `keepCurrentModel={True}` for
exactly this reason, with the trade-off that a closed tab's model is never explicitly disposed (an
accepted leak, same trade-off already made for orphaned graph nodes in `workspace_service.jac` — a
local, single-user dev tool doesn't need active memory reclamation the way a long-running service
would). **Confirmed for Phase 3's diff-editor bullet (2026-08-28)**: `@monaco-editor/react`'s
`DiffEditor` (`src/editor/client/monaco_diff_editor.jac`) accepts `originalModelPath`/
`modifiedModelPath` and, when a diffed file is *also* open in a regular tab, reuses that file's
existing shared model (the same `getModel(uri) || createModel(...)` sharing described above)
rather than creating an independent copy. But the *disposal-avoidance* fix does **not** carry over
by name: `DiffEditor` has no `keepCurrentModel` prop at all — passing it (the plain `Editor`'s
prop) compiles and runs with zero warning, silently ignored, and closing a diff tab disposed the
model a regular tab was still rendering (`Uncaught Error: TextModel got disposed before
DiffEditorWidget model got reset`, reproduced live before the fix, not assumed). Reading the
package's own source turned up the real, differently-named pair —
`keepCurrentOriginalModel`/`keepCurrentModifiedModel`, both needed, both default `false` — which
`monaco_diff_editor.jac` now sets, verified against the same repro.

**CORRECTION (2026-08-28, Phase 3's syntax-highlighting-confirmation bullet)**: the "free per-side
language detection" claimed just above does **not** hold in general — only checked against a diff
where one side happened to already have a model from an open regular tab. Verified cold (a diff of
two files neither open elsewhere): `@monaco-editor/react`'s `DiffEditor` falls back to a **literal
language string `"text"`** for any side it has to create a model for itself (its internal
`modifiedLanguage||language||"text"`, not the empty-string auto-detect fallback the plain `Editor`
uses in the same spot), so a cold-diffed file's side renders as `plaintext` regardless of its
extension. `monaco_diff_editor.jac`'s `handle_before_mount` now pre-creates both sides' models
itself with the empty-string language spelling before `DiffEditor`'s own resolution runs, so its
internal `getModel(uri)` check finds the correctly-tagged model instead. See that module's
docstring for the full finding, including file:line citations into `@monaco-editor/react`'s source.

## Syntax highlighting and the minimap: confirmed, not just assumed (2026-08-28)

Phase 3's syntax-highlighting bullet was framed as "largely free via `monaco-editor`'s own bundled
tokenizer/language services" — verified live (`jac browse`, `monaco.editor.colorize`,
`monaco.editor.tokenize`) rather than taken on faith, and the claim holds for the languages Monaco
actually ships: Python, JavaScript, CSS, JSON, and Markdown all produced real multi-class token
output, not just a language-id label with no visible effect.

**But `monaco.languages.getLanguages()` does not include `jac` (or `toml`)** — every `.jac` file in
this project, including this file's own source, resolved to `plaintext` before this fix, since
Monaco has no idea what a `.jac` extension is. For a "VS Code reimplemented in Jac" editor, this
would have left the flagship syntax-highlighting feature invisible for the exact files a
jac-studio user opens most. **Resolution**: `src/editor/client/jac_language.jac` registers a real,
intentionally-scoped Monarch tokenizer for Jac (`monaco.languages.register`/
`setMonarchTokensProvider`/`setLanguageConfiguration`, associated with the `.jac` extension),
covering the constructs `jac-core-cheatsheet` and this project's own files actually use — keywords,
`#` comments, single/double/triple-quoted strings, backtick-escaped identifiers, `->`/`::` — not a
claim of full grammar fidelity. Registered via `@monaco-editor/react`'s `beforeMount` (confirmed
from the package's own source to run before model creation), guarded by a module-level flag so
repeated mounts don't re-register. `.toml` is left as `plaintext` — a single config file, not this
project's own dominant language, isn't worth the same investment.

**Minimap: decided on, not left off from an unrevisited Phase 2 default.** `monaco_editor.jac` now
sets `"minimap": {"enabled": True}`, matching VS Code's own default. The diff editor's `DiffEditor`
does **not** get the same flip: read `monaco-editor`'s own source
(`diffEditor/components/diffEditorEditors.js`'s `_adjustOptionsForSubEditor`) and confirmed it
hardcodes `minimap.enabled = false` for both diff panes unconditionally, regardless of the
`options` passed in — real VS Code's diff view has no per-pane minimap either, so this is
deliberate upstream design, not a gap to work around.

**Decided in Phase 1: not taken.** The from-scratch widget (step 2 above) is fast/far enough
along with real data in hand — see the resolved open question below and
`docs/phases/phase-1-editor-core.md`. This fallback stays documented here as the path considered
and set aside, not deleted, in case a later phase's performance data reopens the question.

## Extension system: the biggest open risk, phased trust model

VS Code's hard guarantee — extension code never runs in the workbench's own process/thread — has
**no ready-made Jac equivalent**. This is confirmed independently by both the docs research and
the examples research: no skill file and no example app demonstrates a plugin sandbox. Proposed
phasing, deliberately conservative:

- **Phase A (trusted, in-process)**: "extensions" are just more Jac walkers/nodes defined
  alongside the app's own code and loaded at build time — no isolation, no marketplace, no
  security boundary. Enough to prove the contribution-registry pattern (commands, views, menus)
  end to end without solving sandboxing first.
- **Phase B (declared-manifest, still trusted)**: extensions become separate Jac packages with a
  manifest (contributes/activation-events, mirroring `package.json`'s contract) loaded dynamically
  at runtime, still fully trusted — proves dynamic loading without solving isolation.
- **Phase C (sandboxed, untrusted)**: the real, hard problem — likely built on Jac's native+WASM
  compilation path (`jac-native-wasm.md`), compiling extension code to WASM and building a
  capability/permission model around it from scratch, since Jac provides the WASM *target* but not
  a plugin *sandbox*. This is R&D, not integration work, and should be scoped as its own
  multi-milestone research track, not a line item inside a later phase.

Do not attempt Phase C before Phases A and B have validated the contribution-registry and
extension-API-surface design against real usage — sandboxing a design that later turns out wrong
would waste the hardest work in the project.

**Re-prioritized 2026-08-31, per explicit project-sponsor direction — this reorders the milestone
target, not the technical phasing above, which stays correct as written.** The near-term goal is a
**complete, VS-Code-feature-equivalent editor built on native/built-in Jac functionality alone**
("jac-coder" as a full-featured product in its own right) — not a marketplace, and not compatibility
with the arbitrary third-party `.vsix` ecosystem. Concretely, this changes what counts as "done" for
the next several phases, without changing the phased trust model itself:

- **Phase A is the whole near-term target, not a stepping stone to rush past.** Every "built-in
  VS Code feature" this document scopes — search, SCM/git, tasks/problems, language intelligence,
  a debugger, notifications, output — should be built as trusted, in-process, build-time-loaded Jac
  modules (Phase A's own definition), reaching real VS-Code feature parity **without ever needing
  Phase B or C to ship.** This was already implicit in Phase A's own description; stating it
  explicitly here because earlier roadmap drafts filed some of these features under "needs the
  extension system" by analogy to how upstream happens to package them, not because they actually
  require dynamic loading or a trust boundary — see "Language intelligence" below for the clearest
  case of this correction.
- **Phase B (dynamic loading) and Phase C (sandboxing) are explicitly a *later*, separate track,
  pursued once the Phase-A-built full-featured editor exists** — not abandoned, not "maybe never,"
  just deliberately sequenced after the native-feature-parity milestone rather than interleaved
  with it. A user should be able to get a complete VS-Code-equivalent experience before jac-studio
  can load a single third-party extension.
- **The "investigate loading the real published `jaseci-labs.jaclang-extension` `.vsix`
  unmodified" research question (below, under Open questions) is downgraded from a Phase-4
  planning item to explicitly deferred, non-blocking research.** It's still worth eventually
  answering — it's the concrete test case for how much `vscode`-API compatibility to target once
  Phase B design starts — but nothing in the native-feature-parity milestone depends on its answer,
  because the same extension's actual value (real Jac language intelligence) is reachable directly
  today: see "Language intelligence" below.
- **A small, explicitly-named set of native AI coding-tool integrations is in scope now**, as its
  own deliverable distinct from both "port upstream's chat subsystem" (still excluded) and "wait
  for a general extension system to make arbitrary chat extensions pluggable" (no longer the
  gating assumption). See "AI coding tool integrations" below.

## IPC / cross-boundary calls

VS Code's extension-host/main-thread RPC split, and its general `IChannel`/`IServerChannel`
transport abstraction, both exist to solve a problem Jac's inferred codespaces already solve:
calling from client code to server code is `root spawn SomeWalker(...)`, a plain function call
that the compiler turns into RPC across whatever codespace boundary applies — no protocol file to
maintain by hand (VS Code's `extHost.protocol.ts` has no counterpart we need to write). This
collapses an entire layer of VS Code's architecture into "just call the walker" for the
client↔server boundary. It does **not** solve the workbench↔extension-host boundary from
Extension System Phase C above — that boundary is a trust boundary, not a process/codespace
boundary, and Jac's RPC inference doesn't imply sandboxing.

## Desktop packaging

Deferred by design (principle 4). When we get there: `jac nacompile` + the OS-native-webview shell
described in `jac-desktop-app.md`, plus the per-OS installer/signing pipeline described in
[`research/vscodium-packaging.md`](research/vscodium-packaging.md) — expect to build that pipeline
ourselves; Jac doesn't ship one yet (tracked gap, upstream issue #6436).

## Process execution: terminal, tasks, and debugging

Worth separating explicitly, because the two halves of "run my code" in VS Code sit on opposite
sides of the extension boundary, and the Jac mapping differs accordingly.

**The integrated terminal is core, not an extension**, in both VS Code and this proposal. VS Code
just spawns a real OS shell process on a pseudo-terminal from the main process and streams
stdin/stdout/stderr to the renderer over IPC — no language knowledge, no extension involved.
Proposed Jac equivalent:

- Terminal UI is an ordinary workbench-core client component. Jac has no native terminal-emulator
  primitive, so this is one of the few UI pieces reached via npm interop rather than shadcn (e.g.
  `import from "xterm" {...}`), not a from-scratch build.
- A command typed into it is sent to the backend the same way everything else is —
  `root spawn RunInTerminal(cmd)`, ordinary client→server RPC, no special mechanism.
- The walker spawns the actual OS process. In desktop mode this runs in the same in-process
  embedded CPython host (`jac-desktop-app.md`) via Python's own `subprocess`, but gated behind the
  `@jac/desktop` `shell` capability — **deny-by-default**, must be explicitly granted in
  `jac.toml`. This is a genuine improvement on VS Code's own model: Electron's main process has
  unrestricted OS access by default, where Jac forces the capability to be an explicit, visible
  grant. Output streams back incrementally via the SSE/`Generator` pattern already used for
  LLM-token streaming (`jac-sv-streaming.md`) — the same mechanism, a different payload.
- **This subsystem belongs in the Phase 2 workbench-shell MVP** (updated in `roadmap.md`), not a
  later extension phase — you should be able to open a terminal and run something in the earliest
  usable build, same as VS Code.

**"Run"/"Debug" (the Run button, F5, breakpoints) is genuinely extension territory** in VS Code,
and stays that way here — but the two halves of it are very different sizes of problem:

- *Run without debugging* is nearly free once the terminal above exists: a language extension
  (Phase 4, or Phase 6 for a third-party one) contributes a command that knows how to construct
  the right shell invocation for a file type (`python foo.py`, `cargo run`, ...) and hands it to
  the same `RunInTerminal` walker. No new mechanism needed.
- *Real debugging* — breakpoints, stepping, call stack, variable inspection — is a gap this
  document had not previously scoped. VS Code's generic Debug Adapter Protocol (DAP) client, and
  the convention of extensions plugging in a per-language debug adapter process that speaks DAP,
  is a substantial piece of core infrastructure (`src/vs/workbench/contrib/debug/`) with **no Jac
  precedent to lean on** — no skill file, no example app addresses anything like it. Proposed
  placement: design a DAP-compatible client as its own workbench-core subsystem alongside Phase
  4/5 (extensions can *plug into* it the same way they do in VS Code), but treat it as its own
  scoped design effort rather than assuming it falls out of the general extension-contribution
  model — it won't. Track the design as its own doc once Phase 4 begins.

**A security question this raises that desktop mode sidesteps but a hosted/browser deployment
would not**: the `shell` capability is safe to grant in desktop mode because the process it spawns
runs on the user's own machine, under their own OS permissions — same trust level as them opening
their own terminal. A server-hosted, multi-tenant deployment (not on the current roadmap, but not
ruled out either) would need real sandboxing of that shell execution — container-per-session or
similar — which VS Code's own hosted offerings (Codespaces, github.dev) solve with exactly that
kind of isolation. Not a blocker for anything currently planned; noted so it isn't rediscovered
as a surprise if a hosted mode is ever pursued.

## Language intelligence: IntelliSense is not syntax highlighting

Worth stating plainly, since earlier drafts of this document conflated the two: **syntax
highlighting** (coloring tokens) and **language intelligence** (autocomplete, hover docs,
go-to-definition, find-references, rename, code actions, signature help) are almost entirely
separate subsystems in VS Code, and only the first was scoped in Phase 3 originally. The second is
what actually makes an editor useful for real work, and upstream implements it as a large,
well-defined provider API (`registerCompletionItemProvider`, `registerHoverProvider`,
`registerDefinitionProvider`, `registerCodeActionsProvider`, `registerRenameProvider`, and ~40
more in `vscode.d.ts`) that extensions implement — usually by bridging to a real **Language Server
Protocol** server process, not by the workbench having built-in per-language knowledge.

**Resolved 2026-08-31 — the "shared open question with the DAP client" below used to read "is
there a usable LSP client library reachable via Jac's interop, or does this need building from the
wire protocol up?" That question undersold what's already available and doesn't need answering by
research: jaclang itself ships a real, working LSP server.** `jac lsp` is a first-party CLI command
(`jaclang/cli/commands/tools.jac`, `handler_name=ct_name(lsp)`) that starts
`jaclang.lsp.server.server.run_lang_server()` — a genuine LSP server built on jaclang's own vendored
`pygls`/`lsprotocol`, already implementing `completion`, `hover`, `definition`, `references`,
`rename`, `document_symbol`, `semantic_tokens_full`, and `formatting` against real Jac source (not a
stub). This is the same server the published `jaseci-labs.jaclang-extension` VS Code extension
already wraps — the extension is just a thin VS Code-side LSP client plus a bundled TextMate
grammar; the actual language intelligence lives in `jac lsp` itself, independent of VS Code
entirely.

This changes the proposed shape materially — it's no longer "wait for the extension system,
because upstream implements this via extensions":

- **A native LSP client is core workbench infrastructure, built directly, not extension-contributed
  — the single highest-value "VS Code full-featured" capability for jac-studio's own dominant file
  type.** Spawn `jac lsp` as a subprocess the same way the terminal work already spawns any other
  process (`root spawn`, gated by the same `shell`-capability mechanism already scoped for Phase 2),
  and speak LSP's JSON-RPC-over-stdio wire format to it from a generic client module. No `vscode`-API
  shim, no `.vsix` loading, no extension host needed to get real Jac completion/hover/definition/
  references/rename working end to end. The `jaseci-labs.jaclang-extension` `.vsix` was previously
  scoped in Phase 4 as a compatibility-research question — that question is now explicitly
  **deferred, non-blocking** (see the Extension System section above); getting the underlying
  language intelligence into jac-studio does not wait on it.
- **The editor-side consumption layer** (rendering a completion popup, a hover card, a peek view,
  applying a rename) is workbench-core UI work against a generic provider interface, same as before
  — but now it has one concrete, already-working backend (`jac lsp`) to build and verify against
  immediately, rather than being blocked on "some future extension registers a provider." Design the
  interface generically enough that a second language server (e.g. `pyright` for Python files opened
  in a Jac project) is a second client instance, not a rewrite — but ship the Jac case first, since
  it's the dominant file type and the server already exists.
- This cluster isn't just "show the results" — a rename provider is useless without something to
  actually *apply* a multi-file edit, and a call-hierarchy/outline panel is just workbench UI over
  the same provider data as the completion popup and hover card. Bulk-edit application and the
  outline/call-hierarchy/breadcrumbs views belong in this same effort, not as separate features
  discovered later (see [`vscode-complete-triage.md`](vscode-complete-triage.md)).
- The Debug Adapter Protocol client is the same category of problem for the same reason: a debug
  adapter is just another subprocess speaking a JSON wire protocol, not something that needs a
  general extension host either. See Process Execution above and `roadmap.md` for both landing in
  the same native-infrastructure phase as the LSP client, ahead of Phase B/C extension work.

## AI coding tool integrations

**Added 2026-08-31, per explicit project-sponsor direction.** Upstream's chat/agent subsystem
(`workbench/contrib/chat`, 442,661 lines — see the gap analysis's Tier 2.5) stays excluded as a
port target; that call doesn't change. What's now explicitly in scope, as its own deliverable, is a
**small, named set of native integrations with existing external coding-assistant tools**, decided
deliberately rather than left as an indefinitely-deferred "revisit with `by llm()`" note:

- **GitHub Copilot** — real-world precedent for the mechanism: even inside VS Code, Copilot's own
  inline-completion path runs a bundled `copilot-language-server` as a subprocess speaking a
  JSON-RPC protocol closely related to LSP, not primarily through the proposed chat-extension APIs.
  The realistic integration shape for jac-studio is therefore the same subprocess/JSON-RPC pattern
  already used for `jac lsp` and the terminal, not a `vscode`-chat-API shim.
- **OpenCode** and **Claude Code** — both are CLI-first agentic coding tools with a documented
  SDK/subprocess-driven integration story (the same shape this very project's own tooling uses).
  Realistic integration shape: drive the tool's CLI/SDK as a spawned, capability-gated process
  (again, the terminal's own mechanism), streaming output back via the SSE/`Generator` pattern
  already used for LLM-token streaming (`jac-sv-streaming.md`).
- **`by llm()`/`sem` stay the native fallback and first-class citizen**, not superseded by these —
  for anything jac-studio wants to build itself (inline suggestions, a native chat panel) without
  depending on an external tool's availability or licensing.
- **Not in scope now**: a generic mechanism for *arbitrary* third-party chat/agent extensions to
  plug in — that would require the same extension-host trust-boundary work as Phase B/C, deferred
  for the same reason. This is a short, named list of integrations, not a platform.
- No architecture spike has been done yet on any of the three integrations individually — each
  needs its own small scoping pass (auth/licensing model, exact subprocess/SDK surface, what UI
  surface it needs) before implementation starts. Track that scoping as its own doc once the
  relevant phase begins, the same discipline already applied to the DAP client.

See [`vscode-feature-gap-analysis.md`](vscode-feature-gap-analysis.md) for the full inventory this
was drawn from, including several Tier 2/3 items (source control, tasks/problem-matchers, the
keybinding context-evaluation system, and a genuinely surprising finding — VS Code's chat/agent
subsystem is now larger than its entire editor core) that are tracked there rather than folded
into every section of this document.

### Reframed 2026-09-03: UI/UX patterns and native-Jac options, not just three subprocess clients

**The first integration (Claude Code) is done** — `claude_code_client.jac` + `claude_code_launcher.py`
+ `ai_chat.jac`'s sidebar panel, shipped and live-verified (PR #69). That confirmed the core
mechanism above works end to end: subprocess-only (never importing `claude_agent_sdk` into `.jac`
code — see tracker entry `2026-09-02-python-interop-import-explodes-compiler-on-large-dependency-closure`
for why that's load-bearing, not stylistic), gated behind `[terminal] enabled`, real streaming, real
multi-turn continuity. What's reframed here is the *ambition* for the rest of this phase, prompted
by two research passes: a real `microsoft/vscode` checkout's actual Copilot Chat source (now merged
in-tree, not a separate closed extension — see
[`research/vscode-copilot-architecture.md`](research/vscode-copilot-architecture.md)), and jaseci's
own native agentic capabilities (see
[`research/jac-native-agent-capabilities.md`](research/jac-native-agent-capabilities.md)). Read both
in full before touching this area again; only the conclusions are summarized here.

**Finding that reframes the plan**: Copilot's own "Fix"/"Explain"/"Review" quick-fix menu, inline
chat (Ctrl+I), and inline completions all turn out to be built on generic, backend-agnostic VS
Code/Monaco APIs (`CodeActionProvider`, a `ZoneWidget`, `InlineCompletionItemProvider`) — none of
them are Copilot-specific mechanisms. Since jac-studio embeds real Monaco, every one of these APIs
is already reachable, and every one of them ultimately just constructs a prompt and hands it to a
generic "start a chat turn" entry point — exactly the shape `start_chat_turn` already is. This means
building richer AI UX is not "build three more integrations," it's "build a few new *UI entry
points* against the *same* provider interface already in place":

1. **AI code actions — done (2026-09-04).** The lightbulb "Fix"/"Explain"/"Modify" menu, built as
   a new Monaco `CodeActionProvider` (`ai_code_action_provider.jac`), registered for `"*"` (every
   language, the same call `git_conflict_codelens_provider.jac` already made for the identical
   reason — explaining or fixing code is just as useful outside `.jac` files, unlike the
   LSP-backed providers, which are genuinely jac-specific). "Fix" appears only when the range has
   real diagnostics (`context.markers`); "Explain"/"Modify" appear on any non-empty selection.
   Routes through the *already-shipped* `AIChatApp` sidebar, not a new UI surface or backend call —
   `onAskAI(promptText, autoSend)` threads down the same `workbench.jac` → `editor_tabs.jac` →
   `monaco_editor.jac` chain `onOpenLocation`/`onOpenCommandPalette` already use, switches to the
   Claude Code view, and hands `AIChatApp` a prompt via a `pendingPrompt`/`pendingNonce` prop pair
   it picks up with `useEffect`. "Fix"/"Explain" auto-send (self-contained requests); "Modify..."
   only prefills the box, matching upstream's own `autoSend: true/false` distinction on
   `editorChat.start(...)` (confirmed in the research doc's reading of `inlineChatCodeActions.ts`).
   **Live-verified end to end** (`jac browse`, real credentials, screenshots at each step): a real
   text selection produced the real Monaco Quick Fix menu with "Explain with Claude Code"/"Ask
   Claude Code to modify this..."; selecting Explain switched to the sidebar, sent the exact
   constructed prompt, and returned a real answer (including a real tool-approval card from item 4
   along the way, confirming the two features compose correctly); selecting Modify prefilled the
   box without sending; a synthetic diagnostic marker (standing in for a real `jac lsp` one — see
   the PR for why) made "Fix with Claude Code" appear and send the diagnostic-plus-code prompt
   correctly.
2. **Inline chat — done (2026-09-04).** A `Ctrl+I` popover (`inline_chat_widget.jac`) for targeted
   edits without leaving the editor, anchored at the cursor/selection via a real Monaco content
   widget (`editor.addContentWidget`) — a deliberate, documented scope cut from upstream's actual
   `ZoneWidget` (real VS Code's own internal contrib class, confirmed **not** part of the public
   `monaco-editor` npm package's exported API surface this project embeds), so it can overlap
   nearby lines rather than pushing them apart. Total backend reuse: makes its own direct
   `start_chat_turn` call — the identical stream `ai_chat.jac`'s sidebar already uses — as a fully
   independent session (closing the popover ends that context; no shared state with the sidebar).
   Tool approval is handled inline too, reusing `AiToolDiffPreview`/`approve_tool_call` rather than
   a second approval UI, since this popover's own `tool_approval_request` events arrive on a
   separate SSE stream the sidebar would never see. **React content reaches Monaco's own
   externally-owned DOM node via `ReactDOM.createPortal`** — a genuinely new integration pattern in
   this project (every other Monaco-facing provider goes the opposite direction), verified live
   before being relied on.

   **A real, previously-undiscovered Monaco limitation surfaced while wiring this, and it turned
   out to affect the pre-existing `Ctrl+S` too.** With more than one tab open (every open tab keeps
   its editor mounted, per `keepCurrentModel`), each `MonacoEditorApp` instance's own
   `editor.addCommand(chord, handler)` does not scope that keybinding to its own instance —
   confirmed live with an isolated minimal test, independent of this project's code, that only the
   *last-registered* handler for a chord ever fires, regardless of which editor genuinely has
   focus. Passing `"editorTextFocus"` as the standard context argument (the correct fix in a real
   VS Code workbench) was tried and confirmed **not** to fix it in this standalone embedding.
   Concretely, before the fix: focusing and editing `broken.jac`, then pressing `Ctrl+S`, could
   silently save `README.md`'s content instead — a real, previously-unnoticed correctness bug, not
   hypothetical. **Fixed** by no longer trusting Monaco's own per-instance routing at all: a
   module-level registry (`_focused_editor_handlers`, keyed by file path) holds every mounted
   instance's own save/toggle callbacks; `Ctrl+S`/`Ctrl+I` are registered exactly once, globally,
   and the shared handler finds the actually-focused editor dynamically
   (`monaco.editor.getEditors().find(hasTextFocus)`) before dispatching. Verified against the exact
   repro: two tabs open, focused `broken.jac`, `Ctrl+S` now correctly saves `broken.jac`. See
   tracker entry `2026-09-04-monaco-addcommand-does-not-scope-per-standalone-editor-instance` for
   the full investigation. **Live-verified end to end** (`jac browse`, real credentials,
   screenshots): `Ctrl+I` opened a correctly-positioned popover; a real turn streamed a real
   response, including a real inline tool-approval card that resolved correctly and let the
   response continue streaming afterward.
3. **Richer agent-session visualization — done (2026-09-04).** The old plain `"[Using X...]"`
   text marker spliced into the running response bubble replaced with a real structured step card
   per tool call — name, pretty-printed input, a status icon (running/done/error), and the tool's
   actual result text, rendered as its own list entry interleaved with the surrounding assistant
   text rather than folded into it. Required widening `claude_code_launcher.py`'s single bare
   `{"type": "tool_use", "name": ...}` event into a three-event lifecycle sharing `tool_use_id` as
   the join key (the same pairing pattern `tool_approval_request`/`approve_tool_call` already
   established): `tool_use_start` (immediate, at `content_block_start` — id+name only, since the
   full input hasn't streamed in yet at that point), `tool_use_input` (from the completed
   `AssistantMessage`'s own `ToolUseBlock`, confirmed live this is the first point the full `input`
   dict actually exists), and `tool_result` (from the `UserMessage`/`ToolResultBlock` the SDK
   yields once the tool finishes — confirmed live this fires identically for a real execution *and*
   for a `can_use_tool` denial, whose message arrives here as `is_error=True` content rather than
   through any separate mechanism). That last finding let a real simplification fall out of it:
   `handle_approval_decision` no longer writes an optimistic local "[Allowed X]"/"[Denied X]" note
   at all — the authoritative `tool_result` event updates the matching step card on its own,
   shortly after either decision, so the separate note was redundant and could race it.
   **Live-verified end to end** (`jac browse`, real credentials, screenshots): a `Bash echo` step
   card showed running→done with the real command output as its result text, and a fresh assistant
   text bubble started cleanly after it (not corrupting the step card); a `Write` call needing
   approval showed the same step card sitting at "running" behind its approval card, then flipped to
   "done" with the real "File created successfully..." result text the instant Allow was clicked,
   with no local note involved.

**A follow-up, more systematic audit (2026-09-03, same day — see the research doc's "full audit"
section) went through all 84 top-level entries in upstream's `chat/browser/`, not just what one
screenshot led to. Two real, currently-missing capabilities surfaced, both higher-priority than
the three above because they're gaps in trust/safety and data-loss risk, not just UX polish**:

4. **Tool approval/confirmation — done (2026-09-03).** Claude Code's tool calls (Edit, Write, Bash,
   the `jac mcp` tools wired in above, ...) used to run with whatever `ClaudeAgentOptions.permission_mode`
   default the SDK applies — confirmed live, before this change, that meant a silent, outright deny
   for anything needing a prompt (a plain `Write` call and a plain MCP tool call were both blocked
   with no way for the user to ever say yes) — **entirely invisible in jac-studio's own UI**.
   `ClaudeAgentOptions.can_use_tool` (a real, awaitable callback field, confirmed by introspecting
   the installed package directly) is now wired up in `claude_code_launcher.py`: it emits a
   `tool_approval_request` event (relayed through the existing SSE stream, no new endpoint needed)
   and blocks the tool call by polling a fixed `/tmp` decision file — the exact same file-based
   cross-process command-channel pattern `dap_client.jac`'s own docstring already established, for
   the identical underlying reason (the launcher is a separate OS process; even the eventual RPC
   call carrying the user's decision runs in yet another, different process). `ai_chat.jac` renders
   each pending request as its own approve/deny card (concurrent requests handled correctly, each
   tracked by the SDK's own `tool_use_id`), and `claude_code_client.jac`'s new `approve_tool_call`
   RPC writes the decision. **Live-verified end to end** (`jac browse` against a real `jac run
   --serve --dev` session, real credentials): a real `Write` call correctly produces an approval
   card showing the tool name and its exact JSON input; clicking Allow lets the write actually land
   on disk and the turn continue; clicking Deny blocks the write and the turn continues knowing it
   was denied. **A real bug found and fixed during that same live pass, not left for later**: the
   first version logged the decision as a new `{"role": "tool", ...}` chat-log entry, which broke
   the "the last message in the list is the live assistant response" invariant `text_delta` depends
   on — Claude's own text resumed streaming right after approval and landed concatenated onto the
   decision line (`"[Allowed Write]Created ..."`, no separator) instead of a new bubble, reproduced
   live before the fix. Fixed by reusing the exact pattern the pre-existing `tool_use` event already
   established (append a note into `messages[-1]`'s own text, never push a separate list entry) —
   consistent with, not a new pattern alongside, what the module already did. **No "always allow
   this tool" persistence in this slice, deliberately** — every call gets its own explicit decision;
   a persisted per-tool trust store (VS Code's own `IAutoConfirmEntry`) is real follow-up work, not
   something this slice's core trust-boundary fix needed to include.
5. **Multi-file edit review — done (2026-09-03), scoped to the v1 this section already named.**
   Upstream's `chatEditing/` (20 files, a full checkpoint/timeline mechanism) stays out of scope,
   as this section already said it should — what shipped instead is exactly the smaller v1 named
   above: a real per-file diff preview shown *before* an `Edit`/`Write` call is approved, closing
   the actual risk (an agent silently overwriting a file the user didn't expect) without the
   larger rollback-timeline machinery. Built directly on item 4's `can_use_tool` interception point
   — `claude_code_launcher.py`'s `_diff_preview_for_tool_call` computes a real before/after (reads
   the file's current on-disk content for `original_text`; derives `modified_text` the same way the
   real tool would apply it — `Write`'s given content outright, `Edit`'s one `str.replace` with the
   same single-vs-`replace_all` semantics the real tool documents) and attaches it to the same
   `tool_approval_request` event item 4 already sends. Both tool input shapes (`Write`:
   `{"file_path", "content"}`; `Edit`: `{"file_path", "old_string", "new_string", "replace_all"}`)
   confirmed live, not assumed — a possible `MultiEdit` tool was probed for but the probe timed out
   inconclusively, so it's deliberately left unspecialized (falls back to the generic card) rather
   than guessed at.

   New `ai_tool_diff_preview.jac` renders this with a real Monaco `DiffEditor` (not a `<pre>` text
   dump), reusing `scm_diff_editor.jac`'s already-established synthetic-model-URI pattern for free
   language auto-detection without risking a collision with a real open tab's live model — extended
   one step further than that precedent needed: keyed by the SDK's own `tool_use_id`, not just the
   file path, since this card (unlike a single git diff view) can have multiple concurrent pending
   requests against the very same file. Renders inline/unified (`renderSideBySide: False`), not the
   two-pane view the existing diff components use in a full editor group — this card lives in
   `ai_chat.jac`'s already-narrow sidebar, where two side-by-side panes would each be unreadably
   cramped. **Live-verified end to end** (`jac browse`, real credentials): asked Claude Code to
   `Write` a new file then `Edit` it — both approval cards rendered a real, correct diff (confirmed
   by screenshot, not just DOM inspection) matching exactly what landed on disk after Allow.

**The single strongest finding from the follow-up audit: VS Code natively parses a portable,
non-Copilot AI-plugin format that already includes Claude Code's own format**, confirmed by reading
`src/vs/platform/agentPlugins/common/pluginParsers.ts` directly — `PluginFormat.Claude` expects
`.claude-plugin/plugin.json` + `hooks/hooks.json`, the exact convention Claude Code's own plugin
system already uses (not a Copilot invention), bundling `hooks`/`commands`/`skills`/`agents`/
`instructions`/`mcpServerDefinitions`. There's also a distinct, deliberately vendor-neutral
`OpenPlugin` format. Since jac-studio's Claude Code provider already talks to real Claude Code,
which already understands `.claude-plugin/` bundles, a jac-studio feature that discovers/installs
them needs no new format design — it's parsing a format the underlying tool already consumes. See
the research doc's "full audit" section for the rest of the categorized list (what's excluded and
why, and the `chatStatus/` status-bar idea correction — it's real but Copilot-quota-specific in
upstream, not something to port, only a small from-scratch addition).

**A genuinely jac-native agent option is now on the table, not just external CLI clients.**
`by llm(tools=[...])` is a real, working ReAct tool-calling loop with native streaming and
multi-turn support (see the native-agent-capabilities research doc) — nothing about it needs a
subprocess or hits the Python-interop compiler restriction, since it's a first-class Jac construct.
Wiring `tools=[create_file, run_in_terminal, search_in_files, ...]` — the **already-built** Phase 4
service functions — makes a fourth provider option, distinguished from Claude Code/Copilot/OpenCode
by needing no external CLI installed, just a model API key. Real and worth building; **not** assumed
to be a drop-in replacement for what an external agentic CLI already brings (permission prompting,
context management, a large curated tool set, safety guardrails refined over real usage starts from
zero here) — see the research doc's own "what this does NOT get for free" section.

**MCP wiring for the Claude Code integration — done (2026-09-03).** `jac mcp` is a real, working
MCP server (confirmed live: `jac mcp --inspect` lists 140 resources, 19 tools, 9 prompts covering
Jac validation/formatting/transpilation/docs-search) that `claude_agent_sdk.ClaudeAgentOptions`
can point at (`mcp_servers`, a real, introspected field). `mcp_servers={"jac": {"command": "jac",
"args": ["mcp"]}}` now lands in `claude_code_launcher.py` (the only module that ever constructs a
`ClaudeAgentOptions`, for the same import-explosion reason it's plain Python and not `.jac`) —
giving Claude Code structured Jac-specific tools (`validate_jac`, `explain_error`, `jac_to_js`, ...)
instead of shelling out through Bash for the same work. Live-verified, not just wired: a real turn
correctly lists all 19 `mcp__jac__*` tool names, and a direct SDK call with permissions granted
confirms one (`validate_jac`) genuinely round-trips over stdio and returns a real result. **Found in
the process, not a defect of this change**: the SDK's default permission behavior blocks calling
any MCP tool without prior approval, exactly like Bash/Edit/Write already are — the same
tool-approval gap flagged as item 4 above, not something wiring the server itself needed to solve.

**Not decided yet, deliberately**: whether the `ChatProvider` shape should eventually split into two
layers the way VS Code's `chat.createChatParticipant` / `lm.registerLanguageModelChatProvider` do
(agent-behavior identity vs. model backend, fully decoupled) — worth watching for once a *second*
external-tool provider (Copilot or OpenCode) is actually built and there's a real second data point,
not before. Splitting now, with only one provider shipped, would be exactly the premature
generalization this project's own implementation discipline warns against.

## Open questions this document deliberately does not resolve

- ~~Root-graph-as-service-registry: validated or replaced with `glob` singletons?~~ **Resolved in
  Phase 0**: validated, with a mandatory caching + test-reset discipline — see the Service
  registry section above.
- ~~Monaco-embed bridge for the editor core: needed as a stopgap, or is the native port fast
  enough to skip it?~~ **Resolved in Phase 1 (native), reversed in Phase 2 (Monaco).** Phase 1: a
  working prototype (`src/editor/client/text_editor.jac`, PRs #10/#11) round-tripped real keyboard
  input through the ported `PieceTreeTextBuffer` correctly, with two found gaps (request ordering,
  fixed; rendering virtualization, deferred) both ordinary bounded engineering, not genuine blocks
  — see `2026-08-23-editor-core-native-vs-monaco-decided-native` and
  `docs/phases/phase-1-editor-core.md` for that record as it stood. Phase 2 (2026-08-25): reversed
  to embedding the real `monaco-editor` npm package for v1 regardless — a reuse-over-reinvention
  call, not a verdict that native failed (see the Editor Core section above for the full
  reasoning). The archived native engine lives at `internal/native-editor-archive/` for a possible
  future revival. See `2026-08-25-editor-core-decision-reversed-to-monaco`.
- Extension API surface shape: how much of VS Code's actual `vscode` API do we aim for
  compatibility with (enabling existing extensions to port over) vs. a from-scratch API idiomatic
  to Jac's walker/node model? Not decided — affects Phase B scope significantly and deserves its
  own design doc once Phase A ships. **A concrete test case identified (2026-08-28)**: the real,
  published `jaseci-labs.jaclang-extension` VS Code extension ships a complete
  `jac.tmLanguage.json` TextMate grammar (4,937 lines) far more thorough than the hand-rolled
  Monarch tokenizer Phase 3 shipped as a stopgap (`src/editor/client/jac_language.jac`), plus a
  real language server. **Re-scoped 2026-08-28→2026-08-31**: whether jac-studio can load that
  extension's `.vsix` unmodified is downgraded from a Phase-4 planning item to deferred,
  non-blocking research (see the Extension System section's 2026-08-31 re-prioritization above) —
  the language-server half of the value this test case represents is already reachable directly,
  since `jac lsp` (the same server that extension wraps) is a first-party jaclang CLI command, not
  something reachable only by loading that `.vsix` — see "Language intelligence" above. The grammar
  half (richer than the Phase 3 Monarch stopgap) remains a legitimate reason to eventually answer
  this bullet, just not on the critical path to a feature-complete native editor.
- ~~Color/icon theming: match VS Code's default visual identity, or keep shadcn's own default
  look?~~ **Decided (2026-08-28), implemented (2026-08-28)**: match VS Code's default identity —
  actually "Dark 2026"/"Light 2026"-derived OKLCH tokens via `jac retheme` plus hand-edited exact
  values, real `@vscode/codicons` icons, not the "Dark+/Light+" pair originally assumed here (see
  the Visual identity section's CORRECTION above for why that assumption was wrong) — built
  natively rather than by importing VS Code's theme format.
- Installable, VS-Code-compatible **third-party** theme *extensions* (arbitrary `.vsix` color/icon
  themes a user installs): a genuinely separate question from the default-identity one above, and
  still open — ecosystem-compatible support is real extra work (parsing VS Code's theme JSON
  format, mapping it onto `jac retheme` tokens at runtime) versus themes only ever being authored
  as native `jac retheme` configs. Not decided — see
  [`vscode-complete-triage.md`](vscode-complete-triage.md)'s `themes` row. Decide once Phase 6
  extensions exist to actually contribute a theme.
- Debug Adapter Protocol client: is a Jac/Python DAP client library reachable via Python interop
  (there's a real ecosystem of DAP libraries in Python), or does this need building from the wire
  protocol up? Not researched yet — first task once the native-infrastructure phase (LSP client +
  DAP client, per the 2026-08-31 re-prioritization above) picks up debugging support.
- ~~LSP client: is there a usable Python (or npm) LSP client library reachable via Jac's interop,
  or does this need building from the wire protocol up?~~ **Resolved 2026-08-31**: the question was
  aimed at the wrong half of the problem — the server side is already solved (`jac lsp`, a real
  first-party jaclang command), so the remaining work is a generic client speaking stdio JSON-RPC
  to it, the same shape as the still-open DAP question above. See "Language intelligence" above.
- Which native AI coding-tool integrations (Copilot / OpenCode / Claude Code) get built, in what
  order, and with what auth/licensing model each requires — added 2026-08-31, see "AI coding tool
  integrations" above. Not decided; needs its own scoping pass per tool before implementation.
