---
name: jac-language
description: This skill should be used before writing, editing, or debugging any .jac file, before making any claim about what Jac syntax or the jac CLI can or cannot do, or when a .jac file fails to compile/run and the error isn't immediately understood. Covers where the authoritative reference lives, how to verify instead of guess, and a grounded list of real gotchas already hit in this project.
---

# Working with Jac without hallucinating

Jac's syntax and compiler behavior are not stable enough to trust from memory. This project runs
against `/home/sahan/dev/jaseci` on `main`, and the bundled docs have already been caught
contradicting actual compiler behavior. Verify every claim; never invent syntax by analogy to
Python or TypeScript.

## Trust order

1. **Run it** — `jac check <file>` / `jac test <file>`. The only fully trustworthy source. Never
   assert a `.jac` file is correct without running `jac check`.
2. **`jac guide <topic>`** — bundled with the compiler, tracks the installed version.
3. **Real apps** in `/home/sahan/dev/jaseci/jac/examples/` (littleX, notes-app, todo_app,
   day_planner, chess, mobui, raylib_shooter) — grep these before guessing at an idiom.
4. **`references/gotchas.md`** in this skill — 26 empirically confirmed traps from this project.
   **Read it before writing Jac of any real size**; it is the cheapest bug prevention here.

Jac's compiler errors are unusually specific and often name the exact fix. Read them before
theorizing.

## `jac guide` topic map

`jac guide <name>`, or `jac guide --search <keyword>`.

- **Core**: `jac-core-cheatsheet` (start here), `jac-types`, `jac-has-fields`, `jac-impl-files`,
  `jac-node-edge-patterns`, `jac-walker-patterns`, `jac-concurrency`, `jac-by-llm`
- **Frontend**: `jac-cl-components`, `jac-cl-routing`, `jac-cl-styling`, `jac-cl-auth`,
  `jac-cl-js-interop`, `jac-cl-organization`, `jac-npm-packages`, `jac-shadcn-components`,
  `jac-shadcn-blocks`
- **Backend**: `jac-sv-endpoints`, `jac-sv-auth`, `jac-sv-persistence`, `jac-sv-multi-user`,
  `jac-sv-streaming`, `jac-sv-microservices`, `jac-sv-deploy`
- **Native/desktop**: `jac-native`, `jac-native-memory`, `jac-native-shared`, `jac-native-wasm`,
  `jac-desktop-app`, `jac-mobile-app`, `jac-mobui`
- **Tooling**: `jac-testing`, `jac-debugging`, `jac-packaging`, `jac-scaffold`, `jac-config`,
  `jac-codespaces`, `jac-python-interop`, `jac-project-kinds`, `jac-fullstack-patterns`

## When you find a new gotcha

Add it to `references/gotchas.md` in the same compressed form — symptom, fix, tracker id. If it is
a genuine Jac limitation rather than a syntax detail with a quick workaround, it **must** also go
to the challenge tracker (see `jac-studio-challenge-tracking`). Not optional.
