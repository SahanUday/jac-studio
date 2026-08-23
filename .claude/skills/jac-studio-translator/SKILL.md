---
name: jac-studio-translator
description: This skill should be used when running, discussing, or planning to use the jac-studio translator tool (translator/main.jac) — porting a VS Code TypeScript module into Jac, deciding what to queue next, using the add/status/extract/verify commands, or interpreting manifest.toml's risk tiers. Not for logging a blocker (see jac-studio-challenge-tracking) or general git/PR conventions (see jac-studio-git-workflow) — those apply project-wide and are deliberately kept separate.
---

# Using the jac-studio translator tool

Full detail and flag reference: `translator/README.md`. This is the operational summary — read
that file directly for anything not covered here.

## One-time setup (per checkout, not per session)

Check `translator/.jac/` and `translator/extract/node_modules/` before redoing this:

```bash
cd translator && jac install          # Jac + Python deps (tomli-w)
cd extract && npm install             # Node deps for the extraction shim (typescript)
```

## The five commands

All run from `translator/`, as `jac run main.jac -- <subcommand> [flags]`. State is tracked in
`translator/manifest.toml` (git-tracked, portable — paths relative to `--vscode-root`, never
absolute).

1. **`add`** — eligibility-check a TS module and queue it:
   ```bash
   jac run main.jac -- add --vscode-root /home/sahan/dev/vs/vscode \
     --source src/vs/editor/common/model/prefixSumComputer.ts \
     --test-root src/vs/editor/test --id prefix-sum-computer --risk-tier low --phase 0
   ```
   If upstream's test-to-source naming convention doesn't hold (a module tested only through an
   outer wrapper's test file — real example already in the manifest: `piece-tree-base`), pass
   `--test-file` explicitly rather than trusting the basename search to find it.
2. **`status`** — print the manifest grouped by status (`queued`/`in-progress`/`landed`/`blocked`).
3. **`extract`** — pull structured context (exports, signatures, doc comments, imports) for a
   queued module: `jac run main.jac -- extract --id <id> --vscode-root <path>`. This is context
   *for you* to translate from — it does not do the translation itself, and it never will (see
   `jac-studio-architecture`'s decision procedure for why translation stays a judgment call).
4. **`verify`** — once a Jac port exists, set `jac_path` (and `test_jac_path`, once that exists
   too) in `manifest.toml` by hand, then `jac run main.jac -- verify --id <id>` runs `jac check`
   then `jac test` as real subprocesses and updates the manifest status. A module with no ported
   test file correctly **fails** verification (`jac test` exits nonzero, "No tests ran") rather
   than silently passing — don't expect `verify` to succeed until the tests are ported too, not
   just the module itself.
5. **`block`** — scaffolds a challenge-tracker entry when a translation attempt hits a real
   blocker. This is the one command that overlaps with `jac-studio-challenge-tracking` — use
   that skill for the actual logging procedure and entry format; this tool just pre-fills the
   frontmatter from the manifest record you're already working with.

## Automation tiers

The manifest's `risk_tier` field: `low`-risk modules (small, pure, narrow — currently
`prefix-sum-computer`, `interval-tree`) can go through `add`→`extract`→translate→`verify` with
lighter supervision. `foundational` modules (currently just `piece-tree-base`, since the whole
editor core depends on it getting it right) always get a deliberate, single-module session with
real review before landing — plus differential testing against upstream beyond just ported-test
parity, per `docs/translator-strategy.md` on `main`.

## Translation targets, in priority order (from docs/translator-strategy.md)

1. `prefixSumComputer.ts` — smallest, purest, do this first
2. `intervalTree.ts`
3. `pieceTreeTextBuffer/` (foundational — the piece-tree buffer everything else depends on)
4. `textModel.ts`'s non-DOM-facing subset

Never point this tool at `workbench/` — UI code is designed fresh in Jac, never mechanically
translated (see `jac-studio-architecture`'s decision procedure).
