# M0 — Foundations

**Status**: complete, 2026-08-23

De-risked the two biggest architectural bets — root-graph-as-service-registry and the TS→Jac
translator — and stood up the tracker before building on top of either.

## Shipped
| PR | What |
|---|---|
| #4 | Translator tool: manifest/ledger, eligibility guard, structural extraction, verification gate, outcome recorder. 27 unit tests. |
| — | Challenge tracker live (`tracking` branch): markdown+frontmatter log, static dashboard, GitHub Actions deploy. |
| — | Service-registry spike (`internal/service-registry-spike/`): `ConfigService` + `CommandRegistry` + `FileTreeService` over the graph. |
| — | `prefix-sum-computer` translated and landed (48/48 ported tests). |
| — | `interval-tree` translated and landed (25/25 ported test blocks, 1281 upstream lines). |
| — | Minimal `jac.toml` scaffold (`kind = "cli"`), `src/` layout established. |

## Decisions
- [ADR 0001](../decisions/0001-rewrite-dont-mirror.md) — rewrite, don't mirror.
- [ADR 0002](../decisions/0002-redesign-translate-build-fresh.md) — redesign/translate/build-fresh procedure.
- [ADR 0003](../decisions/0003-graph-as-service-registry.md) — the graph as service registry.
- [ADR 0011](../decisions/0011-jac-first-tooling-with-named-exceptions.md) — Jac-first tooling (superseded by [0067](../decisions/0067-reuse-proven-libraries-for-solved-problems.md)).
- [ADR 0012](../decisions/0012-translator-supervision-by-risk-tier.md) — translator supervision by risk tier.

## Deviations from plan
- The eligibility guard's DOM-global heuristic false-positived on the word "document" in a comment; tightened to real call-shape patterns.
- `pieceTreeBase.ts` has no test file of its own — needed an explicit `--test-file` override.
- Manifest paths are relative to `--vscode-root`, not absolute (an early draft baked in a machine-specific path).
- Service-registry cache must be keyed by `jid(root)`, not a bare value — a non-keyed cache leaked one user's node into another's request.
- Cross-test cache leakage needed a `_reset_<x>_cache_for_tests()` hook, separate from the `jid(root)` keying fix.
- `obj` equality is identity, not the documented structural equality — every ported test compares fields directly instead.
- `node` and `include` are reserved Jac keywords; `interval_tree.jac` needed a whole-file rename from `node` to `nd` (~280 uses, 205 cascading parse errors).
- A method calling a bare name matching a module-level function of the same name recurses into itself instead of resolving to module scope (unlike TS). Fixed with an `_impl` suffix convention.

## Blockers logged
- `npm-interop-server-only-blocked` (resolved) — settled the extraction-language question.
- `entry-exit-keyword-doc-mismatch`, `keyword-collisions-common-python-names`, `argparse-type-callable-stub-mismatch` (resolved).
- `no-extension-sandbox`, `desktop-packaging-gap` (open, tracked for later phases).
- `chat-subsystem-scale`, `graph-fanout-dedup`, `file-move-schema-migration`, `lsp-dap-client-unresearched`, `jac2js-compiler-quirks` (strategic notes, relevant to M1+).
- `2026-08-23-service-registry-query-cost`, `2026-08-23-service-cache-test-isolation` (resolved).
- `2026-08-23-service-registry-snapshot-read-primitive` (open, lower priority).
- `2026-08-23-obj-equality-not-structural` (open).
- `2026-08-23-node-is-a-reserved-keyword` (resolved).

## Left open
Everything else carried into M1 as planned — piece-tree buffer translation and the first native
client component. See [`internal/service-registry-spike/README.md`](../../internal/service-registry-spike/README.md)
for the full spike writeup.
