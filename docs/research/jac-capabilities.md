# Research notes: what Jac actually offers (docs + skills)

Sources: `/home/sahan/dev/jaseci/jac/jaclang/cli/docs/{quick-guide,reference,internals}`,
`/home/sahan/dev/jaseci/jac/jaclang/cli/skills/*.md` — all 37 skill files read in full.
Investigated 2026-08-22. Grounding reference for [`../architecture.md`](../architecture.md).

## Core language model

Jac is **synechic** (one language spanning server/client/native/LLM "codespaces," inferred not
annotated) and **topokinetic** (Object-Spatial Programming: mobile computation over a persistent
graph). Four archetypes: `obj` (plain data), `node` (graph-persistent entity), `edge` (typed
relationship, can itself carry fields/abilities), `walker` (mobile stateful computation).

- `can ability with Type entry/exit { }` — dispatch by *arrival*, not invocation. In a walker
  ability `self`=walker, `here`=current node; in a node ability `self`=node, `visitor`=the walker.
- `visit [-->]` queues neighbors explicitly (BFS default, `visit:0:[-->]` for DFS) — a node with
  no `visit` call is a dead end. `report x` accumulates into `.reports`. `disengage` halts the
  whole walker; `skip` returns from just the current ability.
- **`root` is a persistent anchor — whatever is reachable from `root` persists automatically.**
  No ORM, no schema setup, no migrations file. Every served user gets an isolated `root`;
  `root.shared` is the deployment-wide commons graph.
- Query syntax does typed, filtered, deduplicated multi-hop graph traversal inline:
  `[a ->:EdgeType:field>val-> [?:NodeType, field==val]]`.
- `.impl.jac` files separate declarations from bodies (three layout conventions available).
- Static typing at boundaries, inferred in bodies; `any` can't silently flow into typed
  destinations. `flow`/`wait` for true parallelism, `async`/`await` for I/O concurrency.
- `by llm()` + `sem` annotations: delegate a function body to an LLM call with the return type
  enforced as the output schema — prompts synthesized from names/types, not hand-written strings.
- **Placement (codespace) is fully inferred from imports**, never annotated: JSX/npm → client,
  Python/graph archetypes → server (default), extern-C → native. Overrides only via
  `jac.toml [placement.pins]`.

## Frontend framework (jac-cl-*)

A genuine React-equivalent DSL. `has` fields = reactive state (plain assignment re-renders, no
`setX` — but **mutating a list/dict in place silently fails to re-render**, the #1 flagged
Python-habit bug). `async can with entry` = mount effect; typed event-handler methods
(`MouseEvent`, `ChangeEvent`, all ambient); `Ref[T]` fields = `useRef`.

- **Routing**: file-based `pages/` directory (Next.js-shaped: `[id].jac`, `(group)/`, `(auth)/`
  auto-wraps `AuthGuard`, `layout.jac`) is the recommended default over manual `<Router>`.
- **Styling**: Tailwind v4, zero-config; scoped `.style.css` annex files auto-hash-scoped by
  basename; `cn()` (clsx + tailwind-merge) for conditional classes.
- **Auth**: `jacLogin`/`jacSignup`/`jacLogout`/`jacIsLoggedIn`/`jacSsoLogin` from `@jac/runtime`,
  JWT/cookie session, `AuthGuard` wraps route groups.
- **Component library — this is the big one for us**: shadcn/ui is built into jaclang core.
  `jac install --shadcn <name>` pulls ~50 accessible Radix-based primitives written natively in
  Jac (Button, Dialog, **Sidebar**, Table, **Command palette**, DataTable, **Resizable**/
  `ResizablePanel`/`ResizableHandle`, Tabs, ContextMenu, Tooltip, ScrollArea...), themeable via
  `jac retheme` (OKLCH CSS vars driven by `jac.toml [jac-shadcn]`). A VS-Code-style workbench
  shell (sidebar + resizable editor groups + tabs + command palette + tree views) maps almost 1:1
  onto primitives that already exist — this is the single most load-bearing fact for scoping the
  workbench-shell phase of the roadmap.
- **Streaming**: SSE via `def:pub ... -> Generator` + `report stream()`, consumed with raw
  `fetch().getReader()` — relevant for incremental LSP/AI output later.

## Backend framework (jac-sv-*)

