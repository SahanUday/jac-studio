---
name: jac-language
description: This skill should be used before writing, editing, or debugging any .jac file, before making any claim about what Jac syntax or the jac CLI can or cannot do, or when a .jac file fails to compile/run and the error isn't immediately understood. Covers where the authoritative reference lives, how to verify instead of guess, and a grounded list of real gotchas already hit in this project.
---

# Working with Jac without hallucinating

Jac's syntax and compiler behavior are **not stable enough to trust from memory or prior
training** — this project runs against `/home/sahan/dev/jaseci` on `main` (dogfooding the latest
compiler, per project decision), and we've already found real mismatches between the bundled
docs and actual compiler behavior this project (see the last section). Treat every claim about
Jac as something to verify, not recall.

## The authoritative sources, in order of trust

1. **Run it.** `jac check <file>` and `jac test <file>` against the real compiler is the only
   fully trustworthy source — it reflects the exact version installed right now, not a snapshot.
   Never assert a `.jac` file is correct without actually running `jac check` on it.
2. **`jac guide <topic>`** — curated reference bundled with the compiler itself, so it tracks
   the installed version far more closely than general knowledge does. Full topic list below.
3. **Real code in `/home/sahan/dev/jaseci/jac/examples/`** — working apps (littleX, notes-app,
   todo_app, mini_todo, day_planner, chess, mobui, ownbench, raylib_shooter). When unsure how an
   idiom is actually used in practice (not just documented), grep a real example before guessing.
4. **This skill's gotcha list below** — real, empirically-confirmed friction from building this
   project, not documentation. Useful as a first check, but not exhaustive — still verify with
   `jac check` when in doubt.

Never invent Jac syntax by analogy to Python or TypeScript. When genuinely unsure, run
`jac guide --search <keyword>` or just try it and read the compiler's own error — Jac's
diagnostics are unusually specific and often name the exact fix (e.g. "prefix with backtick to
escape: `` `keyword ``").

## `jac guide` topic map

Run `jac guide <name>` for any of these (or `jac guide` alone to list all, `jac guide --search
<keyword>` to find by topic):

**Core language**: `jac-core-cheatsheet` (start here for syntax), `jac-types` (type system, `as`
casts, the `any` boundary), `jac-has-fields`, `jac-impl-files` (declaration/implementation
splitting), `jac-node-edge-patterns`, `jac-walker-patterns` (the OSP graph model), `jac-concurrency`
(`flow`/`wait` vs `async`/`await`), `jac-by-llm` (`by llm()` function bodies).

**Frontend (jac-cl)**: `jac-cl-components`, `jac-cl-routing`, `jac-cl-styling`, `jac-cl-auth`,
`jac-cl-js-interop`, `jac-cl-organization`, `jac-npm-packages`, `jac-shadcn-components`,
`jac-shadcn-blocks`.

**Backend (jac-sv)**: `jac-sv-endpoints`, `jac-sv-auth`, `jac-sv-persistence`,
`jac-sv-multi-user`, `jac-sv-streaming`, `jac-sv-microservices`, `jac-sv-deploy`.

**Native/desktop/mobile**: `jac-native`, `jac-native-memory`, `jac-native-shared`,
`jac-native-wasm`, `jac-desktop-app`, `jac-mobile-app`, `jac-mobui`.

**Tooling/ecosystem**: `jac-testing`, `jac-debugging`, `jac-packaging`, `jac-scaffold`,
`jac-config`, `jac-codespaces` (client/server/native placement inference), `jac-python-interop`,
`jac-project-kinds`, `jac-fullstack-patterns`.

## Real gotchas found in this project (grounded, not theoretical)

- **Tuple unpacking needs parens, everywhere** — `for (k, v) in d.items() { }` and
  `(a, b) = f();` both required; the bare Python spelling (`for k, v in ...`, `a, b = f()`) is a
  parse error.
- **Docstrings go immediately before a declaration, never as the first statement inside its
  body.** `""".."""` then `def foo() { }` — not `def foo() { """.."""; ... }` (warning `W0060`,
  often cascades into confusing follow-on errors).
- **`root` is reserved** (the OSP graph anchor) — cannot be used as a variable name anywhere,
  including `with tempfile.TemporaryDirectory() as root { }`.
- **`match`, `default`, `exit` collide with extremely common Python API names** — `re.match(...)`,
  `argparse`'s `default=` kwarg, and `sys.exit(...)` all needed backtick-escaping
  (`` re.`match(...) ``, `` `default=... ``, `` sys.`exit(...) ``). Expect this category of
  friction anywhere Jac wraps a stdlib/PyPI API with common parameter or method names — it isn't
  rare. The docs claim `entry`/`exit` are "not reserved — fine as identifiers," but in practice
  `entry` was rejected as a plain variable name and `exit` as an attribute access — don't trust
  that specific doc claim at face value; escape or rename instead.
- **A plain `with entry { }` runs on every import, not just direct execution.** Use
  `with entry:__main__ { }` for CLI/demo code — otherwise importing the module for reuse (e.g. to
  unit-test a function it defines) will also trigger the block, including any `sys.exit()` in it.
- **No-dot imports for an entry-point script's own top-level imports** — `import from src.module
  { ... }`, not `import from .src.module { ... }`, or it fails at runtime with "attempted
  relative import with no known parent package" (dotted relative imports work fine for
  *non-entry* submodules importing their siblings — this only bites the file that's actually
  executed directly).
- **String-path npm imports (`import from "pkg" { ... }`) are structurally client-only** —
  cannot be used from server/native/CLI code, and `[placement.pins]` cannot override it (hard
  error `E5001`). If a task needs an npm package's functionality outside a browser context, it
  needs a subprocess (see `translator/src/extract.jac` for a real working example), not npm
  interop.
- **Untyped values need explicit casts before using operators like `in`.** A `dict` from
  `json.loads`, or a value from an untyped foreign import, is `any`/`Unknown`; `"x" in
  some_dict["y"]` fails to check (`E1111`) unless cast: `"x" in (some_dict["y"] as list)`.
- **Never name a file `test_*.jac`** — collides with Python's own test-discovery import
  machinery. Use `<name>_tests.jac` for standalone test files, or `<mod>.test.jac` as an annex
  paired with `<mod>.jac` (run via `jac test <mod>.jac`, not the annex path directly).
- **`jac test` runs in parallel across isolated workers**, and graph state under `root` persists
  to `.jac/data` **between runs** — `jac clean --all --force` before a clean run; never assume
  test execution order or that one test can see another's data.
- **Booleans are `True`/`False`, capitalized** — `false`/`true` parse as undefined names.
- **There is no `pass` statement** — write `{}` for an intentionally empty block.

## When something here doesn't resolve it

If a new gotcha gets found, add it to this list (grounded, with the actual error and fix) rather
than letting it stay tribal knowledge for one session. And if it's a genuine Jac limitation or
missing capability — not just a syntax detail with a quick escape/rename fix — **it must be
logged to the challenge tracker, not silently worked around or left unrecorded.** See the
`jac-studio-workflow` skill's "When you hit a blocker" section for the exact procedure. This is
not optional or translator-specific — it applies no matter what part of jac-studio is being
built when the blocker is hit.
