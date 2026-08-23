# jac-studio translator

The TS→Jac porting tool described in [`docs/translator-strategy.md`](../docs/translator-strategy.md)
(main branch). An internal bootstrapping tool and gap-detection instrument, not a general
transpiler — see that doc for the full design rationale, the redesign/translate/build-fresh
decision procedure, and why this tool is Jac-first with one confirmed exception (extraction).

## What's here

```
translator/
  main.jac           CLI entry point (add / status / extract / verify / block)
  jac.toml
  manifest.toml       the ledger -- git-tracked, portable (paths relative to --vscode-root)
  src/
    manifest.jac       ManifestEntry + load/save/find
    eligibility.jac     the Tier-1 eligibility guard
    extract.jac          calls extract/extract.mjs as a subprocess
    verify.jac            jac check + jac test invocation
    tracker_entry.jac      scaffolds a challenge-tracker entry on failure
  extract/
    extract.mjs         Node script wrapping the TypeScript compiler API
    package.json
  tests/
    manifest_tests.jac
    eligibility_tests.jac
  blocked/             local staging dir for scaffolded tracker entries, gitignored
```

## Setup

```
jac install                    # Jac + Python deps (tomli-w)
cd extract && npm install      # the extraction shim's own deps (typescript)
```

## Usage

All paths for `add`/`extract` are relative to `--vscode-root` (your local `microsoft/vscode`
checkout) — the manifest stores them that way too, so it's portable across machines.

```bash
# 1. Eligibility-check a candidate and queue it
jac run main.jac -- add \
  --vscode-root /path/to/vscode \
  --source src/vs/editor/common/model/prefixSumComputer.ts \
  --test-root src/vs/editor/test \
  --id prefix-sum-computer --risk-tier low --phase 0

# If the naming convention doesn't hold (a module tested only as part of a larger unit --
# see manifest.toml's piece-tree-base entry), pass the test file explicitly:
jac run main.jac -- add \
  --vscode-root /path/to/vscode \
  --source src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts \
  --test-root src/vs/editor/test \
  --test-file src/vs/editor/test/common/model/pieceTreeTextBuffer/pieceTreeTextBuffer.test.ts \
  --id piece-tree-base --risk-tier foundational --phase 1

# 2. See what's queued
jac run main.jac -- status

# 3. Pull structured context (exports, signatures, doc comments, imports) for the model
#    doing the actual translation -- this is the "structural extraction" step, not the
#    translation itself
jac run main.jac -- extract --id prefix-sum-computer --vscode-root /path/to/vscode

# 4. Once a Jac port exists, set jac_path in manifest.toml by hand, then:
jac run main.jac -- verify --id prefix-sum-computer
# `verify` only ever runs `jac check`/`jac test` against `jac_path` -- it never reads
# `test_jac_path` directly. This means the ported tests MUST live in a `<mod>.test.jac` annex
# (same basename as jac_path, `jac-testing`'s auto-discovered-by-`jac test <mod>.jac` form), not
# a standalone `<mod>_tests.jac` file -- the latter is a valid general Jac pattern but `verify`
# will silently report "no tests ran" and mark the module blocked if you use it here. An annex
# sees the base module's declarations without importing them; importing them anyway causes a
# circular-import error at test time. Set `test_jac_path` in the manifest to the annex's own path
# for bookkeeping/portability, even though `verify` doesn't read it back.

# 5. If verification fails and it's a real blocker (not something to just fix and retry):
jac run main.jac -- block --id prefix-sum-computer \
  --summary "short slug for the filename" \
  --error "paste the actual jac check/test output"
```

## Landing a scaffolded blocker on the tracking branch

`block` writes into `blocked/` (gitignored, local staging only) because the `tracking` branch
isn't checked out while this tool runs on `main` — git doesn't let you write across branches in
one working tree.

**First, fill in the `**Plan**: TODO` line by hand** — that's real judgment, not something to
automate. Then land it in one shot:

```bash
translator/land-blocker.sh translator/blocked/<file>.md
```

It checks out `tracking`, pulls, copies the file into `log/`, rebuilds the site, commits, pushes,
and switches back to whatever branch you started on — refusing to run if the Plan is still the
TODO placeholder, if there are uncommitted changes on your current branch (it won't stash), or if
a file of that name already exists on `tracking`. Deliberately plain bash, not Jac — see the
script's own header comment for why (it touches the observability backstop itself, the same
reasoning that kept `site/build.py` in Python).

## Automation tiers

Per the manifest's `risk_tier` field: `low`-risk modules (small, pure, narrow) can run through
`extract`→translate→`verify` as an unattended batch. `foundational` modules — right now, just
`piece-tree-base`, since the whole editor core depends on it — always get a supervised,
single-module session with deliberate human review before landing, and the piece-tree buffer
specifically also gets differential testing against upstream (see `docs/translator-strategy.md`),
not just ported-test parity.

## What's validated vs. what isn't yet

Validated end-to-end against real targets: `add` (all three current manifest entries, including
the false-positive fix on `pieceTreeBase.ts`'s "document." doc comment and the `--test-file`
override for its multi-file test mapping), `status`, `extract` (real structural JSON from
`prefixSumComputer.ts` and its test file), `verify` (both pass and fail paths, synthetic
fixtures), `block` (scaffolds a correctly-formatted tracker entry). 10 unit tests pass
(`jac test`).

Not yet done: the actual translation step (step 4 of the workflow — a human/model session
producing real Jac code for any of the three queued modules). That's deliberately out of scope
for this tool's implementation — it's a judgment-heavy session per `translator-strategy.md`, not
something the tooling automates.