Every `walker:pub`/`def:pub` becomes a REST endpoint automatically, with **auto-generated Swagger
at `/docs` and a live graph visualizer at `/graph`**. `:pub` = anonymous-OK (runs on
`root.shared` or the caller's own root if authenticated); plain `def`/`:priv` = JWT-required, own
isolated root. Built-in role system (`admin`/`system`/`user`).

- **Persistence: the graph *is* the database** (Postgres-backed, embedded/zero-setup or external
  via `JAC_DB_URL`). Schema evolution is graceful (new fields default, removed fields move to an
  "attic") — **except a moved/renamed module changes archetype identity**, which is effectively a
  breaking schema migration unless you declare `@archetype_alias`. Real friction for an evolving
  large codebase; track file moves carefully once the workspace/extension graph model exists.
- **Deployment**: `jac start --scale` is one-command Kubernetes (auto-provisions Postgres/Redis/
  Mongo, HPA, TLS via cert-manager). Webhooks, WebSockets, S3 file storage, Prometheus metrics,
  Redis distributed locks all built in.
- **Microservices**: splitting a module into its own service is a `jac.toml` config change, not a
  code change — imports of a routed module transparently become RPC stubs.
- **Multi-user sharing**: `grant()`/`revoke()`, `allow_root`/`disallow_root`, `root.shared`,
  `__jac_access__` policy hook — a coherent, explicit isolation model, good fit for collaborative
  editing later.

For an editor's backend (workspace/file graph, extension registry, settings, sessions), this
removes essentially all the boilerplate a hand-rolled service+DB stack would need.

## Native/desktop & mobile runtime

**Desktop is NOT Electron, Tauri, or PyInstaller.** `jac nacompile` produces a native host binary
embedding CPython, serving the standard Vite/React client bundle over loopback, rendered in the
**OS's native webview** (WebKitGTK/WKWebView/WebView2) — architecturally like Tauri but with Jac's
own native compiler and the server logic running **in-process**, no separate backend to manage.
Capability-gated `@jac/desktop` IPC bridge (filesystem, dialogs, clipboard, notifications, shell —
`shell` deny-by-default) for OS access — directly analogous to what an extension host needs.
**Status: explicitly beta.** No cross-compilation (must build per target OS), no code-signing
pipeline yet (upstream issue #6436) — confirmed independently by the VSCodium packaging research
in `vscodium-packaging.md`.

Mobile has two paths, both beta: a Capacitor webview wrapper (frontend-only, needs a separately
deployed server), and **MobUI** — one source compiling to real React Native *and*
react-native-web via `@jac/mobui` primitives (bans raw HTML, though enforcement is inconsistent —
only on `main.jac`/`.native.jac`, not plain component files).

Separately, a real LLVM-backed **native compilation** path exists: C FFI, opt-in ownership/
borrow-checking (`own`/`&`/`&mut`, zero-RC "headerless" builds), shared-library export, and a
**WASM target** — a Jac module compiles to `.wasm`, importable lazily from client code. This
subset excludes walkers/nodes/edges/async/PyPI — a restricted language surface, not "the whole
language, compiled fast." Relevant later as a possible foundation for sandboxing extension code
(see gaps below), but there is no ready-made plugin sandbox — we'd be building one.

## Tooling & ecosystem

One binary bundles CPython 3.14, Bun, LLVM+Zig linker, Postgres-backed server, a Kubernetes
deployer, formatter/linter/type-checker/LSP/test-runner/MCP server. `test "name" { assert ...; }`
blocks + `jac test` (parallel workers; **graph state persists to `.jac/data` between runs** —
`jac clean --all --force` needed to reset); `JacTestClient` for in-process endpoint tests;
`MockLLM` for LLM-call tests. `jac build --as wheel|npm` for packaging (no `jac publish` — use
`twine`/`npm publish`). Full PyPI interop via plain `import`; `::py::` blocks for legacy code;
`class` archetype for subclassing Python metaclass-driven types (relevant if wrapping existing
Python syntax-highlighting/LSP libraries like Pygments). npm interop via quoted-string imports.

## Gaps worth tracking from day one (not discovered-later surprises)

1. **Desktop packaging unfinished** (#6436) — no signing, no installers, no cross-compile.
2. **MobUI's HTML ban is inconsistently enforced** — silent-failure trap, not a hard guarantee.
3. **`jac2js` is young and leaky** — documented miscompilation classes: `let`-scoping/TDZ bugs,
   string-literal newline escaping, `sorted(key=lambda)` rejected client-side, `asChild`/ref-
   forwarding silent no-ops, `jac check` false positives that are "correct at runtime," a dict
   literal keyed by a variable (`{x: y}`) compiling to invalid JS instead of a bracketed computed
   key, and a client-side aliased import (`{real_name as alias}`) baking the *alias* into an RPC
   call's route name instead of the server's real registered name — see tracker entries
   `2026-08-24-client-dict-literal-variable-key-miscompiles` and
   `2026-08-24-client-import-alias-breaks-rpc-route-name`.
4. **Known upstream bug** (jac#7695): adding `def:pub` to an already-imported module still 404s
   until its name is re-added to the entry import.
5. **No production-grade extension/plugin sandbox.** The native+WASM pathway could theoretically
   host untrusted code, but there's no built-in capability/permission model for third-party WASM
   plugins — this is custom engineering, not a Jac feature we can lean on. **This is the single
   biggest open R&D risk in the whole project**, bigger than the text editor itself.
6. Ownership/borrow-checking is opt-in and pre-1.0 (extensive gotcha lists, "not yet implemented"
   markers) — only relevant if/when extension-host performance needs the zero-RC native path.
7. No client-side CORS control in single-process `jac start` (`allow_origins=['*']` hardwired) —
   fine for dev, a gap before any public-facing deployment.
8. File uploads cap at 100MB in-memory (`UploadFile` buffers the whole body) — relevant if the
   editor ever needs large binary workspace assets; would need direct S3 streaming instead.
9. A file move for any module declaring `node`/`edge` types is effectively a schema migration
   (archetype identity includes module path) — real friction for iterative refactors of a large,
   evolving data model like ours.
10. **Ecosystem is young and moving fast** — skills repeatedly cite "verified against the live
    server/compiler," reference specific open GitHub issues by number, and a dedicated
    `community/breaking-changes.md` doc exists. Expect breaking changes between Jac versions;
    pin a version per `jac-config.md` profiles and track upgrades deliberately.

## Overall read

OSP is a genuinely strong fit for an editor's data layer (workspace files/folders as a node graph,
extensions as walkers, settings/keybindings as graph-attached objects), and shadcn-in-Jac covers
most of a VS-Code-style workbench UI out of the box. The desktop shell mechanism is architecturally
sound and lightweight. Productionization (signing, installers, extension sandboxing) and the
compiler's own youth (`jac2js` quirks, breaking changes) are the parts we build ourselves, on a
still-maturing platform — which is exactly why the challenge tracker in
[`../challenge-tracking.md`](../challenge-tracking.md) matters as much as the app itself.
