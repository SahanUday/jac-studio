# Jac gotchas confirmed in this project

Each entry: symptom → fix. Tracker ids point to the full writeup; don't re-derive them here.

## Syntax

- **`obj` has no structural `==`** despite the docs' claim, and a hand-written `__eq__` is never
  called. `==` is identity, full stop. Compare fields directly.
  `2026-08-23-obj-equality-not-structural`
- **Reserved words**: `node`, `edge`, `walker`, `obj`, `def`, `impl`, `visit`, `disengage`,
  `report`, `spawn`, `flow`, `wait`, `skip`, `del`, `include`, `with`, `can`, `has`, `root`. A
  leading backtick escapes them, but for a pervasive name (`node` in any tree algorithm) rename
  instead — `intervalTree.ts` needed ~280 renames. Check names *before* writing hundreds of lines.
- **`root` can never be a variable**, including `as root` in a `with` block.
- **`match`, `default`, `exit` collide with common Python APIs** — `` re.`match() ``,
  `` `default= ``, `` sys.`exit() ``. Expect this wrapping any stdlib/PyPI call. The docs claim
  `entry`/`exit` are safe as identifiers; they are not.
- **Tuple unpacking needs parens**: `for (k, v) in d.items()`, `(a, b) = f();`.
- **Docstrings go before a declaration, never as the first statement inside the body** (W0060).
- **A lambda whose body is one bare string literal** trips the same W0060. Use `return "x";`.
- **Zero-arg declarations omit parens** — `def foo { }`, not `def foo() { }` (W3005).
- **`True`/`False` are capitalized**; `true`/`false` are undefined names.
- **No `pass`** — write `{}`.
- **A method calling a bare name matching a module-level function resolves to itself**, not the
  free function (unlike TS). Surfaces as `E1051: Too many positional arguments`. Give the free
  function a distinct name.
- **Untyped values need a cast before operators like `in`** — `"x" in (d["y"] as list)` (E1111).

## Imports and placement

- **No-dot imports in an entry-point script** — `import from src.module`, not `.src.module`.
  Dotted relative imports are fine for non-entry submodules.
- **String-path npm imports (`import from "pkg"`) are structurally client-only** and
  `[placement.pins]` cannot override it (E5001). Need it server-side? Use a subprocess — see
  `internal/translator/src/extract.jac`.
- **A client module importing one server `def:pub` gets pulled server-side wholesale**, and a
  `root`-using module with no Python import or archetype gets pulled client-side wholesale. Both
  need an explicit `[placement.pins]` entry. See `jac.toml`'s pins.
  `2026-08-31-client-module-with-one-server-import-pulled-server-wholesale`,
  `2026-08-31-anchor-free-root-using-module-pulled-client-wholesale`
- **Importing any function from a server-anchored module makes it an async RPC stub client-side**,
  even if it was never `async` (E1042 at the call site). For something hot like a per-cursor-move
  lookup, that silently adds a network round trip. Move pure helpers to their own module with no
  server evidence, and pin it `client` — see `breadcrumb_symbols.jac`.
- **A client-side `import { x as y }` breaks the RPC call**, not just the binding —
  `__jacCallFunction` bakes in the local alias, so it calls a route that doesn't exist. Only a real
  round-trip catches it. Rename the caller's own identifier instead.
  `2026-08-24-client-import-alias-breaks-rpc-route-name`

## Runtime and state

- **`root` is bound per caller, not per process.** A served app resolves a different `root` per
  authenticated user. Any cache of a `root`-resolved value must be keyed by `jid(root)`
  (`dict[str, T]`) — a bare `glob X | None` leaks one user's data to another. Verified live.
- **jaclang's SSE dispatcher appends a trailing `event: end\ndata: {}` frame** to every stream. A
  client that `JSON.parse`s each frame without skipping `event:` lines throws on it, which aborts
  whatever cleanup follows — this permanently disabled the debug Start button. Skip `event:`
  frames, as `terminal.impl.jac` does.
- **`with entry { }` runs on every import.** Use `with entry:__main__ { }` for CLI/demo code.
- **Jac `list` raises `IndexError` where a JS array returns `undefined`.** Ported TS that reads a
  computed index and relies on JS forgiveness will crash. Guard the degenerate case.
- **`threading.Lock` does not make a `def:pub` check-then-create atomic** — the durable commit
  happens after the function returns, outside the lock's reach. jaseci's documented
  `WriteConflict` replay never fires (`raise WriteConflict` appears nowhere in the runtime).
  De-duplicate on the read path instead. `2026-08-25-write-conflict-never-raised-session-commit-blind-retries`
- **Mutating a node's fields in place can duplicate it over real HTTP**, even after a fresh
  `jobj(jid(...))` resolve. Create a new node and detach the old one instead.
  `2026-08-28-rename-field-mutation-duplicates-node-over-real-http`
- **`del`-ing a plain dict entry holding the last Python reference to an edge-reachable node
  corrupts that unrelated edge's later visibility** to `[parent-->]`. Not a graph operation at all
  — an application-level dict. `2026-08-28-path-index-dict-del-corrupts-unrelated-edge-reachability`
- **A `glob` cache can read back empty when its function is reached as a nested cross-module
  `def:pub` call** rather than as its own endpoint, despite an identical `jid(root)`. Root cause
  unisolated, **still open** — don't assume a keyed cache is reliable across that boundary.
  `2026-08-31-cross-module-def-pub-call-sees-empty-glob-cache`

- **`isinstance(x, ArchetypeType)` can fail with the same field-access error as using the missing
  field directly** — checking `isinstance(child, (Folder, File))` against a value that is actually
  a different archetype (`Workspace`, lacking `Folder`/`File`'s own fields) raised the identical
  `'Workspace' object has no attribute 'path'` the direct field access did, one line earlier than
  expected. `isinstance` against an archetype apparently isn't a plain type comparison the way
  Python's is. Use `hasattr(x, "field")` to guard instead.
  `2026-09-04-list-children-by-path-crashes-on-unexpected-contains-target`

## Testing

- **Never name a file `test_*.jac`** — collides with Python test discovery. Use `<mod>.test.jac`
  (annex, run via `jac test <mod>.jac`) or `<name>_tests.jac` (standalone).
- **A `.test.jac` annex must never import the module it is paired with.** It already sees those
  declarations. Doing it anyway breaks *unrelated* `jac run` calls in the same project.
  `2026-08-24-test-annex-self-import-breaks-unrelated-runs`
- **`jac test` runs parallel across workers and graph state persists between runs.** `jac clean`
  first. `jid(root)` is the *same* across tests sharing a worker, so a `jid(root)`-keyed cache
  still needs an explicit `_reset_<x>_cache_for_tests()` hook.
- **`jac clean --all` also wipes `.jac/venv`** — re-run `jac install` after. Bare `jac clean` only
  clears `.jac/data` and is enough to isolate a run.
- **`jac run` persists `root` state across CLI invocations and `jac clean --data` does not reset
  it** for `kind = "cli"` — repeated runs accumulate duplicate nodes. Use a `test` block for
  anything needing a clean slate. `2026-08-24-jac-run-persists-state-jac-clean-does-not-reset`
- **`jac test .` ignores `[test] directory` and sweeps nested subprojects.** Use `jac test` or
  `jac test src`. `2026-08-25-root-test-sweep-crosses-internal-subproject-boundary`

- **Subclassing a Python library class as a Jac `obj` works, including virtual dispatch.**
  `obj _DirtyDirHandler(FileSystemEventHandler)` overriding `on_any_event`, scheduled against a real
  `watchdog.Observer`, fires correctly across the Jac/Python boundary — confirmed with a real `jac
  run`, not assumed. A small, real dependency like this is safe to import at `.jac` module scope;
  contrast with `claude_agent_sdk`'s dependency closure, which is not (see the `python-interop`
  entry above).

## Client / jac2js

- **A dict literal with a variable key miscompiles** — `{some_var: value}` emits invalid JS.
  `jac check`/`jac test` never see it; only the Vite build does. Use
  `updated = {**d}; updated[key] = value;`. `2026-08-24-client-dict-literal-variable-key-miscompiles`
- **`jac install --shadcn command` generates a `CommandDialog` that crashes on open** — children
  are not wrapped in the `Command` root that `cmdk` needs. Hand-wrap after every regeneration.
  `2026-08-25-shadcn-command-generator-missing-root-wrapper`
