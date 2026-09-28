# 0081 — `jac.toml`'s pin tracks the latest published release, not a frozen version

- **Date**: 2026-09-28
- **Status**: accepted

## Decision

The root `jac.toml`/CI `jac` pin is bumped to the newest published release whenever one ships,
instead of staying frozen on whatever version M6 happened to pin. Each bump is a standing chore,
not a one-time event or its own numbered decision: rerun `jac check src` and `jac test src`
against the new pin, fix whatever new (correct, stricter) diagnostics it surfaces, and file
anything that's a genuine jac defect upstream rather than working around it. `internal/`
(archived/spike work) is permanently out of scope for this — it stays on whatever pin it last had
and is never bumped.

True floating-`main` tracking is not adopted: `jaseci`'s `dev` pre-release tag is stale (points to
a fixed old commit, not continuously rebuilt), so tracking literal `main` in CI would mean building
`jac` from source every run instead of downloading a release asset — slower and less reproducible
than pinning the latest tag.

## Why

The original `v0.37.3` pin drifted ~300 commits behind `main` with no plan to revisit it
(see prior [roadmap.md](../roadmap.md) carry-over note). A frozen pin doesn't just get stale about
`main` — it means the project stops benefiting from real compiler fixes and stricter, correct
diagnostics indefinitely. Treating the bump as a recurring chore instead of a discrete
"upgrade project" makes staying current the default, not something that needs deciding again.

## Consequences

- Bumping is routine: update `jac-version` in the root `jac.toml` and `JAC_VERSION` in
  `ci.yml`, then audit — no new ADR needed per bump unless the audit itself surfaces a decision
  worth recording (e.g. a real upstream defect requiring a workaround, or a diagnostic that changes
  how a subsystem must be written).
- `jac check` in CI stays scoped to `jac check src` (not `jac check .`) specifically so `internal/`
  never blocks a bump — reviving an archived/spike project means bumping its own `jac.toml` pin
  first, on its own schedule.
- The first bump under this policy (`0.37.3` → `0.37.23`, 2026-09-28) fixed seven `src/` files for
  three now-stricter diagnostics — unnamed edge endpoints (`E2086`), bare generic types (`E1036`),
  and `Generator`-annotated functions using the `report`-a-generator streaming pattern that only
  ever implicitly return `None` (`E1004`) — and found one genuine regression, not worked around: a
  client-placed module's test fails to compile only when `jac test` discovers it via directory
  traversal alongside another `.test.jac` file. Filed upstream
  ([jaseci-labs/jac#9606](https://github.com/jaseci-labs/jac/issues/9606), tracker entry
  `2026-09-28-client-test-directory-discovery-breaks-cross-file-binding`); CI shows this one
  failure honestly until it's fixed rather than skipping/xfail-ing it.
