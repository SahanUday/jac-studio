# 0024 — `jac browse` is a required verification step for UI-affecting work

- **Date**: 2026-08-25
- **Status**: accepted

## Decision

UI-affecting work is not verified until it has been loaded and interacted with in a real browser
via `jac browse`. `jac check`/`jac test`/compiled-bundle inspection/RPC probes are necessary but
never sufficient.

## Why

Every Phase 2 PR (#17–#25) shipped without a real rendered page. The first browser pass found
seven real bugs those checks structurally cannot catch — including that `main.jac` had never
imported the global stylesheet (zero CSS had ever shipped, since the project's inception) and
that the generated `CommandDialog` crashed the palette on every open
(`2026-08-25-shadcn-command-generator-missing-root-wrapper`).

## Consequences

The largest process deviation of Phase 2, and the source of the
`feedback_jac_studio_browser_verification` memory. Phase 4 kept proving it — a breadcrumb bar
shipped whose cursor tracking never worked, with a docstring describing behavior the code did not
implement. Manual verification against a real running server stays load-bearing.
