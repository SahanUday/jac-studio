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
| `src/vs/editor` (Monaco) | 279k lines | A from-scratch Jac text-editing core, bootstrapped by porting Monaco's *algorithms* (piece tree, interval tree, prefix-sum) via the [translator](translator-strategy.md); rendering/interaction rebuilt as Jac client components. Single biggest engineering effort in the project — see Editor Core below. |
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

This is a genuine architectural bet, not a settled fact — it needs to be validated with a real
multi-service slice (e.g., a `ConfigService` + `CommandRegistry` + `FileTreeService` interacting)
early in Phase 0, before the workbench shell is built on top of it. If it doesn't hold up under
real use (e.g., query-based lookup turns out too slow or too indirect for hot paths like
keystroke handling), the fallback is plain module-level `glob` singletons for stateless/compute
services, reserving the graph pattern for things that are genuinely persistent (workspace state,
settings, extension registrations). Track the outcome of this validation as the first real entry
in the challenge tracker, win or lose.

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

## Workbench shell: shadcn-in-Jac primitives, not hand-rolled chrome

VS Code's workbench parts map almost directly onto existing Jac shadcn primitives:

| Workbench part | Jac primitive |
|---|---|
| Activity bar + sidebar | `Sidebar` |
| Editor groups (split panes) | `Resizable` / `ResizablePanel` / `ResizableHandle` |
| Tabs | `Tabs` |
| Command palette | `Command` |
| Right-click menus | `ContextMenu` |
| Status bar hints, hover info | `Tooltip` |
| File tree, output panels | `ScrollArea` (+ a tree component we likely build ourselves — not in the ~50-primitive shadcn set) |

Because the primitive layer already exists, the workbench-shell phase of the roadmap is
realistically a composition/layout effort, not a from-scratch UI-toolkit-building effort — this is
the part of the reimplementation where "everything in Jac" is closest to free, and where we expect
the fewest tracked blockers.

Following the self-registering **contribution model** VS Code uses (rather than one monolithic
layout file), each workbench feature (file explorer, search, settings UI, later: debug/terminal)
should be its own set of Jac modules that attach `Command`/`View`/`Menu` nodes to the registry
graph on load — the direct Jac analog of VS Code's `workbench/contrib/*` self-registration, and
the mechanism that lets `workbench` scale to 4,000 files without a central switchboard.

## Editor core: the hardest, most novel piece — build vs. bootstrap

This is the component with no existing Jac precedent to lean on (no example app implements a real
text-editing widget) and the one place where "everything in Jac" is genuinely expensive rather than
mostly-free. Proposed approach, in order:

1. **Port the algorithms first, headless, via the translator.** Piece-tree text buffer,
   interval tree (decoration lookup), prefix-sum computer (line/offset math) are small, pure,
   well-unit-tested TS modules with minimal DOM/Electron coupling — the best possible first targets
   for the [TS→Jac translator](translator-strategy.md), and validated behavior-for-behavior against
   VS Code's own unit tests before anything renders on screen.
2. **Build the rendering/interaction surface as ordinary Jac client components** on top of the
   ported model (cursor rendering, selection, line-by-line virtualized rendering, keyboard/IME
   input handling) — this part has no good literal translation target (VS Code's DOM-manipulation
   approach doesn't map onto JSX-style rendering) and should be designed idiomatically in Jac from
   the start, informed by but not copied from Monaco's `view/` layer.
3. **Tokenization/syntax highlighting** is a later increment (Phase 3+) — start with a
   TextMate-grammar-compatible tokenizer if one is reachable via Python/npm interop before
   committing to reimplementing tokenization from scratch.

**Explicit fallback, to be decided with real data, not assumed away**: if the from-scratch text
widget proves too costly for an early usable MVP, a temporary bridge embedding the real
`monaco-editor` npm package via jac-cl's npm interop is architecturally possible and would unblock
every layer above it (workbench, extensions) while the native Jac editor core matures in parallel.
This would be tracked as a deliberate, visible, time-boxed decision in the tracker — not a quiet
substitution — consistent with principle 2 above.

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

- Root-graph-as-service-registry: validated or replaced with `glob` singletons? (Phase 0 spike)
- Monaco-embed bridge for the editor core: needed as a stopgap, or is the native port fast enough
  to skip it? (Decide after the Phase 1 translator spike on the piece tree)
- Extension API surface shape: how much of VS Code's actual `vscode` API do we aim for
  compatibility with (enabling existing extensions to port over) vs. a from-scratch API idiomatic
  to Jac's walker/node model? Not decided — affects Phase B scope significantly and deserves its
  own design doc once Phase A ships.
- Color/icon theming: adopt a VS-Code-compatible installable-theme-extension model (ecosystem-
  compatible, more work), or lean entirely on Jac's own native `jac retheme` system (simpler,
  native, incompatible with existing VS Code themes)? Not decided — see
  [`vscode-complete-triage.md`](vscode-complete-triage.md)'s `themes` row. Decide once Phase 4/5
  extensions exist to actually contribute a theme.
- Debug Adapter Protocol client: is a Jac/Python DAP client library reachable via Python interop
  (there's a real ecosystem of DAP libraries in Python), or does this need building from the wire
  protocol up? Not researched yet — first task if Phase 4/5 picks up debugging support.
