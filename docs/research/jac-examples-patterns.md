# Research notes: idioms extracted from real Jac example apps

Source: `/home/sahan/dev/jaseci/jac/examples/*` (littleX, notes-app, todo_app, mini_todo,
day_planner, chess, mobui, ownbench, raylib_shooter). Investigated 2026-08-22. These are
patterns observed in working code, cross-checked against the docs-derived
[`jac-capabilities.md`](jac-capabilities.md) — docs and practice agree closely, which is a good
sign for the maturity of these particular patterns (as opposed to the compiler-quirk gaps, which
are also consistent between docs and examples).

## Patterns that repeat across multiple apps (the real de-facto conventions)

- **Markerless full-stack files are the default shape.** One `main.jac` holds nodes/edges/walkers
  *and* the `def:pub app -> JsxElement {...}` component; the compiler infers server vs. client per
  symbol. Splitting into `frontend.jac`/`frontend.impl.jac` + a separate backend file only happens
  once auth or component count justifies it (littleX, day_planner's `auth`/`walkers` variants).
  **Implication for us**: don't over-structure jac-studio's file layout up front; let it grow the
  way these examples grew.
- **`root` is the per-user graph anchor everywhere.** `root ++> Node(...)` to create,
  `[root-->][?:Type]` / `[-->[?:Type]]` to query. `walker ... with Root entry` is the standard
  first hop.
- **Two backend registration styles, freely mixed in the same codebase**: `def:pub`/`def:priv`
  functions doing direct graph ops (mini_todo, day_planner/basic, day_planner/auth) vs.
  `walker:pub`/`walker:priv` doing object-spatial traversal (littleX, todo_app, day_planner/
  walkers). `:priv` vs `:pub` is *literally* what toggles shared-vs-per-user graph isolation —
  the day_planner example proves this by re-implementing the identical app three ways with "no
  changes to business logic" between the `basic` and `auth` variants.
- **Walker report convention**: `report <value>` inside an ability; the client receives
  `result.reports` as a list of lists, commonly unwrapped as `reports[0][0]`. Node identity
  crossing the wire is `jid(node)` / `node._jac_id`, resolved server-side via `jobj(id)`.
- **Fan-out / gather / report-on-exit** is the standard multi-result walker shape:
  `can ... with Root entry { visit [...]; }`, `can ... with T entry { self.results.append(here); }`,
  `can ... with Root exit { report self.results; }` — appears near-verbatim in littleX and
  day_planner/walkers. Exit abilities run LIFO/post-order, which is what makes this work.
- **Walker inheritance as a mixin for shared entry logic**: a base walker resolves a target by id
  (`walker find_tweet`), and subclasses (`walker like_tweet(find_tweet)`) add a reactive ability
  that fires once the base has navigated there, ending in `disengage`. Non-obvious, genuinely
  useful pattern for "operate on a thing after locating it" flows (littleX, `social_graph.jac`).
- **`has` fields on a JSX component are reactive state**; `can with entry` = mount;
  `can with [field] entry` = a dependency-scoped effect (littleX's dark-mode toggle) — the direct
  Jac equivalent of a React `useEffect(fn, [field])`.
- **List rendering via comprehensions embedded directly in JSX**, conditional rendering via
  ternaries returning `None` for "render nothing" — consistent across littleX, notes-app,
  todo_app.
- **AI-typed domain models**: `def foo(...) -> SomeEnum by llm();` plus `sem Field = "..."`
  annotations to steer structured output, always wrapped in `try/except` with a degraded fallback
  string when no API key is present (mini_todo, all three day_planner variants). Worth adopting
  verbatim for any AI-assist feature we build later (inline suggestions, commit-message gen, etc).
- **Desktop packaging is exercised for real, not just documented**: todo_app ships as
  `jac start --client desktop`, with least-privilege capability flags in `jac.toml`
  (`[desktop.plugins] notification = true`) and a typed `@jac/desktop` SDK preferred over raw
  `window.__jac.invoke()` strings.

## Most-relevant examples in more detail

**littleX** (social graph app) is the most complete full-stack reference: real auth, access
control (`grant(node, level=AccessLevel.WRITE/CONNECT)` immediately after node creation), and a
hand-ported shadcn-style UI primitive library under `components/ui/` mirroring the real
shadcn/Radix API (`cva()` variants, `asChild`/`Slot.Root` polymorphism, prop-spreading) closely
enough that porting workbench chrome later should feel familiar to anyone who's touched
shadcn/ui in React. `get_trending`/`get_all_profiles` need manual jid-based dedup because
`allroots()` fan-out can reach the same node via multiple paths — **graph fan-out does not
auto-dedupe**, a real gotcha for any "aggregate across users" query we write.

**notes-app** (two-pane sidebar + editor — the closest existing example to our workbench shape)
is deliberately the odd one out: **no backend graph at all**, pure client-side `localStorage`
state, used as the project's CEF/desktop smoke test. Its README documents real desktop-packaging
friction worth expecting: first-run ~1.4GB CEF download, `libpython3.x.so` version-pinning issues,
GPU/fontconfig workarounds (`JAC_CEF_DISABLE_GPU=1`). It also shows the idiom for a client probing
its native host bridge (`window.__JAC_DESKTOP__`, `window.__JAC_BROKER__`, `/__jac/health`,
`/__jac/session`) — directly reusable for a "desktop capabilities" diagnostics panel later.

**todo_app** shows the cleanest `walker:pub` REST-endpoint pattern and is the proof-of-life that
desktop packaging works end to end today for a small app; its README documents the typed
`@jac/desktop` SDK and capability flags we'll want for filesystem/dialog access once jac-studio
needs "open folder"/"save file" — exactly the primitives an editor needs first.

**day_planner** is the single best teaching artifact: the same app implemented three ways
(`basic`/`auth`/`walkers`) to demonstrate architecture tradeoffs explicitly, including a walker
ability that deletes stale items purely as a side effect of traversal encountering them
(`can clear_old with ShoppingItem entry { del here; }`) rather than a separate cleanup pass —
worth remembering for graph-hygiene walkers (e.g., pruning closed-editor state).

**chess** (no UI) confirms plain `obj` inheritance syntax (`obj Pawn(Piece) {...}`) and
decl/impl splitting at scale via `.impl.jac` — relevant once the workspace/extension-manifest
object model grows past what one file should hold.

**mobui** confirms a real "same logical component, per-platform implementation file" precedent
(`icon.jac` vs `icon.native.jac`) — a pattern we may need if the desktop shell and a future
web-only mode need different native-bridge implementations behind one component interface.

**ownbench** and **raylib_shooter** are native-compilation/FFI/WASM demos, architecturally
unrelated to a workbench UI but confirm the native/WASM tooling referenced in
[`jac-capabilities.md`](jac-capabilities.md) is real and exercised, not vaporware — relevant only
if/when we pursue WASM-based extension sandboxing.
