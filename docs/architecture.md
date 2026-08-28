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
| Title bar (window controls + Command Center search) | No direct shadcn primitive — hand-built chrome. Not yet built (see below). |
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
  (Phase 4/5) contributes a command that knows how to construct the right shell invocation for a
  file type (`python foo.py`, `cargo run`, ...) and hands it to the same `RunInTerminal` walker.
  No new mechanism needed.
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

Proposed shape for jac-studio, deliberately mirroring the Debug Adapter Protocol treatment above
since it's the same category of problem:

- The **editor-side consumption layer** (rendering a completion popup, a hover card, a peek view)
  is workbench-core UI work, independent of any specific language — build it once, Phase 4-or-later,
  against a generic provider interface.
- **Providers themselves are extension-contributed**, same as upstream — a language extension
  either implements the interface directly or bridges to a real LSP server subprocess (the same
  `shell`-capability process-spawn mechanism already scoped for the terminal handles launching
  one).
- **Shared open question with the DAP client**: is there a usable Python (or npm) LSP client
  library reachable via Jac's interop, or does this need building from the wire protocol up?
  Worth researching once, since both DAP and LSP are JSON-RPC-shaped protocols with a similar
  "spawn a subprocess, speak a wire format" integration story.
- This cluster isn't just "show the results" — a rename provider is useless without something to
  actually *apply* a multi-file edit, and a call-hierarchy/outline panel is just workbench UI over
  the same provider data as the completion popup and hover card. Bulk-edit application and the
  outline/call-hierarchy/breadcrumbs views belong in this same effort, not as separate features
  discovered later (see [`vscode-complete-triage.md`](vscode-complete-triage.md)).

See [`vscode-feature-gap-analysis.md`](vscode-feature-gap-analysis.md) for the full inventory this
was drawn from, including several Tier 2/3 items (source control, tasks/problem-matchers, the
keybinding context-evaluation system, and a genuinely surprising finding — VS Code's chat/agent
subsystem is now larger than its entire editor core) that are tracked there rather than folded
into every section of this document.

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
  Monarch tokenizer Phase 3 shipped as a stopgap (`src/editor/client/jac_language.jac`) — whether
  jac-studio can load that extension (fully, or at least its grammar via a narrower
  `vscode-textmate`/`vscode-oniguruma` bridge if full compatibility isn't feasible) is now scoped
  into Phase 4's plan (see `roadmap.md`), and answering it also resolves this bullet, not just the
  syntax-highlighting stopgap.
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
  [`vscode-complete-triage.md`](vscode-complete-triage.md)'s `themes` row. Decide once Phase 4/5
  extensions exist to actually contribute a theme.
- Debug Adapter Protocol client: is a Jac/Python DAP client library reachable via Python interop
  (there's a real ecosystem of DAP libraries in Python), or does this need building from the wire
  protocol up? Not researched yet — first task if Phase 4/5 picks up debugging support.
