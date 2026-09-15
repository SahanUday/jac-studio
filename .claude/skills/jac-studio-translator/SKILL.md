---
name: jac-studio-translator
description: This skill should be used when running or planning to use the jac-studio translator tool (internal/translator/main.jac) — porting a VS Code TypeScript module into Jac, or interpreting manifest.toml. The tool is currently idle with no queued targets; check here before assuming it should be used at all.
---

# The TS→Jac translator

Full detail: `internal/translator/README.md`. **Currently idle** — all original targets landed,
then the editor engine moved to the real `monaco-editor` package, so the ported code is archived at
`internal/native-editor-archive/` and nothing is queued. The workflow stays ready for a genuinely
pure, tested, in-scope module; it is not the default way to build anything.

Per `jac-studio-architecture`'s decision procedure, translation ranks *below* reusing a proven
library and below redesigning around a Jac primitive. **Never point it at `workbench/`** — UI is
designed fresh.

## Setup (per checkout)

```bash
cd internal/translator && jac install
cd extract && npm install
```

## Commands

All from `internal/translator/`, as `jac run main.jac -- <cmd>`. State lives in `manifest.toml`
(git-tracked, paths relative to `--vscode-root`).

| Command | Does |
|---|---|
| `add` | Eligibility-check a TS module and queue it. Pass `--test-file` explicitly when upstream's test naming doesn't match the source basename. |
| `status` | Print the manifest grouped by status. |
| `extract` | Pull exports/signatures/doc comments for you to translate from. It never translates. |
| `verify` | Runs `jac check` then `jac test` and updates status. |
| `block` | Scaffolds a tracker entry — see `jac-studio-challenge-tracking` for the real procedure. |

**`verify` only ever runs against `jac_path`.** Ported tests must therefore live in a
`<mod>.test.jac` annex; a standalone `<name>_tests.jac` leaves `verify` reporting "no tests ran"
and marking the module blocked. Known gap: `verify` fails with `ModuleNotFoundError` for modules
using absolute `src.…` imports — pre-existing and unrelated to your change. Check `jac test <path>`
directly before trusting a `blocked` status, and revert any spurious `manifest.toml` flip.

The six landed modules' `jac_path`s are stale (files moved to the archive) — `status = "landed"`
there does not mean "wired into the app".

## Lessons worth keeping

- **Port upstream's test adapters too.** When a test file exercises implementations through a
  shared wrapper, that adapter is part of what makes the tests meaningful. Skipping it produces
  silent wrong-answer bugs.
- **Fields referencing untranslated classes stay untyped placeholders**, with the method that
  touches their shape deferred. Don't invent a shape for a class that doesn't exist yet.
- **Generate large assertion tables from the TS source with a script.** A 208-case table was pulled
  with a regex pass — hand-transcription on that scale is pure risk.
