---
name: jac-studio-code-style
description: This skill should be used when writing or restructuring any jac-studio .jac file — deciding whether to split declarations from implementations, naming internal helpers, organizing a client component, or judging whether a comment or docstring earns its place. Load before writing a new module of real size, or when a file grows past ~150 lines.
---

# Writing idiomatic, lean Jac

## Prose: the hard rules

The codebase is kept deliberately lean; text earns its place or it goes.

- **Module docstring: 5 lines max.** What it is, any non-obvious constraint, one link. That's all.
- **Comments: rare and one line.** Only for what the code cannot say — an ordering constraint, a
  workaround, a real gotcha. If it restates the line below it, delete it.
- **Never in source**: changelogs, dated "as of" narratives, QA-pass reports, design-rationale
  essays, scope justifications, or chains of cross-references to four other files. These go to
  `docs/decisions/` as an ADR; link it in one line if the code needs it at all.
- A `PostToolUse` hook flags files over budget. It's advisory — fix it, don't ignore it.

The good pattern already in this repo: `# a brand-new folder is known to be empty -- scanned=True
skips a pointless first listdir`. One line, states a fact the code can't.

**Before deleting a comment, check what it actually is.** `# region`/`# endregion` markers in
ported files are upstream VS Code's own section boundaries — fidelity breadcrumbs, not noise.

## Declarations vs. implementations

Jac auto-discovers `impl` bodies by naming/location. Work top to bottom:

1. Mostly data, few methods → **pure declarations**, no impl file. Don't create one for symmetry.
2. Under ~150 lines total, short methods → **inline**. Splitting adds navigation cost for nothing.
3. One class, 20+ methods, clearly distinct concerns → **`.impl/` directory**: `mod.jac`
   (signatures) + `mod.impl/*.impl.jac`, one file per *feature*. Verify the grouping against the
   real method list (`grep -n "^obj \|^    def "`), don't guess from names.
4. Several medium modules in one package → **shared `impl/` directory**.
5. Otherwise → **side-by-side** `mod.jac` + `mod.impl.jac`.

Mechanics, verified:

- A method with no explicit return type needs `-> None` on **both** the declaration and the `impl`
  line; they must match exactly. Same for `postinit`.
- Both `mod.impl.jac` and `impl/mod.impl.jac` auto-discover correctly.
- After a split, `jac check` clean and `jac test` at the **exact** pre-split pass count. A drop is
  a transcription error, not a real regression.

## Client components

A `def:pub app -> JsxElement` shell keeps `has` fields, `can with entry`, and handler *stubs* in
the component file; handler *bodies* move to `<component>.impl.jac`.

- Receiver is the export name: `impl app.handler_name(...) -> T`, not `impl ComponentName.…`.
- Inside an impl block, `has` fields are read and written **bare** — `lines = new_lines;`, never
  `self.lines`. Assignment re-renders exactly as inline.
- **Views that mount once and hide with CSS must refetch on activation** — `useEffect([active])`,
  not just on mount. Otherwise they show whatever was true at first render (SCM said "No
  repository" after a folder was opened). Same applies to output, problems and task views.
- Verify with a live `jac browse` session, not just `jac check` — a static pass cannot catch broken
  event wiring. Stop the server and clear ports 8000/8001 after.

## The `_` prefix

Leading `_` means internal-only: nothing outside the module (or its own `.test.jac`) calls it.
Before renaming, confirm it: `grep -rn "\b<name>\b" src/ main.jac`. A name imported by another
module is public API — leave it. Private helpers belong in the impl file, not the declaration file.
